# Local-Dev Backend Migration: Supabase → Django Ninja

**Status:** Design approved, awaiting implementation plan
**Date:** 2026-05-21
**ClickUp Task:** [86ba1xwjk](https://app.clickup.com/t/86ba1xwjk)
**Scope:** Phase 1 — local development only. Production continues to use Supabase. The new backend is designed so it can scale to production in a future phase, but production migration is out of scope here.

## 1. Motivation

The LucidBoard Swift app currently uses Supabase for auth, Postgres, and embedding generation (via an Edge Function). Local development requires the full Supabase Docker stack (~8 containers). This task replaces that stack with a lightweight, self-hosted Django Ninja backend that:

- Talks to a single Postgres + pgvector container
- Exposes the same data and AI surface the Swift app uses today
- Lets a developer hack on the iPad/Mac UI without depending on a remote Supabase project or running the full Supabase Docker stack
- Keeps the Supabase code path intact and selectable, so production behavior is unchanged

## 2. Architecture

```
┌──────────────────────────────────────┐
│         LucidBoard (SwiftUI)         │
│                                      │
│  AppRepository (protocol)            │
│  ├── SupabaseRepository (wraps existing SupabaseService)
│  └── LocalAPIRepository (new — URLSession + JSON)
└────────────────┬─────────────────────┘
                 │ HTTPS + Bearer JWT
                 ▼
┌──────────────────────────────────────┐
│  Django Ninja API (`backend/`)       │
│  ├── auth/    (anonymous JWT mint)   │
│  ├── boards/  (CRUD)                 │
│  ├── notes/   (CRUD + embed-on-write)│
│  ├── profiles/(get/upsert)           │
│  └── rpc/     (match_notes)          │
└────────────────┬─────────────────────┘
                 │ psycopg + django-pgvector
                 ▼
┌──────────────────────────────────────┐
│  Postgres 17 + pgvector (Docker)     │
│  Schema: boards, notes, profiles,    │
│          users, match_notes()        │
└──────────────────────────────────────┘
```

### Repository layout

```
LucidBoard/
├── backend/                            ← NEW
│   ├── docker-compose.yml              postgres+pgvector only
│   ├── pyproject.toml                  uv-managed, ruff, ty
│   ├── manage.py
│   ├── .env.example
│   ├── lucidboard_api/                 Django project
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── asgi.py
│   ├── core/                           Django app
│   │   ├── models.py                   Board, Note, Profile, User
│   │   ├── auth.py                     JWT mint + JWTBearer auth class
│   │   ├── embeddings.py               Gemini client wrapper
│   │   └── migrations/                 Django migrations (port SCHEMA.sql)
│   ├── api/                            Django Ninja routes
│   │   ├── schemas.py                  Pydantic request/response models
│   │   ├── routers/
│   │   │   ├── auth.py
│   │   │   ├── boards.py
│   │   │   ├── notes.py
│   │   │   ├── profiles.py
│   │   │   └── rpc.py
│   │   └── tests/
│   └── scripts/
│       └── smoke.sh                    end-to-end smoke test
├── LucidBoard/                         existing Xcode project
│   └── LucidBoard/Services/
│       ├── AppRepository.swift         NEW — protocol
│       ├── SupabaseRepository.swift    NEW — wraps existing SupabaseService
│       ├── LocalAPIRepository.swift    NEW — URLSession + JSON to Django
│       └── SupabaseService.swift       existing, internal to SupabaseRepository
└── supabase/                           existing, unchanged
```

The Django backend lives in `backend/` as a peer to the Xcode project so the Python toolchain doesn't pollute the Swift workspace, and a future fully-remote prod deploy can lift `backend/` out into its own repo if needed.

## 3. Backend Components

### 3.1 `core/models.py` — Django ORM

Mirrors `SCHEMA.sql` 1:1 so SQL queries port directly:

- **`User`** — minimal custom user keyed by UUID. Replaces Supabase's `auth.users`. Fields: `id (UUID PK), is_anonymous (bool), created_at`. No password column (anonymous-only auth in Phase 1).
- **`Board`** — `id (UUID PK), user_id (FK→User), title, background_color, background_layout, created_at, updated_at`.
- **`Note`** — all fields from SCHEMA.sql. Uses `pgvector.django.VectorField(dimensions=768)` for `embedding`. `checklist_items: JSONField`.
- **`Profile`** — `id (OneToOne→User PK), settings (JSONField), updated_at`.

### 3.2 `core/auth.py` — JWT minting & validation

Tokens use the **same Supabase shape** so Swift can decode them without special handling:

```
HS256
{
  "sub": "<user-uuid>",
  "role": "authenticated",
  "aud": "authenticated",
  "iat": <unix>,
  "exp": <unix + 3600>,
  "is_anonymous": true
}
```

- `mint_anonymous_token() -> (User, str)` — creates a User row and returns the signed JWT.
- `JWTBearer(HttpBearer)` — Ninja auth class. Verifies HS256 with `settings.JWT_SECRET`, returns the `User`. All board/note/profile routes use `auth=JWTBearer()`.

Signing key is read from `JWT_SECRET` env var.

### 3.3 `core/embeddings.py` — Gemini wrapper

Single function `generate_embedding(text: str) -> list[float] | None`:

- Returns `None` if `text.strip() == ""`.
- Calls Gemini `text-embedding-004` (matches the existing Edge Function).
- On API error: logs and returns `None` rather than failing the note write. Graceful degradation — the note still saves with `embedding=null`.

### 3.4 `api/routers/` — endpoints

| Method | Path | Purpose | Mirrors |
|---|---|---|---|
| `POST` | `/auth/v1/signup?anonymous=true` | mint anonymous JWT | `signInAnonymously()` |
| `GET` | `/api/boards` | list user's boards | `fetchBoards` |
| `PATCH` | `/api/boards/{id}` | update board | `updateBoard` |
| `GET` | `/api/boards/{id}/notes` | list notes for board | `fetchNotes(boardId:)` |
| `PUT` | `/api/notes/{id}` | upsert note (embed-on-write) | `upsertNote` |
| `DELETE` | `/api/notes/{id}` | delete | `deleteNote` |
| `GET` | `/api/profile` | get current user profile | `fetchProfile` |
| `PUT` | `/api/profile` | upsert profile | `updateProfile` |
| `POST` | `/api/rpc/match_notes` | run clustering | `autoOrganize` |

- `PUT /api/notes/{id}` (not `POST`) because Swift generates the UUID client-side — making create/update idempotent on the same path matches what Supabase's `.upsert()` already does.
- `match_notes` is exposed as a real HTTP endpoint that calls the unchanged Postgres function via `cursor.execute("SELECT * FROM match_notes(%s)", [board_id])`.
- `GET /api/profile` auto-creates a `Profile` row with default settings on first call, so the Swift client never gets a 404 for a missing profile (matches the current `fetchProfile() -> AppSettings?` shape where `nil` means "not yet set").

## 4. Data Flow

### 4.1 First app launch (anonymous sign-in)

```
Swift App        LocalAPIRepository      Django Ninja
  │ signInAnonymously()  │                      │
  │ ──────────────────► │  POST /auth/v1/signup │
  │                     │  ?anonymous=true      │
  │                     │ ───────────────────►  │
  │                     │                       │ create User(is_anonymous=true)
  │                     │                       │ mint HS256 JWT (sub=user.id)
  │                     │  200 {access_token,user}
  │                     │ ◄──────────────────── │
  │                     │  store in Keychain    │
  │ ok                  │                       │
  │ ◄────────────────── │                       │
```

JWT is cached in Keychain (`LocalAPIRepository.tokenStore`), attached as `Authorization: Bearer <jwt>` on every subsequent request. On 401 (expired token), `LocalAPIRepository` performs a one-time silent re-sign-in and retries the failing request once. If retry also fails, the error surfaces to the caller. Phase-1 simplification: re-sign-in mints a *new* anonymous user; we do not yet implement refresh tokens or durable-anonymous-user binding. This is acceptable for local dev.

### 4.2 Create/edit a note (embed-on-write)

```
Swift          LocalAPIRepository    Django Ninja         Postgres
  │ upsertNote(note)   │                  │                    │
  │ ────────────────► │  PUT /api/notes/{id}                  │
  │                   │ ──────────────► │  validate JWT       │
  │                   │                 │  check user owns    │
  │                   │                 │   parent board      │
  │                   │                 │  generate_embedding │
  │                   │                 │   (Gemini ~150ms)   │
  │                   │                 │  UPSERT note        │
  │                   │                 │   incl. vector      │
  │                   │                 │ ──────────────────► │
  │                   │                 │ ◄────────────────── │
  │                   │  200 {note}     │                     │
  │                   │ ◄────────────── │                     │
```

**Skip-rule** (matches existing Edge Function behavior): if it's an update *and* `content_text` is unchanged from the stored row, the embedding call is skipped and the existing embedding is reused. The Ninja view fetches the current row first; if content text is byte-equal, skip Gemini.

### 4.3 Auto-Organize (clustering)

```
Swift          LocalAPIRepository    Django Ninja         Postgres
  │ autoOrganize(board)│                 │                    │
  │ ────────────────► │  POST /api/rpc/match_notes           │
  │                   │  {board_uuid: "..."}                 │
  │                   │ ──────────────► │ ownership check    │
  │                   │                 │ cursor.execute(    │
  │                   │                 │  "SELECT * FROM    │
  │                   │                 │   match_notes(%s)",│
  │                   │                 │   [board_uuid])    │
  │                   │                 │ ─────────────────► │
  │                   │                 │ ◄───────────────── │
  │                   │  200 [{id,new_x,new_y}]              │
  │                   │ ◄────────────── │                    │
```

The Python view is roughly 5 lines. The pgvector clustering logic stays in SQL exactly as it is today.

### 4.4 Authorization (every request)

The current Supabase setup uses RLS policies (`auth.uid() = id`). We move that check into application code:

- A helper `assert_owns_board(user, board_id)` runs at the top of every board/note route.
- For list endpoints: every query is filtered by `user_id=request.auth.id`, via a `UserScopedManager` on the model.

This is a deliberate move — RLS is necessary in Supabase because the client talks directly to Postgres. With an application server in front, explicit ownership checks are easier to read, test, and trace.

### 4.5 Behavioral change from Supabase

Embeddings are **synchronous on note write** rather than async via DB trigger → Edge Function. This adds ~100-300ms of latency to note writes that touch `content_text`, but eliminates: pg_net extension, trigger function, service-role-key plumbing, the entire Edge Function (`generate-embedding/`), and a class of "embedding silently failed and you don't know" bugs. The current Edge Function path is fire-and-forget — if Gemini 500s, the note still saves but its embedding stays null forever. The new path logs the failure explicitly; a retry job can be added in a follow-up if needed.

## 5. Swift Client Integration

### 5.1 `AppRepository.swift` — the protocol

```swift
protocol AppRepository {
    // Auth
    func signInAnonymously() async throws
    var isSignedIn: Bool { get }

    // Boards
    func fetchBoards() async throws -> [Board]
    func updateBoard(_ board: Board) async throws

    // Notes
    func fetchNotes(boardId: UUID) async throws -> [Note]
    func upsertNote(_ note: Note) async throws
    func deleteNote(id: UUID) async throws

    // Profile
    func fetchProfile() async throws -> AppSettings?
    func updateProfile(settings: AppSettings) async throws

    // AI
    func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)]
}
```

This is the existing `SupabaseService` surface, lifted verbatim into a protocol. Method signatures stay identical so ViewModel call sites need zero changes.

### 5.2 Two implementations

- **`SupabaseRepository`** — thin wrapper delegating to `SupabaseService.shared`. ~30 lines of boilerplate. Zero behavior change.
- **`LocalAPIRepository`** — new. Uses `URLSession` + stock `JSONDecoder`. The existing `Note`/`Board` models already declare explicit `CodingKeys` with snake-case mappings, so the same JSON shape works on both backends.

### 5.3 `AppRepositoryFactory` — selection

```swift
enum BackendKind { case supabase, localAPI }

enum AppRepositoryFactory {
    static func make() -> AppRepository {
        let kind: BackendKind = (Bundle.main.object(
            forInfoDictionaryKey: "BACKEND_KIND") as? String) == "local"
                ? .localAPI : .supabase
        switch kind {
        case .supabase: return SupabaseRepository()
        case .localAPI: return LocalAPIRepository(
            baseURL: Bundle.main.object(forInfoDictionaryKey: "LOCAL_API_URL")
                     as? String ?? "http://127.0.0.1:8000")
        }
    }
}
```

- Selected at app launch via xcconfig — same mechanism as the current `SUPABASE_URL`/`SUPABASE_KEY`.
- `Sample.xcconfig` gains `BACKEND_KIND = local` and `LOCAL_API_URL = http://127.0.0.1:8000` as documented defaults.
- ViewModels grab the repo from a single injection point in `LucidBoardApp.swift` via `.environment(\.appRepository, repo)`. After this refactor, there should be no scattered `SupabaseService.shared` references.

### 5.4 Token storage

A small `TokenStore` actor stores the JWT and user UUID in Keychain (Apple's `Security` framework, ~40 lines). On launch, if a token exists and is unexpired, `signInAnonymously()` is skipped. On 401 mid-request, the repository triggers one-time re-sign-in and retries the failing request once.

### 5.5 What changes in existing code

1. `SupabaseService.shared` references in ViewModels are replaced with the injected `AppRepository`. This is the only meaningful Swift refactor.
2. `LucidBoardApp.swift` instantiates the repo via `AppRepositoryFactory.make()` once and injects it.
3. `Config.xcconfig` / `Sample.xcconfig` gain two keys.

Models, Views, the canvas, and PencilKit code are untouched.

## 6. Error Handling

### 6.1 Django side

A single Ninja exception handler maps internal errors to JSON `{detail, code}`:

| Condition | HTTP | `code` |
|---|---|---|
| Missing/invalid JWT | 401 | `unauthorized` |
| Token expired | 401 | `token_expired` |
| User doesn't own the resource | 404 | `not_found` (intentional — don't leak existence) |
| Validation error (Pydantic) | 422 | `validation_error` |
| Gemini call fails during note write | 200 | — (note still saved, embedding=null, logged) |
| `match_notes` on board with 0 embedded notes | 200 | — (returns `[]`) |
| Postgres connection lost | 503 | `unavailable` |

### 6.2 Swift side

```swift
enum LocalAPIError: Error {
    case unauthorized            // triggers one-time re-signin + retry
    case notFound
    case validation(String)
    case network(URLError)
    case server(status: Int, code: String?)
}
```

ViewModels already handle generic `Error` from `SupabaseService` — they don't need to differentiate. The retry-on-401 logic stays inside the repository.

## 7. Testing

### 7.1 Backend (`backend/api/tests/`)

pytest + `pytest-django` + `httpx` test client.

- `test_auth.py` — anonymous signup mints valid JWT; JWT round-trips; expired token returns 401.
- `test_boards.py` — list/update enforce ownership; 404 for other users' boards.
- `test_notes.py` — upsert generates embedding (Gemini mocked); unchanged content skips re-embedding; ownership enforced via parent board.
- `test_profiles.py` — get/upsert; auto-creates profile if missing.
- `test_rpc.py` — `match_notes` returns positions for a board with 3 mocked-embedding notes (real Postgres + pgvector via `pytest-postgresql` or testcontainers).

Coverage target: every router function has at least one happy-path test and one auth-failure test.

### 7.2 Swift (`LucidBoardTests/`)

- `LocalAPIRepositoryTests.swift` — mock `URLSession` via `URLProtocol` subclass; assert request shapes (URL, headers, body); assert response decoding for each endpoint.
- `AppRepositoryFactoryTests.swift` — factory returns correct impl per `BACKEND_KIND`.

The existing Supabase path is not re-tested (unchanged), but verified to still compile and launch.

### 7.3 Smoke test

A single `backend/scripts/smoke.sh` boots `docker compose up -d`, runs `manage.py migrate`, hits `POST /auth/v1/signup`, creates a board, creates a note, lists notes, deletes the note. Exit 0 if all pass. Runs in CI.

## 8. Developer Experience

`backend/README.md` documents a 4-command bootstrap:

```bash
cd backend
docker compose up -d              # postgres+pgvector
uv sync                           # install Python deps
uv run manage.py migrate          # apply schema
uv run manage.py runserver        # http://127.0.0.1:8000
```

Then in Xcode: set `BACKEND_KIND = local` in `Config.xcconfig` and build/run.

`GEMINI_API_KEY` is loaded from a `.env` file (gitignored). Without it, the embedding code logs a warning and stores `null` — the app keeps working; auto-organize falls back to laying un-embedded notes out as singleton positions (matches the `match_notes` SQL behavior for notes with `embedding IS NULL`). This matches current Edge Function behavior and is important for local dev: a developer hacking on canvas UI shouldn't need a valid Gemini key to run the app.

## 9. Out of Scope (Explicit)

- Realtime/WebSockets (parity with current code — not yet implemented on Swift side either).
- Production deployment (no Dockerfile-for-prod, no `gunicorn`/`uvicorn` config beyond dev).
- Migration of existing Supabase data into the local DB (local dev starts empty).
- Multi-user / real-account auth (anonymous only in Phase 1).
- Removal of the `supabase/` directory (stays — local Supabase remains an option; prod still uses it).

## 10. Open Questions

None at this time. All open questions resolved during brainstorming.

## 11. Success Criteria

- A developer can clone the repo, run the 4-command bootstrap, set `BACKEND_KIND=local`, build the Xcode project, and create/edit/cluster notes with no remote Supabase project required.
- All backend pytest tests pass.
- All Swift unit tests pass.
- The smoke test exits 0.
- With `BACKEND_KIND=supabase` (default), the app behaves identically to the pre-migration code.
