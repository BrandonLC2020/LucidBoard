# Local DB → Firestore Emulator Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `backend/` local-dev Django+Postgres/pgvector data layer with Google Cloud Firestore, run locally via the Firestore Local Emulator Suite, so local dev matches the shape of the eventual GCP production stack.

**Architecture:** `backend/` stays a Django + django-ninja HTTP API (routing, JWT auth, request/response schemas are unchanged), but every place that touched `django.db` (ORM models, managers, migrations, raw SQL RPC) is replaced with a thin `google-cloud-firestore` repository layer talking to the Firestore emulator via the standard `FIRESTORE_EMULATOR_HOST` env var. The Postgres `match_notes` PL/pgSQL function is ported to a pure-Python equivalent (`core/matching.py`) since there is no SQL layer anymore.

**Tech Stack:** Django 5, django-ninja, `google-cloud-firestore` (Python client), Firebase CLI (`firebase-tools`) for the emulator, pytest + pytest-django (Client only, no DB fixture).

## Global Constraints

- ClickUp task 86bb077ug: "transition local database to Google Cloud Firestore and use the Emulator." Scope is **local dev only** — production still runs Supabase until a separate future "prod cutover" task flips `AppRepositoryFactory`'s Release default and updates `supabase/` project config. Do not touch `frontend/LucidBoard/Services/SupabaseRepository.swift` or the `supabase/` directory in this plan.
- The Swift app's `LocalAPIRepository` talks to `backend/` over the existing REST surface (`README.md`'s API table). Every router's request/response shape (via `api/schemas.py`) must stay byte-identical — the Swift client is not being changed, so the HTTP contract is the invariant this whole migration must preserve.
- No production GCP project or real credentials are needed for this plan — the emulator runs against a fake project id (`demo-lucidboard`) and needs no `GOOGLE_APPLICATION_CREDENTIALS`.
- Preserve existing behavior for: anonymous-only JWT auth, per-user board/note scoping (404 on cross-user access, not 403), embedding-reuse-on-unchanged-text logic in `upsert_note`, and the `match_notes` clustering algorithm's observable behavior (same inputs → notes grouped the same way, valid float positions returned).
- Follow existing repo conventions: `from __future__ import annotations` at the top of every backend module, `ruff` line-length 100, type-annotated function signatures.

---

## File Structure

| File | Responsibility |
|---|---|
| `backend/firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json` (new) | Firebase CLI config so `firebase emulators:start` boots a Firestore emulator on a fixed port. |
| `backend/docker-compose.yml` | Deleted — Postgres container no longer needed. |
| `backend/.env.example`, `backend/README.md` | Updated bootstrap instructions (emulator instead of `docker compose` + `migrate`). |
| `backend/pyproject.toml` | Drop `psycopg`, `pgvector`, `pytest-postgresql`; add `google-cloud-firestore`. |
| `backend/lucidboard_api/settings.py` | Drop `DATABASES`, `AUTH_USER_MODEL`, `django.contrib.auth`/`contenttypes`; add `FIRESTORE_PROJECT_ID` / `FIRESTORE_EMULATOR_HOST` passthrough settings. |
| `backend/core/firestore_client.py` (new) | Lazy singleton `google.cloud.firestore.Client`, pointed at the emulator via env var — the one place that constructs a Firestore client. |
| `backend/core/models.py` | Django `Model` subclasses → plain `@dataclass`es (`User`, `Board`, `Note`, `Profile`). No more ORM, no more `pgvector.django`. |
| `backend/core/repository.py` (new, replaces `core/managers.py`) | All Firestore reads/writes: CRUD functions per entity, replacing `Model.objects.*` call sites. |
| `backend/core/matching.py` (new) | Pure-Python port of the `match_notes(board_uuid)` Postgres function. |
| `backend/core/auth.py` | `mint_anonymous_token` / `decode_token` call `core/repository.py` instead of the ORM. |
| `backend/api/routers/*.py` | Swap ORM/`get_object_or_404` calls for repository calls + manual 404s. |
| `backend/core/migrations/` | Deleted — Firestore is schemaless, nothing to migrate. |
| `backend/core/managers.py` | Deleted — superseded by `core/repository.py`. |
| `backend/api/conftest.py`, `backend/conftest.py` (new) | Emulator-backed test fixtures: assert the emulator is running, wipe all documents between tests, rebuild `auth_client` on top of the new repository. |
| `backend/api/tests/*.py` | Rewritten to call `core/repository.py` instead of the Django ORM. |
| `backend/scripts/smoke.sh` | Swap the `psql`-based board seed for a small Python script that writes directly to the emulator via `google-cloud-firestore`. |

---

### Task 1: Firestore Emulator infra + dependency swap

**Files:**
- Create: `backend/firebase.json`
- Create: `backend/.firebaserc`
- Create: `backend/firestore.rules`
- Create: `backend/firestore.indexes.json`
- Delete: `backend/docker-compose.yml`
- Modify: `backend/.env.example`
- Modify: `backend/pyproject.toml`
- Modify: `backend/README.md`

**Interfaces:**
- Produces: `FIRESTORE_EMULATOR_HOST` (default `127.0.0.1:8080`) and `FIRESTORE_PROJECT_ID` (default `demo-lucidboard`) as the two env vars every later task reads.

- [ ] **Step 1: Add Firebase CLI config**

`backend/.firebaserc`:
```json
{
  "projects": {
    "default": "demo-lucidboard"
  }
}
```

`backend/firebase.json`:
```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "emulators": {
    "firestore": {
      "port": 8080
    },
    "ui": {
      "enabled": true,
      "port": 4000
    }
  }
}
```

`backend/firestore.rules` (server-side Admin SDK access via the emulator ignores rules entirely, but the Firebase CLI refuses to start the emulator without a rules file, so keep it maximally locked-down):
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

`backend/firestore.indexes.json` (empty for now — the emulator does not enforce composite-index requirements the way production Firestore does, so `boards` queries filtering on `user_id` and ordering by `updated_at` work locally without one; a real composite index must be added here before the prod cutover):
```json
{
  "indexes": [],
  "fieldOverrides": []
}
```

- [ ] **Step 2: Remove the Postgres container**

```bash
rm backend/docker-compose.yml
```

- [ ] **Step 3: Update env template**

Replace the contents of `backend/.env.example`:
```
DJANGO_SECRET_KEY=dev-only-change-me
JWT_SECRET=dev-only-change-me-jwt
JWT_EXPIRY_SECONDS=3600
FIRESTORE_PROJECT_ID=demo-lucidboard
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
GEMINI_API_KEY=
```

- [ ] **Step 4: Swap backend dependencies**

In `backend/pyproject.toml`, change the `dependencies` list from:
```toml
dependencies = [
    "django>=5.0,<6.0",
    "django-ninja>=1.3",
    "psycopg[binary]>=3.2",
    "pgvector>=0.3.6",
    "pyjwt>=2.9",
    "google-generativeai>=0.8",
    "python-dotenv>=1.0",
]
```
to:
```toml
dependencies = [
    "django>=5.0,<6.0",
    "django-ninja>=1.3",
    "google-cloud-firestore>=2.19",
    "pyjwt>=2.9",
    "google-generativeai>=0.8",
    "python-dotenv>=1.0",
]
```

And change the `dev` dependency group from:
```toml
[dependency-groups]
dev = [
    "pytest>=8.3",
    "pytest-django>=4.9",
    "pytest-postgresql>=6.1",
    "httpx>=0.27",
    "ruff>=0.6",
    "ty>=0.0.1a1",
]
```
to:
```toml
[dependency-groups]
dev = [
    "pytest>=8.3",
    "pytest-django>=4.9",
    "httpx>=0.27",
    "requests>=2.32",
    "ruff>=0.6",
    "ty>=0.0.1a1",
]
```
(`requests` is added for the emulator's document-clearing REST call used by the test fixtures in Task 3.)

Run: `cd backend && uv sync`
Expected: resolves cleanly, `psycopg`/`pgvector`/`pytest-postgresql` gone from `uv.lock`, `google-cloud-firestore` and `requests` present.

- [ ] **Step 5: Update README bootstrap instructions**

Replace the `## Bootstrap` section of `backend/README.md`:
```markdown
## Bootstrap

```bash
cp .env.example .env
# Optional: set GEMINI_API_KEY in .env (without it, embeddings are null)
npm install -g firebase-tools     # one-time, if not already installed
firebase emulators:start --only firestore --project demo-lucidboard  # :8080, UI on :4000
uv sync
uv run manage.py runserver        # http://127.0.0.1:8000
```
```

And update the header line from `Lightweight Django Ninja API that replaces Supabase for local development.` to also mention Firestore:
```markdown
Lightweight Django Ninja API that replaces Supabase for local development,
backed by the Firestore Local Emulator instead of a local database of
its own.
```

- [ ] **Step 6: Verify the emulator boots**

Run: `cd backend && firebase emulators:start --only firestore --project demo-lucidboard`
Expected: log line `✔  firestore: Firestore Emulator UI websocket is running on 9150.` (or similar) and `All emulators ready! It is now safe to connect.` Leave it running in a terminal for the rest of this plan — every later task's tests need it up. Stop with Ctrl-C when done.

- [ ] **Step 7: Commit**

```bash
git add backend/firebase.json backend/.firebaserc backend/firestore.rules backend/firestore.indexes.json backend/.env.example backend/pyproject.toml backend/uv.lock backend/README.md
git rm backend/docker-compose.yml
git commit -m "chore(backend): swap Postgres docker-compose for Firestore Emulator config"
```

---

### Task 2: Firestore client singleton + Django settings cleanup

**Files:**
- Create: `backend/core/firestore_client.py`
- Modify: `backend/lucidboard_api/settings.py`

**Interfaces:**
- Consumes: `FIRESTORE_PROJECT_ID`, `FIRESTORE_EMULATOR_HOST` env vars from Task 1.
- Produces: `get_client() -> google.cloud.firestore.Client` — the only Firestore entry point later tasks import.

- [ ] **Step 1: Write `core/firestore_client.py`**

```python
from __future__ import annotations

from google.cloud import firestore

from django.conf import settings

_client: firestore.Client | None = None


def get_client() -> firestore.Client:
    """Return a process-wide Firestore client.

    Routes to the emulator automatically when `FIRESTORE_EMULATOR_HOST` is
    set in the environment (the google-cloud-firestore client checks this
    var itself) — no credentials are needed against the emulator.
    """
    global _client
    if _client is None:
        _client = firestore.Client(project=settings.FIRESTORE_PROJECT_ID)
    return _client


def reset_client_for_tests() -> None:
    """Drop the cached client so tests can rebuild it against a fresh emulator."""
    global _client
    _client = None
```

- [ ] **Step 2: Rewrite `settings.py`**

Replace the whole file:
```python
import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-only-change-me")
JWT_SECRET = os.environ.get("JWT_SECRET", "dev-only-change-me-jwt")
JWT_EXPIRY_SECONDS = int(os.environ.get("JWT_EXPIRY_SECONDS", "3600"))
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

FIRESTORE_PROJECT_ID = os.environ.get("FIRESTORE_PROJECT_ID", "demo-lucidboard")
# google-cloud-firestore reads FIRESTORE_EMULATOR_HOST directly from the
# environment; re-export it here only so `.env` is the single source of
# truth even though load_dotenv already populated os.environ.
FIRESTORE_EMULATOR_HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "")
if FIRESTORE_EMULATOR_HOST:
    os.environ.setdefault("FIRESTORE_EMULATOR_HOST", FIRESTORE_EMULATOR_HOST)

DEBUG = True
ALLOWED_HOSTS = ["*"]

INSTALLED_APPS = [
    "core",
]

MIDDLEWARE = [
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "lucidboard_api.urls"
WSGI_APPLICATION = "lucidboard_api.wsgi.application"
ASGI_APPLICATION = "lucidboard_api.asgi.application"

USE_TZ = True
TIME_ZONE = "UTC"
```

Note what's gone: `DATABASES`, `AUTH_USER_MODEL`, `DEFAULT_AUTO_FIELD`, `django.contrib.contenttypes`/`django.contrib.auth` from `INSTALLED_APPS`, and the `urlparse`-based `DATABASE_URL` parsing. Nothing in this app uses Django's session/permission/admin machinery, so those apps were only ever there to support `AUTH_USER_MODEL` — which no longer points at an ORM model.

- [ ] **Step 3: Verify Django still boots with no database configured**

Run: `cd backend && uv run python -c "import django, os; os.environ.setdefault('DJANGO_SETTINGS_MODULE','lucidboard_api.settings'); django.setup(); print('ok')"`
Expected: `ok` — this will fail loudly right now if anything still imports `core.models` and expects Django `Model` classes, which is expected until Task 3 lands. If it fails with an unrelated error (e.g. about `AUTH_USER_MODEL` or `DATABASES`), fix `settings.py` before moving on.

- [ ] **Step 4: Commit**

```bash
git add backend/core/firestore_client.py backend/lucidboard_api/settings.py
git commit -m "feat(backend): add Firestore client singleton, drop Postgres settings"
```

---

### Task 3: Users, Profile, dataclass models, and the test harness

This task lands the new `core/models.py` dataclasses, the `core/repository.py` module (users + profiles slice), rewires `core/auth.py`, and — critically — replaces the emulator-agnostic test fixtures so every later task can rely on them.

**Files:**
- Modify: `backend/core/models.py`
- Create: `backend/core/repository.py`
- Modify: `backend/core/auth.py`
- Modify: `backend/api/routers/profiles.py`
- Delete: `backend/core/managers.py`
- Create: `backend/conftest.py`
- Modify: `backend/api/conftest.py`
- Modify: `backend/api/tests/test_health.py`
- Modify: `backend/api/tests/test_auth.py`
- Modify: `backend/api/tests/test_auth_module.py`
- Modify: `backend/api/tests/test_profiles.py`

**Interfaces:**
- Consumes: `get_client()` from `core/firestore_client.py` (Task 2).
- Produces: `User`, `Profile` dataclasses (`core/models.py`); `create_anonymous_user() -> User`, `get_user(user_id: UUID) -> User | None`, `get_profile(user_id: UUID) -> Profile | None`, `upsert_profile(user_id: UUID, settings: dict) -> Profile` (`core/repository.py`) — later tasks add `Board`/`Note` functions to the same two files.

- [ ] **Step 1: Rewrite the `User` and `Profile` parts of `core/models.py`**

`core/models.py` (full file — `Board`/`Note` classes added in Task 4/5, so for now this only has `User`/`Profile`; leave the file as just these two so Task 4/5 append to it):
```python
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID


@dataclass
class User:
    id: UUID
    is_anonymous_user: bool = True
    created_at: datetime | None = None

    @property
    def is_authenticated(self) -> bool:  # ninja/django use this
        return True

    @property
    def is_anonymous(self) -> bool:
        return self.is_anonymous_user


@dataclass
class Profile:
    user_id: UUID
    settings: dict = field(default_factory=dict)
    updated_at: datetime | None = None
```

- [ ] **Step 2: Write the users/profiles slice of `core/repository.py`**

```python
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from core.firestore_client import get_client
from core.models import Profile, User

USERS = "users"
PROFILES = "profiles"


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


# --- Users ---

def create_anonymous_user() -> User:
    user = User(id=uuid.uuid4(), is_anonymous_user=True, created_at=_now())
    get_client().collection(USERS).document(str(user.id)).set(
        {"is_anonymous_user": user.is_anonymous_user, "created_at": user.created_at}
    )
    return user


def get_user(user_id: uuid.UUID) -> User | None:
    snap = get_client().collection(USERS).document(str(user_id)).get()
    if not snap.exists:
        return None
    data = snap.to_dict()
    return User(
        id=user_id,
        is_anonymous_user=data["is_anonymous_user"],
        created_at=data["created_at"],
    )


# --- Profiles ---

def get_profile(user_id: uuid.UUID) -> Profile | None:
    snap = get_client().collection(PROFILES).document(str(user_id)).get()
    if not snap.exists:
        return None
    data = snap.to_dict()
    return Profile(user_id=user_id, settings=data.get("settings", {}), updated_at=data.get("updated_at"))


def upsert_profile(user_id: uuid.UUID, settings: dict) -> Profile:
    now = _now()
    get_client().collection(PROFILES).document(str(user_id)).set(
        {"settings": settings, "updated_at": now}
    )
    return Profile(user_id=user_id, settings=settings, updated_at=now)
```

- [ ] **Step 3: Rewrite `core/auth.py`**

```python
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
from django.conf import settings
from ninja.security import HttpBearer

from core.models import User
from core.repository import create_anonymous_user, get_user


def mint_anonymous_token() -> tuple[User, str]:
    """Create a fresh anonymous user and return (user, signed_jwt)."""
    user = create_anonymous_user()
    now = datetime.now(tz=timezone.utc)
    payload = {
        "sub": str(user.id),
        "role": "authenticated",
        "aud": "authenticated",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=settings.JWT_EXPIRY_SECONDS)).timestamp()),
        "is_anonymous": True,
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")
    return user, token


def decode_token(token: str) -> User:
    """Verify a JWT and return the User it identifies.

    Raises jwt.InvalidTokenError subclasses on failure
    (InvalidSignatureError, ExpiredSignatureError, ...), and ValueError
    if the token's subject no longer exists in Firestore.
    """
    payload = jwt.decode(
        token, settings.JWT_SECRET, algorithms=["HS256"], audience="authenticated"
    )
    user = get_user(payload["sub"])
    if user is None:
        raise ValueError(f"user {payload['sub']} not found")
    return user


class JWTBearer(HttpBearer):
    """Ninja auth class. Returns the User on success, None on failure."""

    def authenticate(self, request, token: str) -> User | None:
        try:
            user = decode_token(token)
        except (jwt.InvalidTokenError, ValueError):
            return None
        request.user = user
        return user
```

Note `get_user` takes a `UUID`, but `payload["sub"]` is a `str` — `get_user` builds the document path with `str(user_id)` either way, but to keep the type contract honest, change `get_user`'s signature to accept `uuid.UUID | str` OR convert at the call site. Convert at the call site (simpler, keeps `core/repository.py` strictly typed):
```python
    user = get_user(uuid.UUID(payload["sub"]))
```
Add `import uuid` to the top of `core/auth.py` accordingly.

- [ ] **Step 4: Rewrite `api/routers/profiles.py`**

```python
from __future__ import annotations

from django.http import HttpRequest
from ninja import Router

from api.schemas import ProfileOut, ProfileUpsertIn
from core.auth import JWTBearer
from core.repository import get_profile, upsert_profile

router = Router(auth=JWTBearer())


@router.get("/profile", response=ProfileOut)
def get_profile_view(request: HttpRequest):
    profile = get_profile(request.auth.id)
    if profile is None:
        profile = upsert_profile(request.auth.id, settings={})
    return ProfileOut(settings=profile.settings)


@router.put("/profile", response=ProfileOut)
def upsert_profile_view(request: HttpRequest, payload: ProfileUpsertIn):
    profile = upsert_profile(request.auth.id, settings=payload.settings)
    return ProfileOut(settings=profile.settings)
```

- [ ] **Step 5: Delete `core/managers.py`**

```bash
rm backend/core/managers.py
```

- [ ] **Step 6: Add the root-level emulator fixtures in `backend/conftest.py`**

```python
from __future__ import annotations

import os

import pytest
import requests

from core.firestore_client import get_client, reset_client_for_tests


def _emulator_host() -> str:
    host = os.environ.get("FIRESTORE_EMULATOR_HOST")
    if not host:
        pytest.exit(
            "FIRESTORE_EMULATOR_HOST is not set — start the emulator first:\n"
            "  firebase emulators:start --only firestore --project demo-lucidboard",
            returncode=1,
        )
    return host


@pytest.fixture(autouse=True)
def clear_firestore():
    """Wipe every document in the emulator before each test."""
    host = _emulator_host()
    project_id = os.environ.get("FIRESTORE_PROJECT_ID", "demo-lucidboard")
    reset_client_for_tests()
    url = f"http://{host}/emulator/v1/projects/{project_id}/databases/(default)/documents"
    requests.delete(url, timeout=5)
    yield
    requests.delete(url, timeout=5)


@pytest.fixture
def firestore_client():
    return get_client()
```

- [ ] **Step 7: Rewrite `api/conftest.py`**

```python
import pytest
from django.test import Client

from core.auth import mint_anonymous_token


@pytest.fixture
def client():
    return Client()


@pytest.fixture
def auth_client():
    user, token = mint_anonymous_token()
    c = Client(HTTP_AUTHORIZATION=f"Bearer {token}")
    c.user = user
    return c
```
(The `db` parameter is gone — there is no Django database fixture anymore; `clear_firestore` in the new root `conftest.py` is `autouse=True` so every test gets a clean emulator automatically.)

- [ ] **Step 8: Drop the `django_db` marker from every test file touched so far**

`api/tests/test_health.py` — remove `import pytest` and `pytestmark = pytest.mark.django_db`, leaving just:
```python
def test_health_endpoint_returns_ok(client):
    res = client.get("/api/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_404_returns_json(client):
    res = client.get("/api/nonexistent")
    assert res.status_code == 404
    assert res.headers["content-type"].startswith("application/json")
```

`api/tests/test_auth.py` — remove the `pytestmark` line and swap the ORM existence check:
```python
from django.conf import settings
import jwt

from core.repository import get_user


def test_anonymous_signup_creates_user_and_returns_token(client):
    res = client.post("/auth/v1/signup?anonymous=true")
    assert res.status_code == 200
    body = res.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == settings.JWT_EXPIRY_SECONDS
    assert body["user"]["is_anonymous"] is True
    payload = jwt.decode(
        body["access_token"], settings.JWT_SECRET,
        algorithms=["HS256"], audience="authenticated",
    )
    assert payload["sub"] == body["user"]["id"]
    import uuid
    assert get_user(uuid.UUID(body["user"]["id"])) is not None


def test_anonymous_signup_without_query_param_returns_400(client):
    res = client.post("/auth/v1/signup")
    assert res.status_code == 400
    assert res.json()["code"] == "anonymous_required"
```

`api/tests/test_auth_module.py` — remove `pytestmark` and swap ORM calls for repository calls:
```python
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import pytest
from django.conf import settings

from core.auth import decode_token, mint_anonymous_token
from core.repository import get_user


def test_mint_anonymous_token_creates_user():
    user, token = mint_anonymous_token()
    assert get_user(user.id) is not None
    assert user.is_anonymous_user is True


def test_mint_anonymous_token_has_correct_claims():
    user, token = mint_anonymous_token()
    payload = jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"], audience="authenticated")
    assert payload["sub"] == str(user.id)
    assert payload["role"] == "authenticated"
    assert payload["aud"] == "authenticated"
    assert payload["is_anonymous"] is True
    assert payload["exp"] - payload["iat"] == settings.JWT_EXPIRY_SECONDS


def test_decode_token_returns_user_for_valid_token():
    user, token = mint_anonymous_token()
    decoded_user = decode_token(token)
    assert decoded_user.id == user.id


def test_decode_token_raises_on_invalid_signature():
    user, _ = mint_anonymous_token()
    bad_token = jwt.encode(
        {"sub": str(user.id), "aud": "authenticated", "exp": 9999999999, "iat": 0,
         "role": "authenticated", "is_anonymous": True},
        "wrong-secret",
        algorithm="HS256",
    )
    with pytest.raises(jwt.InvalidSignatureError):
        decode_token(bad_token)


def test_decode_token_raises_on_expired_token():
    expired_payload = {
        "sub": str(uuid4()),
        "aud": "authenticated",
        "iat": int((datetime.now(tz=timezone.utc) - timedelta(hours=2)).timestamp()),
        "exp": int((datetime.now(tz=timezone.utc) - timedelta(hours=1)).timestamp()),
        "role": "authenticated",
        "is_anonymous": True,
    }
    expired_token = jwt.encode(expired_payload, settings.JWT_SECRET, algorithm="HS256")
    with pytest.raises(jwt.ExpiredSignatureError):
        decode_token(expired_token)
```

`api/tests/test_profiles.py` — remove `pytestmark`, swap ORM for repository:
```python
from core.repository import get_profile


def test_get_profile_auto_creates_on_first_call(auth_client):
    assert get_profile(auth_client.user.id) is None
    res = auth_client.get("/api/profile")
    assert res.status_code == 200
    assert res.json() == {"settings": {}}
    assert get_profile(auth_client.user.id) is not None


def test_upsert_profile(auth_client):
    res = auth_client.put(
        "/api/profile",
        data={"settings": {"defaultNoteColor": "#000"}},
        content_type="application/json",
    )
    assert res.status_code == 200
    profile = get_profile(auth_client.user.id)
    assert profile.settings == {"defaultNoteColor": "#000"}
```

- [ ] **Step 9: Start the emulator and run the tests touched so far**

Run (in one terminal): `cd backend && firebase emulators:start --only firestore --project demo-lucidboard`
Run (in another terminal): `cd backend && uv run pytest api/tests/test_health.py api/tests/test_auth.py api/tests/test_auth_module.py api/tests/test_profiles.py -v`
Expected: all tests PASS. `test_boards.py`, `test_notes.py`, `test_rpc.py` will currently ERROR on collection (they still import `core.models.Board`/`Note`, which don't exist yet) — that's expected until Task 4/5/7; don't run the full suite yet.

- [ ] **Step 10: Commit**

```bash
git add backend/core/models.py backend/core/repository.py backend/core/auth.py backend/api/routers/profiles.py backend/conftest.py backend/api/conftest.py backend/api/tests/test_health.py backend/api/tests/test_auth.py backend/api/tests/test_auth_module.py backend/api/tests/test_profiles.py
git rm backend/core/managers.py
git commit -m "feat(backend): migrate users/profile to Firestore repository layer"
```

---

### Task 4: Boards

**Files:**
- Modify: `backend/core/models.py`
- Modify: `backend/core/repository.py`
- Modify: `backend/api/routers/boards.py`
- Modify: `backend/api/tests/test_boards.py`

**Interfaces:**
- Consumes: `create_anonymous_user()` (Task 3, used by tests).
- Produces: `Board` dataclass; `list_boards_for_user(user_id) -> list[Board]`, `get_board(board_id) -> Board | None`, `create_board(user_id, title="Untitled") -> Board`, `update_board(board_id, **fields) -> Board` — `core/matching.py` (Task 7) and `api/routers/notes.py` (Task 5) rely on `get_board`.

- [ ] **Step 1: Append `Board` to `core/models.py`**

```python
@dataclass
class Board:
    id: UUID
    user_id: UUID
    title: str = "Untitled"
    background_color: str = "#FFFFFF"
    background_layout: str = "grid"
    created_at: datetime | None = None
    updated_at: datetime | None = None
```

- [ ] **Step 2: Append the boards slice to `core/repository.py`**

```python
from core.models import Board, Profile, User  # extend existing import line

BOARDS = "boards"


def _board_from_doc(doc_id: str, data: dict) -> Board:
    return Board(
        id=uuid.UUID(doc_id),
        user_id=uuid.UUID(data["user_id"]),
        title=data["title"],
        background_color=data["background_color"],
        background_layout=data["background_layout"],
        created_at=data["created_at"],
        updated_at=data["updated_at"],
    )


def list_boards_for_user(user_id: uuid.UUID) -> list[Board]:
    query = (
        get_client()
        .collection(BOARDS)
        .where("user_id", "==", str(user_id))
        .order_by("updated_at", direction="DESCENDING")
    )
    return [_board_from_doc(doc.id, doc.to_dict()) for doc in query.stream()]


def get_board(board_id: uuid.UUID) -> Board | None:
    snap = get_client().collection(BOARDS).document(str(board_id)).get()
    if not snap.exists:
        return None
    return _board_from_doc(snap.id, snap.to_dict())


def create_board(user_id: uuid.UUID, title: str = "Untitled") -> Board:
    now = _now()
    board = Board(
        id=uuid.uuid4(), user_id=user_id, title=title, created_at=now, updated_at=now
    )
    get_client().collection(BOARDS).document(str(board.id)).set(
        {
            "user_id": str(board.user_id),
            "title": board.title,
            "background_color": board.background_color,
            "background_layout": board.background_layout,
            "created_at": board.created_at,
            "updated_at": board.updated_at,
        }
    )
    return board


def update_board(board_id: uuid.UUID, **fields) -> Board:
    fields["updated_at"] = _now()
    get_client().collection(BOARDS).document(str(board_id)).update(fields)
    return get_board(board_id)
```

- [ ] **Step 3: Rewrite `api/routers/boards.py`**

```python
from __future__ import annotations

from uuid import UUID

from django.http import Http404, HttpRequest
from ninja import Router

from api.schemas import BoardOut, BoardUpdateIn
from core.auth import JWTBearer
from core.repository import get_board, list_boards_for_user, update_board

router = Router(auth=JWTBearer())


@router.get("/boards", response=list[BoardOut])
def list_boards(request: HttpRequest):
    return list_boards_for_user(request.auth.id)


@router.patch("/boards/{board_id}", response=BoardOut)
def update_board_view(request: HttpRequest, board_id: UUID, payload: BoardUpdateIn):
    board = get_board(board_id)
    if board is None or board.user_id != request.auth.id:
        raise Http404
    fields = payload.model_dump(exclude_unset=True)
    return update_board(board_id, **fields) if fields else board
```

- [ ] **Step 4: Rewrite `api/tests/test_boards.py`**

```python
from core.repository import create_anonymous_user, create_board, get_board


def test_list_boards_returns_only_users_boards(auth_client):
    create_board(auth_client.user.id, title="Mine")
    other_user = create_anonymous_user()
    create_board(other_user.id, title="Theirs")
    res = auth_client.get("/api/boards")
    assert res.status_code == 200
    titles = [b["title"] for b in res.json()]
    assert "Mine" in titles
    assert "Theirs" not in titles


def test_list_boards_requires_auth(client):
    res = client.get("/api/boards")
    assert res.status_code == 401


def test_update_board(auth_client):
    board = create_board(auth_client.user.id, title="Old")
    res = auth_client.patch(
        f"/api/boards/{board.id}",
        data={"title": "New", "background_color": "#000"},
        content_type="application/json",
    )
    assert res.status_code == 200
    updated = get_board(board.id)
    assert updated.title == "New"
    assert updated.background_color == "#000"


def test_update_other_users_board_returns_404(auth_client):
    other_user = create_anonymous_user()
    other = create_board(other_user.id, title="Theirs")
    res = auth_client.patch(
        f"/api/boards/{other.id}",
        data={"title": "Hacked"},
        content_type="application/json",
    )
    assert res.status_code == 404
```

- [ ] **Step 5: Run the boards tests against the running emulator**

Run: `cd backend && uv run pytest api/tests/test_boards.py -v`
Expected: all 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/core/models.py backend/core/repository.py backend/api/routers/boards.py backend/api/tests/test_boards.py
git commit -m "feat(backend): migrate boards to Firestore repository layer"
```

---

### Task 5: Notes

**Files:**
- Modify: `backend/core/models.py`
- Modify: `backend/core/repository.py`
- Modify: `backend/api/routers/notes.py`
- Modify: `backend/api/tests/test_notes.py`

**Interfaces:**
- Consumes: `get_board(board_id)` (Task 4), `generate_embedding(text)` (existing, unchanged `core/embeddings.py`).
- Produces: `Note` dataclass; `list_notes_for_board(board_id) -> list[Note]`, `get_note(note_id) -> Note | None`, `upsert_note(note_id, **fields) -> Note`, `delete_note(note_id) -> None` — `core/matching.py` (Task 7) relies on `list_notes_for_board` and the `Note.embedding` field.

- [ ] **Step 1: Append `Note` to `core/models.py`**

```python
@dataclass
class Note:
    id: UUID
    board_id: UUID
    user_id: UUID
    content_text: str | None = None
    content_drawing: bytes | None = None
    color: str = "#FFFFFF"
    pos_x: float = 0.0
    pos_y: float = 0.0
    z_index: int = 0
    template: str = "plain"
    checklist_items: list[dict] = field(default_factory=list)
    embedding: list[float] | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
```

- [ ] **Step 2: Append the notes slice to `core/repository.py`**

```python
from core.models import Board, Note, Profile, User  # extend existing import line

NOTES = "notes"


def _note_from_doc(doc_id: str, data: dict) -> Note:
    return Note(
        id=uuid.UUID(doc_id),
        board_id=uuid.UUID(data["board_id"]),
        user_id=uuid.UUID(data["user_id"]),
        content_text=data.get("content_text"),
        content_drawing=data.get("content_drawing"),
        color=data["color"],
        pos_x=data["pos_x"],
        pos_y=data["pos_y"],
        z_index=data["z_index"],
        template=data["template"],
        checklist_items=data.get("checklist_items", []),
        embedding=data.get("embedding"),
        created_at=data["created_at"],
        updated_at=data["updated_at"],
    )


def list_notes_for_board(board_id: uuid.UUID) -> list[Note]:
    query = (
        get_client()
        .collection(NOTES)
        .where("board_id", "==", str(board_id))
        .order_by("z_index")
    )
    return [_note_from_doc(doc.id, doc.to_dict()) for doc in query.stream()]


def get_note(note_id: uuid.UUID) -> Note | None:
    snap = get_client().collection(NOTES).document(str(note_id)).get()
    if not snap.exists:
        return None
    return _note_from_doc(snap.id, snap.to_dict())


def upsert_note(note_id: uuid.UUID, **fields) -> Note:
    existing = get_note(note_id)
    now = _now()
    data = {
        "board_id": str(fields["board_id"]),
        "user_id": str(fields["user_id"]),
        "content_text": fields.get("content_text"),
        "content_drawing": fields.get("content_drawing"),
        "color": fields["color"],
        "pos_x": fields["pos_x"],
        "pos_y": fields["pos_y"],
        "z_index": fields["z_index"],
        "template": fields.get("template", "plain"),
        "checklist_items": fields.get("checklist_items", []),
        "embedding": fields.get("embedding"),
        "created_at": existing.created_at if existing else now,
        "updated_at": now,
    }
    get_client().collection(NOTES).document(str(note_id)).set(data)
    return _note_from_doc(str(note_id), data)


def delete_note(note_id: uuid.UUID) -> None:
    get_client().collection(NOTES).document(str(note_id)).delete()
```

- [ ] **Step 3: Rewrite `api/routers/notes.py`**

```python
from __future__ import annotations

import base64
from uuid import UUID

from django.http import Http404, HttpRequest
from ninja import Router

from api.schemas import NoteOut, NoteUpsertIn
from core.auth import JWTBearer
from core.embeddings import generate_embedding
from core.models import Note
from core.repository import delete_note, get_board, get_note, list_notes_for_board, upsert_note

router = Router(auth=JWTBearer())


def _decode_drawing(b64: str | None) -> bytes | None:
    return base64.b64decode(b64) if b64 else None


def _encode_drawing(data: bytes | None) -> str | None:
    return base64.b64encode(data).decode() if data else None


def _serialize(note: Note) -> dict:
    return {
        "id": note.id,
        "board_id": note.board_id,
        "user_id": note.user_id,
        "content_text": note.content_text,
        "content_drawing": _encode_drawing(note.content_drawing),
        "color": note.color,
        "pos_x": note.pos_x,
        "pos_y": note.pos_y,
        "z_index": note.z_index,
        "template": note.template,
        "checklist_items": note.checklist_items,
        "created_at": note.created_at,
        "updated_at": note.updated_at,
    }


@router.get("/boards/{board_id}/notes", response=list[NoteOut])
def list_notes(request: HttpRequest, board_id: UUID):
    board = get_board(board_id)
    if board is None or board.user_id != request.auth.id:
        raise Http404
    return [_serialize(n) for n in list_notes_for_board(board_id)]


@router.put("/notes/{note_id}", response=NoteOut)
def upsert_note_view(request: HttpRequest, note_id: UUID, payload: NoteUpsertIn):
    board = get_board(payload.board_id)
    if board is None or board.user_id != request.auth.id:
        raise Http404
    existing = get_note(note_id)

    new_text = payload.content_text or ""
    if existing is not None and existing.content_text == payload.content_text:
        embedding = existing.embedding  # reuse
    else:
        embedding = generate_embedding(new_text)

    note = upsert_note(
        note_id,
        board_id=payload.board_id,
        user_id=request.auth.id,
        content_text=payload.content_text,
        content_drawing=_decode_drawing(payload.content_drawing),
        color=payload.color,
        pos_x=payload.pos_x,
        pos_y=payload.pos_y,
        z_index=payload.z_index,
        template=payload.template,
        checklist_items=[item.model_dump() for item in payload.checklist_items],
        embedding=embedding,
    )
    return _serialize(note)


@router.delete("/notes/{note_id}", response={204: None})
def delete_note_view(request: HttpRequest, note_id: UUID):
    note = get_note(note_id)
    if note is None or note.user_id != request.auth.id:
        raise Http404
    delete_note(note_id)
    return 204, None
```

Note the `checklist_items` schema uses `id: UUID` fields (`ChecklistItemSchema` in `api/schemas.py`) — `item.model_dump()` on those still yields `UUID` objects in the dict, exactly as it did with the ORM's `JSONField`, so no change needed there; Firestore's client serializes `UUID` inside a dict the same way Django's `JSONField` did (both need JSON-safe values — check Step 5 for a note on this).

- [ ] **Step 4: Rewrite `api/tests/test_notes.py`**

```python
import uuid
from unittest.mock import patch

from core.repository import create_anonymous_user, create_board, get_note


def _note_payload(board_id, **overrides):
    base = {
        "board_id": str(board_id),
        "content_text": "Hello",
        "content_drawing": None,
        "color": "#FFF9C4",
        "pos_x": 1.0,
        "pos_y": 2.0,
        "z_index": 0,
        "template": "plain",
        "checklist_items": [],
    }
    base.update(overrides)
    return base


def _make_other_board():
    other_user = create_anonymous_user()
    return create_board(other_user.id, title="theirs")


def test_list_notes_for_board(auth_client):
    board = create_board(auth_client.user.id, title="b")
    with patch("api.routers.notes.generate_embedding", return_value=None):
        auth_client.put(
            f"/api/notes/{uuid.uuid4()}",
            data=_note_payload(board.id),
            content_type="application/json",
        )
    res = auth_client.get(f"/api/boards/{board.id}/notes")
    assert res.status_code == 200
    assert len(res.json()) == 1


def test_list_notes_for_other_users_board_returns_404(auth_client):
    other_board = _make_other_board()
    res = auth_client.get(f"/api/boards/{other_board.id}/notes")
    assert res.status_code == 404


def test_upsert_creates_note_and_calls_embedding(auth_client):
    board = create_board(auth_client.user.id, title="b")
    fake_vector = [0.1] * 768
    note_id = uuid.uuid4()
    with patch("api.routers.notes.generate_embedding", return_value=fake_vector) as mock_embed:
        res = auth_client.put(
            f"/api/notes/{note_id}",
            data=_note_payload(board.id),
            content_type="application/json",
        )
    assert res.status_code == 200
    mock_embed.assert_called_once_with("Hello")
    note = get_note(note_id)
    assert note.embedding == fake_vector


def test_upsert_skips_embedding_when_content_unchanged(auth_client):
    board = create_board(auth_client.user.id, title="b")
    note_id = uuid.uuid4()
    with patch("api.routers.notes.generate_embedding", return_value=[0.5] * 768):
        auth_client.put(
            f"/api/notes/{note_id}",
            data=_note_payload(board.id, content_text="Same"),
            content_type="application/json",
        )

    with patch("api.routers.notes.generate_embedding") as mock_embed:
        auth_client.put(
            f"/api/notes/{note_id}",
            data=_note_payload(board.id, content_text="Same", color="#000"),
            content_type="application/json",
        )
    mock_embed.assert_not_called()
    note = get_note(note_id)
    assert note.color == "#000"


def test_upsert_on_other_users_board_returns_404(auth_client):
    other_board = _make_other_board()
    note_id = uuid.uuid4()
    with patch("api.routers.notes.generate_embedding", return_value=None):
        res = auth_client.put(
            f"/api/notes/{note_id}",
            data=_note_payload(other_board.id),
            content_type="application/json",
        )
    assert res.status_code == 404


def test_delete_note(auth_client):
    board = create_board(auth_client.user.id, title="b")
    note_id = uuid.uuid4()
    with patch("api.routers.notes.generate_embedding", return_value=None):
        auth_client.put(
            f"/api/notes/{note_id}",
            data=_note_payload(board.id),
            content_type="application/json",
        )
    res = auth_client.delete(f"/api/notes/{note_id}")
    assert res.status_code == 204
    assert get_note(note_id) is None


def test_delete_other_users_note_returns_404(auth_client):
    other_board = _make_other_board()
    other_note_id = uuid.uuid4()
    with patch("api.routers.notes.generate_embedding", return_value=None):
        # PUT as the other user directly via the repository (bypassing auth)
        # to seed a note that belongs to someone else.
        from core.repository import upsert_note
        upsert_note(
            other_note_id,
            board_id=other_board.id,
            user_id=other_board.user_id,
            content_text=None,
            content_drawing=None,
            color="#fff",
            pos_x=0,
            pos_y=0,
            z_index=0,
            template="plain",
            checklist_items=[],
            embedding=None,
        )
    res = auth_client.delete(f"/api/notes/{other_note_id}")
    assert res.status_code == 404
```

- [ ] **Step 5: Run the notes tests against the running emulator**

Run: `cd backend && uv run pytest api/tests/test_notes.py -v`
Expected: all 7 tests PASS. If `test_upsert_creates_note_and_calls_embedding` fails with a Firestore serialization error, it means the `checklist_items` list (containing `UUID` values from `ChecklistItemSchema`) isn't JSON/Firestore-safe — fix by converting the `id` field to `str` in `_serialize`'s call to `upsert_note`, i.e. `[{**item.model_dump(), "id": str(item.id)} for item in payload.checklist_items]` in `api/routers/notes.py`, and update `ChecklistItemSchema` handling in `_serialize`/`NoteOut` accordingly if needed. Confirm which path is needed by reading the actual pytest failure — don't apply this preemptively if the vanilla version already passes (the Firestore Python client does accept `UUID` values by coercing via `str()` in some versions, so check first).

- [ ] **Step 6: Commit**

```bash
git add backend/core/models.py backend/core/repository.py backend/api/routers/notes.py backend/api/tests/test_notes.py
git commit -m "feat(backend): migrate notes to Firestore repository layer"
```

---

### Task 6: Auto-cluster matching (`match_notes` → pure Python)

**Files:**
- Create: `backend/core/matching.py`
- Modify: `backend/api/routers/rpc.py`
- Modify: `backend/api/tests/test_rpc.py`

**Interfaces:**
- Consumes: `list_notes_for_board(board_id) -> list[Note]` (Task 5), `get_board(board_id)` (Task 4).
- Produces: `match_notes(notes: list[Note]) -> list[MatchedPosition]` — pure function, no Firestore access, so it's independently unit-testable.

- [ ] **Step 1: Write `core/matching.py`**

```python
from __future__ import annotations

import uuid
from dataclasses import dataclass

from core.models import Note

# Mirrors the constants baked into the retired Postgres `match_notes` function
# (backend/core/migrations/0002_match_notes_function.py, now deleted).
CLUSTER_SPACING = 280.0
CLUSTER_GAP = 400.0
SIMILARITY_THRESHOLD = 0.15
CANVAS_ORIGIN_X = 200.0
CANVAS_ORIGIN_Y = 200.0


@dataclass
class MatchedPosition:
    id: uuid.UUID
    new_x: float
    new_y: float


def _cosine_distance(a: list[float], b: list[float]) -> float:
    """1 - cosine_similarity, matching pgvector's `<=>` operator."""
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = sum(x * x for x in a) ** 0.5
    norm_b = sum(y * y for y in b) ** 0.5
    if norm_a == 0 or norm_b == 0:
        return 1.0
    return 1.0 - dot / (norm_a * norm_b)


def match_notes(notes: list[Note]) -> list[MatchedPosition]:
    """Pure-Python port of the Postgres `match_notes(board_uuid)` function.

    Pairs each embedded note with its single nearest neighbor; if that
    pair is within SIMILARITY_THRESHOLD they share a cluster (the note
    with the smaller UUID becomes the canonical cluster id), otherwise
    the note is its own cluster. Notes without an embedding are always
    their own cluster. Clusters are laid out left-to-right by descending
    size (ties broken by cluster id), notes within a cluster top-to-bottom
    ordered by note id.
    """
    embedded = [n for n in notes if n.embedding is not None]
    unembedded = [n for n in notes if n.embedding is None]

    nearest_id: dict[uuid.UUID, uuid.UUID] = {}
    nearest_dist: dict[uuid.UUID, float] = {}
    for a in embedded:
        best_id: uuid.UUID | None = None
        best_dist = float("inf")
        for b in embedded:
            if b.id == a.id:
                continue
            dist = _cosine_distance(a.embedding, b.embedding)
            if dist < best_dist:
                best_dist = dist
                best_id = b.id
        if best_id is not None:
            nearest_id[a.id] = best_id
            nearest_dist[a.id] = best_dist

    cluster_id: dict[uuid.UUID, uuid.UUID] = {}
    for n in embedded:
        nid = nearest_id.get(n.id)
        dist = nearest_dist.get(n.id)
        if nid is None or dist > SIMILARITY_THRESHOLD:
            cluster_id[n.id] = n.id
        elif n.id < nid:
            cluster_id[n.id] = n.id
        else:
            cluster_id[n.id] = nid

    all_notes_clustered: list[tuple[uuid.UUID, uuid.UUID]] = [
        (n.id, cluster_id[n.id]) for n in embedded
    ] + [(n.id, n.id) for n in unembedded]

    sizes: dict[uuid.UUID, int] = {}
    for _, cid in all_notes_clustered:
        sizes[cid] = sizes.get(cid, 0) + 1
    ordered_clusters = sorted(sizes.keys(), key=lambda cid: (-sizes[cid], cid))
    cluster_idx = {cid: idx for idx, cid in enumerate(ordered_clusters)}

    by_cluster: dict[uuid.UUID, list[uuid.UUID]] = {}
    for note_id, cid in all_notes_clustered:
        by_cluster.setdefault(cid, []).append(note_id)

    positions: list[MatchedPosition] = []
    for cid, note_ids in by_cluster.items():
        for pos_in_cluster, note_id in enumerate(sorted(note_ids)):
            positions.append(
                MatchedPosition(
                    id=note_id,
                    new_x=CANVAS_ORIGIN_X + cluster_idx[cid] * (CLUSTER_SPACING + CLUSTER_GAP),
                    new_y=CANVAS_ORIGIN_Y + pos_in_cluster * CLUSTER_SPACING,
                )
            )
    return positions
```

- [ ] **Step 2: Rewrite `api/routers/rpc.py`**

```python
from __future__ import annotations

from django.http import Http404, HttpRequest
from ninja import Router

from api.schemas import MatchNoteResult, MatchNotesIn
from core.auth import JWTBearer
from core.matching import match_notes
from core.repository import get_board, list_notes_for_board

router = Router(auth=JWTBearer())


@router.post("/rpc/match_notes", response=list[MatchNoteResult])
def match_notes_view(request: HttpRequest, payload: MatchNotesIn):
    board = get_board(payload.board_uuid)
    if board is None or board.user_id != request.auth.id:
        raise Http404
    notes = list_notes_for_board(payload.board_uuid)
    return [
        MatchNoteResult(id=p.id, new_x=p.new_x, new_y=p.new_y) for p in match_notes(notes)
    ]
```

- [ ] **Step 3: Rewrite `api/tests/test_rpc.py`**

Keep the existing integration-level tests (through the HTTP API), and add a small direct unit test of `core/matching.py` since it's now a pure function worth testing in isolation:

```python
import uuid

from core.matching import match_notes
from core.models import Note
from core.repository import create_anonymous_user, create_board, upsert_note


def _fake_embedding(seed: float) -> list[float]:
    return [seed] * 768


def _make_note(board_id, user_id, *, content_text, embedding, z_index=0) -> Note:
    note_id = uuid.uuid4()
    return upsert_note(
        note_id,
        board_id=board_id,
        user_id=user_id,
        content_text=content_text,
        content_drawing=None,
        color="#fff",
        pos_x=0,
        pos_y=0,
        z_index=z_index,
        template="plain",
        checklist_items=[],
        embedding=embedding,
    )


def test_match_notes_returns_positions(auth_client):
    board = create_board(auth_client.user.id, title="b")
    n1 = _make_note(board.id, auth_client.user.id, content_text="cat", embedding=_fake_embedding(0.1))
    n2 = _make_note(board.id, auth_client.user.id, content_text="kitten", embedding=_fake_embedding(0.1), z_index=1)
    n3 = _make_note(board.id, auth_client.user.id, content_text="rocket", embedding=_fake_embedding(0.9), z_index=2)
    res = auth_client.post(
        "/api/rpc/match_notes",
        data={"board_uuid": str(board.id)},
        content_type="application/json",
    )
    assert res.status_code == 200
    body = res.json()
    ids = {item["id"] for item in body}
    assert ids == {str(n1.id), str(n2.id), str(n3.id)}
    for item in body:
        assert isinstance(item["new_x"], (int, float))
        assert isinstance(item["new_y"], (int, float))


def test_match_notes_rejects_other_users_board(auth_client):
    other_user = create_anonymous_user()
    other_board = create_board(other_user.id, title="theirs")
    res = auth_client.post(
        "/api/rpc/match_notes",
        data={"board_uuid": str(other_board.id)},
        content_type="application/json",
    )
    assert res.status_code == 404


def test_match_notes_returns_empty_for_board_with_no_notes(auth_client):
    board = create_board(auth_client.user.id, title="b")
    res = auth_client.post(
        "/api/rpc/match_notes",
        data={"board_uuid": str(board.id)},
        content_type="application/json",
    )
    assert res.status_code == 200
    assert res.json() == []


def test_match_notes_pure_function_clusters_similar_notes_together():
    board_id = uuid.uuid4()
    user_id = uuid.uuid4()
    n1 = Note(id=uuid.uuid4(), board_id=board_id, user_id=user_id, color="#fff",
               pos_x=0, pos_y=0, z_index=0, embedding=_fake_embedding(0.1))
    n2 = Note(id=uuid.uuid4(), board_id=board_id, user_id=user_id, color="#fff",
               pos_x=0, pos_y=0, z_index=1, embedding=_fake_embedding(0.1))
    n3 = Note(id=uuid.uuid4(), board_id=board_id, user_id=user_id, color="#fff",
               pos_x=0, pos_y=0, z_index=2, embedding=_fake_embedding(0.9))
    positions = match_notes([n1, n2, n3])
    by_id = {p.id: p for p in positions}
    # n1 and n2 are identical embeddings (distance 0) -> same cluster -> same x.
    assert by_id[n1.id].new_x == by_id[n2.id].new_x
    # n3 is far from both -> different cluster -> different x.
    assert by_id[n3.id].new_x != by_id[n1.id].new_x


def test_match_notes_pure_function_handles_no_embeddings():
    board_id = uuid.uuid4()
    user_id = uuid.uuid4()
    n1 = Note(id=uuid.uuid4(), board_id=board_id, user_id=user_id, color="#fff",
               pos_x=0, pos_y=0, z_index=0, embedding=None)
    positions = match_notes([n1])
    assert len(positions) == 1
    assert positions[0].id == n1.id
```

- [ ] **Step 4: Run the rpc tests against the running emulator**

Run: `cd backend && uv run pytest api/tests/test_rpc.py -v`
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/core/matching.py backend/api/routers/rpc.py backend/api/tests/test_rpc.py
git commit -m "feat(backend): port match_notes clustering from Postgres to pure Python"
```

---

### Task 7: Cleanup — delete dead ORM artifacts, update smoke test, full suite pass

**Files:**
- Delete: `backend/core/migrations/`
- Modify: `backend/scripts/smoke.sh`
- Modify: `backend/README.md`

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: nothing new — this task only removes dead code and re-verifies the whole surface.

- [ ] **Step 1: Delete the migrations package**

```bash
rm -rf backend/core/migrations
```

Confirm nothing still imports it:
Run: `cd backend && grep -rn "core.migrations\|core\.migrations" --include="*.py" . | grep -v .venv`
Expected: no output.

- [ ] **Step 2: Rewrite `scripts/smoke.sh` to seed via the emulator instead of `psql`**

```bash
#!/usr/bin/env bash
# End-to-end smoke test against a running local backend + Firestore emulator.
# Usage: ./scripts/smoke.sh
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8000}"
PY="${PY:-python3}"

echo "==> signup"
TOKEN=$(curl -sf -X POST "$BASE/auth/v1/signup?anonymous=true" | "$PY" -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="Authorization: Bearer $TOKEN"
USER_ID=$("$PY" -c 'import sys,json,base64;tok=sys.argv[1].split(".")[1];tok+="="*((4-len(tok)%4)%4);print(json.loads(base64.urlsafe_b64decode(tok))["sub"])' "$TOKEN")

echo "==> seed board directly in the Firestore emulator (boards are normally created by the Swift app)"
BOARD_ID=$("$PY" - "$USER_ID" <<'EOF'
import sys, uuid
from datetime import datetime, timezone
from google.cloud import firestore

user_id = sys.argv[1]
board_id = str(uuid.uuid4())
client = firestore.Client(project="demo-lucidboard")
now = datetime.now(tz=timezone.utc)
client.collection("boards").document(board_id).set({
    "user_id": user_id,
    "title": "Smoke",
    "background_color": "#FFFFFF",
    "background_layout": "grid",
    "created_at": now,
    "updated_at": now,
})
print(board_id)
EOF
)

echo "==> list boards"
curl -sf -H "$AUTH" "$BASE/api/boards" | "$PY" -m json.tool

echo "==> create note"
NOTE_ID=$("$PY" -c 'import uuid;print(uuid.uuid4())')
curl -sf -X PUT -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"board_id\":\"$BOARD_ID\",\"color\":\"#FFF9C4\",\"pos_x\":1.0,\"pos_y\":2.0,\"z_index\":0,\"content_text\":\"smoke\",\"template\":\"plain\",\"checklist_items\":[]}" \
  "$BASE/api/notes/$NOTE_ID" | "$PY" -m json.tool

echo "==> list notes"
curl -sf -H "$AUTH" "$BASE/api/boards/$BOARD_ID/notes" | "$PY" -m json.tool

echo "==> delete note"
curl -sf -X DELETE -H "$AUTH" "$BASE/api/notes/$NOTE_ID" -o /dev/null -w "delete status: %{http_code}\n"

echo "==> SMOKE OK"
```

The seed step needs `FIRESTORE_EMULATOR_HOST`/`FIRESTORE_PROJECT_ID` set in the shell running `smoke.sh` (same values as the server's `.env`) so the ad-hoc Python snippet talks to the same emulator instance as the running Django server.

- [ ] **Step 3: Update the README's "Limitations" section**

Replace the `## Limitations (Phase 1)` section of `backend/README.md`:
```markdown
## Limitations (Phase 1)

- Anonymous-only auth (no email/password, no OAuth)
- No realtime/WebSocket sync (LocalAPIRepository returns inert subscription)
- Local dev only — this backend and its Firestore Emulator are not deployed anywhere;
  production still runs Supabase until the prod cutover task lands
- `firestore.indexes.json` is empty — the emulator doesn't enforce composite-index
  requirements, but real Firestore will; add the `boards` (user_id ==, updated_at desc)
  composite index here before pointing this backend at production Firestore
- `match_notes` clustering is pairwise nearest-neighbor (ported as-is from the retired
  Postgres function), not a transitive/global clustering algorithm
- No data migration from Supabase (starts empty)
```

- [ ] **Step 4: Run the complete backend test suite**

Run: `cd backend && uv run pytest -v`
Expected: all tests across `test_auth.py`, `test_auth_module.py`, `test_boards.py`, `test_embeddings.py`, `test_health.py`, `test_notes.py`, `test_profiles.py`, `test_rpc.py` PASS. `test_embeddings.py` needs no changes — it only exercises `core/embeddings.py`, which never touched the database.

Run: `cd backend && uv run ruff check .`
Expected: no errors (fix any `unused import` findings left over from the router/model rewrites — e.g. `core/models.py` no longer needs `pgvector.django`/`django.contrib.auth` imports, `api/routers/*.py` no longer need `django.shortcuts.get_object_or_404`).

- [ ] **Step 5: Manual end-to-end check**

Run (terminal 1): `cd backend && firebase emulators:start --only firestore --project demo-lucidboard`
Run (terminal 2): `cd backend && uv run manage.py runserver`
Run (terminal 3): `cd backend && ./scripts/smoke.sh`
Expected: `SMOKE OK` printed with no curl errors along the way, and the Firestore Emulator UI at `http://127.0.0.1:4000/firestore` shows `users`, `boards`, `notes` collections populated with the smoke-test data.

- [ ] **Step 6: Commit**

```bash
git add backend/scripts/smoke.sh backend/README.md
git rm -r backend/core/migrations
git commit -m "chore(backend): drop dead Django ORM migrations, update smoke test for Firestore"
```

---

## Self-Review Notes

- **Spec coverage:** ClickUp task 86bb077ug asked for two things — "transition local database to Firestore" (Tasks 2–7 replace every `django.db`/pgvector call site) and "use the Emulator" (Task 1 stands up the Firebase CLI emulator; Task 3's `conftest.py` makes tests fail fast with a clear message if it isn't running). Both covered.
- **Explicitly out of scope, confirmed with the user:** production Supabase config (`supabase/`), the Swift `SupabaseRepository`/Release build default, and Firestore's native vector-search index (local matching is done in pure Python instead) — all called out in Global Constraints and the Task 7 README update so nobody mistakes this for the prod cutover itself.
- **Type consistency check:** `get_board`/`get_note`/`get_user`/`get_profile` all return `X | None` and every router checks for `None` before use (mirroring the old `get_object_or_404` 404 behavior) — verified consistently across Tasks 3–6. `Board`/`Note`/`Profile`/`User` field names match `api/schemas.py`'s `Out` schemas exactly (Ninja serializes dataclass/dict attributes by name), so no response-shape drift from the Swift client's perspective.
