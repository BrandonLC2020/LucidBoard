# Local-Dev Backend Migration (Supabase → Django Ninja) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-dev Django Ninja backend that fully replaces Supabase (auth, CRUD, AI clustering) for local development, with a Swift `AppRepository` protocol that lets the app switch between Supabase and the local backend via xcconfig.

**Architecture:** New `backend/` Django Ninja project sitting in front of a single Postgres+pgvector Docker container. Swift app gains an `AppRepository` protocol with two implementations (`SupabaseRepository`, `LocalAPIRepository`), chosen at launch. Supabase code path stays intact and selectable. Spec: `docs/superpowers/specs/2026-05-21-supabase-to-django-ninja-local-dev-design.md`.

**Tech Stack:**
- Backend: Python 3.12, Django 5, django-ninja, django-pgvector, psycopg, PyJWT, google-generativeai
- Tooling: uv (deps), ruff (lint), ty (typecheck), pytest + pytest-django + pytest-postgresql
- Infra: Postgres 17 + pgvector (Docker)
- Frontend: Swift 5.10+, existing Supabase Swift SDK, URLSession

---

## File Structure

### New backend files
```
backend/
├── docker-compose.yml
├── pyproject.toml
├── .env.example
├── .gitignore
├── manage.py
├── README.md
├── lucidboard_api/
│   ├── __init__.py
│   ├── settings.py
│   ├── urls.py
│   ├── asgi.py
│   └── wsgi.py
├── core/
│   ├── __init__.py
│   ├── apps.py
│   ├── models.py
│   ├── auth.py
│   ├── embeddings.py
│   ├── managers.py
│   └── migrations/
│       ├── __init__.py
│       └── 0001_initial.py
├── api/
│   ├── __init__.py
│   ├── ninja.py            # NinjaAPI root + exception handlers
│   ├── schemas.py
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   ├── boards.py
│   │   ├── notes.py
│   │   ├── profiles.py
│   │   └── rpc.py
│   ├── conftest.py
│   └── tests/
│       ├── __init__.py
│       ├── test_auth.py
│       ├── test_boards.py
│       ├── test_notes.py
│       ├── test_profiles.py
│       └── test_rpc.py
└── scripts/
    └── smoke.sh
```

### New Swift files
```
frontend/LucidBoard/Services/
├── AppRepository.swift            # protocol + NoteChange enum + factory
├── SupabaseRepository.swift       # wraps existing SupabaseService
├── LocalAPIRepository.swift       # URLSession + JSON to Django Ninja
└── TokenStore.swift               # Keychain JWT storage
frontend/LucidBoardTests/
├── LocalAPIRepositoryTests.swift
└── AppRepositoryFactoryTests.swift
```

### Modified files
- `frontend/LucidBoard/LucidBoardApp.swift` — inject AppRepository
- `frontend/LucidBoard/ViewModels/BoardViewModel.swift` — use AppRepository, drop direct Realtime usage
- `frontend/LucidBoard/ViewModels/NoteViewModel.swift` — use AppRepository
- `frontend/LucidBoard/Services/SettingsManager.swift` — use AppRepository
- `frontend/LucidBoard/Sample.xcconfig` — add BACKEND_KIND and LOCAL_API_URL
- `frontend/LucidBoard/Config.xcconfig` (if it exists locally) — add the same keys

---

## Task Index

1. Scaffold backend (uv, Django, deps, settings, Docker)
2. Database models (User, Board, Note, Profile) + initial migration
3. Port `match_notes` SQL function as a follow-on migration
4. JWT module (`core/auth.py`) — mint + decode + JWTBearer auth class
5. Embeddings module (`core/embeddings.py`) — Gemini wrapper with graceful failure
6. Ninja app root + exception handler (`api/ninja.py`)
7. Pydantic schemas (`api/schemas.py`)
8. Auth router (anonymous signup)
9. Boards router (list, update)
10. Notes router (list-by-board, upsert with embed, delete)
11. Profiles router (get, upsert; auto-create on get)
12. RPC router (`match_notes` endpoint)
13. Smoke script (`scripts/smoke.sh`)
14. Backend README
15. Swift: `TokenStore` (Keychain JWT storage)
16. Swift: `AppRepository` protocol + `NoteChange`/`NoteSubscription` types + factory
17. Swift: `SupabaseRepository` (wraps existing SupabaseService + Realtime)
18. Swift: `LocalAPIRepository` (URLSession + retry-on-401)
19. Swift: Wire `AppRepository` into `LucidBoardApp`, refactor `BoardViewModel`/`NoteViewModel`/`SettingsManager`
20. Swift: xcconfig keys

---

### Task 1: Scaffold backend

**Files:**
- Create: `backend/pyproject.toml`
- Create: `backend/docker-compose.yml`
- Create: `backend/.env.example`
- Create: `backend/.gitignore`
- Create: `backend/manage.py`
- Create: `backend/lucidboard_api/__init__.py`
- Create: `backend/lucidboard_api/settings.py`
- Create: `backend/lucidboard_api/urls.py`
- Create: `backend/lucidboard_api/asgi.py`
- Create: `backend/lucidboard_api/wsgi.py`
- Create: `backend/core/__init__.py`
- Create: `backend/core/apps.py`

- [ ] **Step 1: Create `backend/pyproject.toml`**

```toml
[project]
name = "lucidboard-api"
version = "0.1.0"
description = "LucidBoard local-dev backend (Supabase replacement)"
requires-python = ">=3.12"
dependencies = [
    "django>=5.0,<6.0",
    "django-ninja>=1.3",
    "psycopg[binary]>=3.2",
    "pgvector>=0.3.6",
    "pyjwt>=2.9",
    "google-generativeai>=0.8",
    "python-dotenv>=1.0",
]

[dependency-groups]
dev = [
    "pytest>=8.3",
    "pytest-django>=4.9",
    "pytest-postgresql>=6.1",
    "httpx>=0.27",
    "ruff>=0.6",
    "ty>=0.0.1a1",
]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "lucidboard_api.settings"
python_files = "test_*.py"
```

- [ ] **Step 2: Create `backend/docker-compose.yml`**

```yaml
services:
  db:
    image: pgvector/pgvector:pg17
    container_name: lucidboard-db
    environment:
      POSTGRES_USER: lucidboard
      POSTGRES_PASSWORD: lucidboard
      POSTGRES_DB: lucidboard
    ports:
      - "5432:5432"
    volumes:
      - lucidboard-pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U lucidboard"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  lucidboard-pgdata:
```

- [ ] **Step 3: Create `backend/.env.example`**

```
DJANGO_SECRET_KEY=dev-only-change-me
JWT_SECRET=dev-only-change-me-jwt
JWT_EXPIRY_SECONDS=3600
DATABASE_URL=postgres://lucidboard:lucidboard@127.0.0.1:5432/lucidboard
GEMINI_API_KEY=
```

- [ ] **Step 4: Create `backend/.gitignore`**

```
.venv/
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
.env
db.sqlite3
```

- [ ] **Step 5: Create `backend/manage.py`**

```python
#!/usr/bin/env python
import os
import sys

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "lucidboard_api.settings")
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
```

- [ ] **Step 6: Create `backend/lucidboard_api/__init__.py`** (empty file)

- [ ] **Step 7: Create `backend/lucidboard_api/settings.py`**

```python
import os
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-only-change-me")
JWT_SECRET = os.environ.get("JWT_SECRET", "dev-only-change-me-jwt")
JWT_EXPIRY_SECONDS = int(os.environ.get("JWT_EXPIRY_SECONDS", "3600"))
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

DEBUG = True
ALLOWED_HOSTS = ["*"]

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.auth",
    "core",
]

MIDDLEWARE = [
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "lucidboard_api.urls"
WSGI_APPLICATION = "lucidboard_api.wsgi.application"
ASGI_APPLICATION = "lucidboard_api.asgi.application"

_db_url = urlparse(os.environ.get(
    "DATABASE_URL",
    "postgres://lucidboard:lucidboard@127.0.0.1:5432/lucidboard",
))
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": _db_url.path.lstrip("/"),
        "USER": _db_url.username,
        "PASSWORD": _db_url.password,
        "HOST": _db_url.hostname,
        "PORT": _db_url.port,
    }
}

AUTH_USER_MODEL = "core.User"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
USE_TZ = True
TIME_ZONE = "UTC"
```

- [ ] **Step 8: Create `backend/lucidboard_api/urls.py`**

```python
from django.urls import path

from api.ninja import api

urlpatterns = [
    path("", api.urls),
]
```

- [ ] **Step 9: Create `backend/lucidboard_api/asgi.py` and `wsgi.py`**

`backend/lucidboard_api/asgi.py`:
```python
import os
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "lucidboard_api.settings")
application = get_asgi_application()
```

`backend/lucidboard_api/wsgi.py`:
```python
import os
from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "lucidboard_api.settings")
application = get_wsgi_application()
```

- [ ] **Step 10: Create `backend/core/__init__.py`** (empty file)

- [ ] **Step 11: Create `backend/core/apps.py`**

```python
from django.apps import AppConfig


class CoreConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "core"
```

- [ ] **Step 12: Boot the stack and verify Django runs**

```bash
cd backend
cp .env.example .env
docker compose up -d
uv sync
# Verify settings load (will print "System check identified no issues")
uv run manage.py check
```

Expected: `System check identified no issues (0 silenced).` (will fail to import `api.ninja` at this point — that's expected; we wire the URL include in Task 6. For now, temporarily comment out the `urls.py` include.)

Actually, to keep `manage.py check` green: edit `backend/lucidboard_api/urls.py` to:
```python
from django.urls import path
urlpatterns = []
```
We'll restore the `api.urls` include in Task 6.

- [ ] **Step 13: Commit**

```bash
git add backend/
git commit -m "feat(backend): scaffold Django Ninja project with Postgres+pgvector compose"
```

---

### Task 2: Database models + initial migration

**Files:**
- Create: `backend/core/models.py`
- Create: `backend/core/managers.py`
- Create: `backend/core/migrations/__init__.py`
- Create: `backend/core/migrations/0001_initial.py` (generated then committed)
- Test: `backend/core/tests/test_models.py` (created later in Task 9 onwards)

- [ ] **Step 1: Create `backend/core/managers.py`**

```python
from __future__ import annotations

from django.contrib.auth.models import BaseUserManager
from django.db import models


class UserScopedManager(models.Manager):
    """Manager that filters queries to a specific user_id.

    Used as a helper from views: `Board.objects.for_user(user)`.
    """

    def for_user(self, user):
        return self.filter(user_id=user.id)


class AnonymousUserManager(BaseUserManager):
    """User manager that only supports anonymous users.

    Phase 1 anonymous-only auth. `create_anonymous()` makes a row with
    is_anonymous=True. No password support.
    """

    def create_anonymous(self):
        user = self.model(is_anonymous=True)
        user.set_unusable_password()
        user.save(using=self._db)
        return user
```

- [ ] **Step 2: Create `backend/core/models.py`**

```python
from __future__ import annotations

import uuid

from django.contrib.auth.models import AbstractBaseUser
from django.db import models
from pgvector.django import VectorField

from core.managers import AnonymousUserManager, UserScopedManager


class User(AbstractBaseUser):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    is_anonymous_user = models.BooleanField(default=True, db_column="is_anonymous")
    created_at = models.DateTimeField(auto_now_add=True)

    objects = AnonymousUserManager()

    USERNAME_FIELD = "id"
    REQUIRED_FIELDS: list[str] = []

    class Meta:
        db_table = "users"

    @property
    def is_authenticated(self) -> bool:  # ninja/django use this
        return True


class Board(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, db_column="user_id")
    title = models.TextField()
    background_color = models.TextField(default="#FFFFFF")
    background_layout = models.TextField(default="grid")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserScopedManager()

    class Meta:
        db_table = "boards"


class Note(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    board = models.ForeignKey(Board, on_delete=models.CASCADE, db_column="board_id")
    user = models.ForeignKey(User, on_delete=models.CASCADE, db_column="user_id")
    content_text = models.TextField(null=True, blank=True)
    content_drawing = models.BinaryField(null=True, blank=True)
    color = models.TextField()
    pos_x = models.FloatField()
    pos_y = models.FloatField()
    z_index = models.IntegerField()
    template = models.TextField(default="plain")
    checklist_items = models.JSONField(default=list)
    embedding = VectorField(dimensions=768, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserScopedManager()

    class Meta:
        db_table = "notes"


class Profile(models.Model):
    user = models.OneToOneField(
        User, on_delete=models.CASCADE, primary_key=True, db_column="id"
    )
    settings = models.JSONField(default=dict)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "profiles"
```

- [ ] **Step 3: Create `backend/core/migrations/__init__.py`** (empty file)

- [ ] **Step 4: Generate the initial migration**

```bash
cd backend
uv run manage.py makemigrations core
```

Expected output: `Migrations for 'core': core/migrations/0001_initial.py - Create model User, Create model Board, Create model Note, Create model Profile`.

Then **manually edit** the generated `0001_initial.py` to add `pgvector` extension creation as the very first operation. Add this import at the top:

```python
from pgvector.django import VectorExtension
```

And insert as the first item in `operations`:

```python
operations = [
    VectorExtension(),
    # ... the rest of the auto-generated operations
]
```

- [ ] **Step 5: Apply the migration**

```bash
uv run manage.py migrate
```

Expected: `Applying core.0001_initial... OK`.

- [ ] **Step 6: Sanity-check the schema in Postgres**

```bash
docker exec -i lucidboard-db psql -U lucidboard -d lucidboard -c "\d notes"
```

Expected: column listing includes `embedding | vector(768)`.

- [ ] **Step 7: Commit**

```bash
git add backend/core/models.py backend/core/managers.py backend/core/migrations/
git commit -m "feat(backend): User/Board/Note/Profile models with pgvector embedding"
```

---

### Task 3: Port `match_notes` SQL function

**Files:**
- Create: `backend/core/migrations/0002_match_notes_function.py`

- [ ] **Step 1: Create the migration file**

`backend/core/migrations/0002_match_notes_function.py`:

```python
from django.db import migrations

MATCH_NOTES_SQL = r"""
CREATE OR REPLACE FUNCTION match_notes(board_uuid uuid)
RETURNS TABLE (id uuid, new_x float4, new_y float4)
LANGUAGE plpgsql
AS $$
DECLARE
    cluster_spacing      float4 := 280;
    cluster_gap          float4 := 400;
    similarity_threshold float8 := 0.15;
    canvas_origin_x      float4 := 200;
    canvas_origin_y      float4 := 200;
BEGIN
    RETURN QUERY
    WITH
    embedded AS (
        SELECT n.id, n.embedding
        FROM notes n
        WHERE n.board_id = board_uuid
          AND n.embedding IS NOT NULL
    ),
    nearest AS (
        SELECT DISTINCT ON (a.id)
            a.id,
            b.id AS nearest_id,
            (a.embedding <=> b.embedding) AS dist
        FROM embedded a
        JOIN embedded b ON b.id <> a.id
        ORDER BY a.id, dist ASC
    ),
    cluster_seeds AS (
        SELECT
            n.id,
            CASE
                WHEN nr.dist > similarity_threshold THEN n.id
                WHEN n.id < nr.nearest_id            THEN n.id
                ELSE nr.nearest_id
            END AS cluster_id
        FROM embedded n
        JOIN nearest nr ON nr.id = n.id
    ),
    all_notes_clustered AS (
        SELECT cs.id, cs.cluster_id
        FROM cluster_seeds cs
        UNION ALL
        SELECT n.id, n.id AS cluster_id
        FROM notes n
        WHERE n.board_id = board_uuid
          AND n.embedding IS NULL
    ),
    cluster_meta AS (
        SELECT
            cluster_id,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, cluster_id) - 1 AS cluster_idx,
            COUNT(*) AS cluster_size
        FROM all_notes_clustered
        GROUP BY cluster_id
    ),
    note_rank AS (
        SELECT
            anc.id,
            anc.cluster_id,
            cm.cluster_idx,
            cm.cluster_size,
            ROW_NUMBER() OVER (PARTITION BY anc.cluster_id ORDER BY anc.id) - 1 AS pos_in_cluster
        FROM all_notes_clustered anc
        JOIN cluster_meta cm ON cm.cluster_id = anc.cluster_id
    ),
    positioned AS (
        SELECT
            nr.id,
            (canvas_origin_x + nr.cluster_idx * (cluster_spacing + cluster_gap))::float4 AS new_x,
            (canvas_origin_y + nr.pos_in_cluster * cluster_spacing)::float4              AS new_y
        FROM note_rank nr
    )
    SELECT p.id, p.new_x, p.new_y
    FROM positioned p;
END;
$$;
"""

DROP_MATCH_NOTES_SQL = "DROP FUNCTION IF EXISTS match_notes(uuid);"


class Migration(migrations.Migration):
    dependencies = [("core", "0001_initial")]

    operations = [
        migrations.RunSQL(MATCH_NOTES_SQL, DROP_MATCH_NOTES_SQL),
    ]
```

- [ ] **Step 2: Apply the migration**

```bash
cd backend
uv run manage.py migrate
```

Expected: `Applying core.0002_match_notes_function... OK`.

- [ ] **Step 3: Sanity-check the function exists**

```bash
docker exec -i lucidboard-db psql -U lucidboard -d lucidboard -c "\df match_notes"
```

Expected: one row showing `match_notes | TABLE(id uuid, new_x real, new_y real)`.

- [ ] **Step 4: Commit**

```bash
git add backend/core/migrations/0002_match_notes_function.py
git commit -m "feat(backend): port match_notes pgvector clustering function"
```

---

### Task 4: JWT module (mint + decode + JWTBearer)

**Files:**
- Create: `backend/core/auth.py`
- Create: `backend/api/__init__.py`
- Create: `backend/api/tests/__init__.py`
- Create: `backend/api/conftest.py`
- Test: `backend/api/tests/test_auth_module.py`

- [ ] **Step 1: Create `backend/api/__init__.py` and `backend/api/tests/__init__.py`** (both empty files)

- [ ] **Step 2: Create `backend/api/conftest.py`**

```python
import pytest
from django.test import Client


@pytest.fixture
def client():
    return Client()
```

- [ ] **Step 3: Write failing test `backend/api/tests/test_auth_module.py`**

```python
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import pytest
from django.conf import settings

from core.auth import decode_token, mint_anonymous_token
from core.models import User

pytestmark = pytest.mark.django_db


def test_mint_anonymous_token_creates_user():
    user, token = mint_anonymous_token()
    assert User.objects.filter(id=user.id).exists()
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

- [ ] **Step 4: Run tests, expect FAIL**

```bash
cd backend
uv run pytest api/tests/test_auth_module.py -v
```

Expected: ImportError on `core.auth` (module doesn't exist yet).

- [ ] **Step 5: Implement `backend/core/auth.py`**

```python
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
from django.conf import settings
from ninja.security import HttpBearer

from core.models import User


def mint_anonymous_token() -> tuple[User, str]:
    """Create a fresh anonymous user and return (user, signed_jwt)."""
    user = User.objects.create_anonymous()
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
    """Verify a JWT and return the User row it identifies.

    Raises jwt.InvalidTokenError subclasses on failure
    (InvalidSignatureError, ExpiredSignatureError, ...).
    """
    payload = jwt.decode(
        token, settings.JWT_SECRET, algorithms=["HS256"], audience="authenticated"
    )
    return User.objects.get(id=payload["sub"])


class JWTBearer(HttpBearer):
    """Ninja auth class. Returns the User on success, None on failure."""

    def authenticate(self, request, token: str) -> User | None:
        try:
            user = decode_token(token)
        except (jwt.InvalidTokenError, User.DoesNotExist):
            return None
        request.user = user
        return user
```

- [ ] **Step 6: Run tests, expect PASS**

```bash
uv run pytest api/tests/test_auth_module.py -v
```

Expected: 5 passed.

- [ ] **Step 7: Commit**

```bash
git add backend/core/auth.py backend/api/
git commit -m "feat(backend): JWT auth module with mint/decode + JWTBearer"
```

---

### Task 5: Embeddings module

**Files:**
- Create: `backend/core/embeddings.py`
- Test: `backend/api/tests/test_embeddings.py`

- [ ] **Step 1: Write failing test `backend/api/tests/test_embeddings.py`**

```python
from unittest.mock import patch

import pytest

from core.embeddings import generate_embedding


def test_generate_embedding_returns_none_for_empty_text():
    assert generate_embedding("") is None
    assert generate_embedding("   ") is None


def test_generate_embedding_calls_gemini_and_returns_vector():
    fake_vector = [0.1] * 768
    fake_response = type("R", (), {"__getitem__": lambda self, k: fake_vector})()
    with patch("core.embeddings._embed") as mock_embed:
        mock_embed.return_value = {"embedding": fake_vector}
        result = generate_embedding("Hello world")
    mock_embed.assert_called_once_with("Hello world")
    assert result == fake_vector


def test_generate_embedding_returns_none_on_gemini_error():
    with patch("core.embeddings._embed", side_effect=RuntimeError("boom")):
        result = generate_embedding("Hello world")
    assert result is None


def test_generate_embedding_returns_none_when_no_api_key(settings):
    settings.GEMINI_API_KEY = ""
    result = generate_embedding("Hello world")
    assert result is None
```

- [ ] **Step 2: Run tests, expect FAIL**

```bash
uv run pytest api/tests/test_embeddings.py -v
```

Expected: ImportError on `core.embeddings`.

- [ ] **Step 3: Implement `backend/core/embeddings.py`**

```python
from __future__ import annotations

import logging

import google.generativeai as genai
from django.conf import settings

logger = logging.getLogger(__name__)

_MODEL = "models/text-embedding-004"


def _embed(text: str) -> dict:
    """Real Gemini call, isolated for mocking in tests."""
    genai.configure(api_key=settings.GEMINI_API_KEY)
    return genai.embed_content(model=_MODEL, content=text)


def generate_embedding(text: str) -> list[float] | None:
    """Return a 768-dim embedding for `text`, or None on any failure.

    Returns None — without raising — when text is empty, the API key is
    not configured, or the Gemini call fails. Caller must persist None
    as a null embedding column.
    """
    if not text or not text.strip():
        return None
    if not settings.GEMINI_API_KEY:
        logger.warning("GEMINI_API_KEY not set; storing null embedding")
        return None
    try:
        result = _embed(text.strip())
        return list(result["embedding"])
    except Exception:  # noqa: BLE001 — deliberate broad catch for graceful degradation
        logger.exception("Gemini embedding failed; storing null embedding")
        return None
```

- [ ] **Step 4: Run tests, expect PASS**

```bash
uv run pytest api/tests/test_embeddings.py -v
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add backend/core/embeddings.py backend/api/tests/test_embeddings.py
git commit -m "feat(backend): Gemini embedding wrapper with graceful failure"
```

---

### Task 6: Ninja app root + exception handler

**Files:**
- Create: `backend/api/ninja.py`
- Modify: `backend/lucidboard_api/urls.py` (restore the `api.urls` include)
- Test: `backend/api/tests/test_health.py`

- [ ] **Step 1: Write failing test `backend/api/tests/test_health.py`**

```python
import pytest

pytestmark = pytest.mark.django_db


def test_health_endpoint_returns_ok(client):
    res = client.get("/api/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_404_returns_json(client):
    res = client.get("/api/nonexistent")
    assert res.status_code == 404
    assert res.headers["content-type"].startswith("application/json")
```

- [ ] **Step 2: Run tests, expect FAIL**

```bash
uv run pytest api/tests/test_health.py -v
```

Expected: 404 for `/api/health`.

- [ ] **Step 3: Create `backend/api/ninja.py`**

```python
from __future__ import annotations

import jwt
from django.http import HttpRequest
from ninja import NinjaAPI
from ninja.errors import AuthenticationError, ValidationError

api = NinjaAPI(title="LucidBoard Local API", version="0.1.0", urls_namespace="api")


@api.get("/api/health")
def health(request: HttpRequest):
    return {"status": "ok"}


@api.exception_handler(AuthenticationError)
def on_auth_error(request, exc):
    return api.create_response(
        request, {"detail": "Unauthorized", "code": "unauthorized"}, status=401
    )


@api.exception_handler(jwt.ExpiredSignatureError)
def on_expired(request, exc):
    return api.create_response(
        request, {"detail": "Token expired", "code": "token_expired"}, status=401
    )


@api.exception_handler(ValidationError)
def on_validation(request, exc):
    return api.create_response(
        request,
        {"detail": "Validation failed", "code": "validation_error", "errors": exc.errors},
        status=422,
    )
```

- [ ] **Step 4: Restore `backend/lucidboard_api/urls.py`**

```python
from django.urls import path

from api.ninja import api

urlpatterns = [
    path("", api.urls),
]
```

- [ ] **Step 5: Run tests, expect PASS**

```bash
uv run pytest api/tests/test_health.py -v
```

Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add backend/api/ninja.py backend/lucidboard_api/urls.py backend/api/tests/test_health.py
git commit -m "feat(backend): Ninja app root with health endpoint and exception handlers"
```

---

### Task 7: Pydantic schemas

**Files:**
- Create: `backend/api/schemas.py`

`★ Note ─────────────────────────────────────`
The schemas use Django Ninja's `Schema` (a thin Pydantic v2 wrapper). Field names match Swift's `CodingKeys` (snake_case) so JSON shape is identical across both repositories. No tests for this file — it's pure declarations exercised by the router tests.
`─────────────────────────────────────────────`

- [ ] **Step 1: Create `backend/api/schemas.py`**

```python
from __future__ import annotations

from datetime import datetime
from uuid import UUID

from ninja import Schema


class ChecklistItemSchema(Schema):
    id: UUID
    text: str
    is_completed: bool = False


# --- Auth ---

class AuthUserOut(Schema):
    id: UUID
    is_anonymous: bool


class AuthResponse(Schema):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user: AuthUserOut


# --- Boards ---

class BoardOut(Schema):
    id: UUID
    user_id: UUID
    title: str
    background_color: str
    background_layout: str
    created_at: datetime
    updated_at: datetime


class BoardUpdateIn(Schema):
    title: str | None = None
    background_color: str | None = None
    background_layout: str | None = None


# --- Notes ---

class NoteOut(Schema):
    id: UUID
    board_id: UUID
    user_id: UUID
    content_text: str | None
    content_drawing: str | None  # base64
    color: str
    pos_x: float
    pos_y: float
    z_index: int
    template: str
    checklist_items: list[ChecklistItemSchema]
    created_at: datetime
    updated_at: datetime


class NoteUpsertIn(Schema):
    board_id: UUID
    content_text: str | None = None
    content_drawing: str | None = None  # base64
    color: str
    pos_x: float
    pos_y: float
    z_index: int
    template: str = "plain"
    checklist_items: list[ChecklistItemSchema] = []


# --- Profile ---

class ProfileOut(Schema):
    settings: dict


class ProfileUpsertIn(Schema):
    settings: dict


# --- RPC ---

class MatchNotesIn(Schema):
    board_uuid: UUID


class MatchNoteResult(Schema):
    id: UUID
    new_x: float
    new_y: float
```

- [ ] **Step 2: Verify schemas import cleanly**

```bash
uv run python -c "from api.schemas import NoteOut, AuthResponse; print('ok')"
```

Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add backend/api/schemas.py
git commit -m "feat(backend): Pydantic schemas matching Swift CodingKeys"
```

---

### Task 8: Auth router (anonymous signup)

**Files:**
- Create: `backend/api/routers/__init__.py`
- Create: `backend/api/routers/auth.py`
- Modify: `backend/api/ninja.py` (register router)
- Test: `backend/api/tests/test_auth.py`

- [ ] **Step 1: Create `backend/api/routers/__init__.py`** (empty file)

- [ ] **Step 2: Write failing test `backend/api/tests/test_auth.py`**

```python
import pytest
from django.conf import settings
import jwt

from core.models import User

pytestmark = pytest.mark.django_db


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
    assert User.objects.filter(id=body["user"]["id"]).exists()


def test_anonymous_signup_without_query_param_returns_400(client):
    res = client.post("/auth/v1/signup")
    assert res.status_code == 400
    assert res.json()["code"] == "anonymous_required"
```

- [ ] **Step 3: Run tests, expect FAIL**

```bash
uv run pytest api/tests/test_auth.py -v
```

Expected: 404 on `/auth/v1/signup`.

- [ ] **Step 4: Create `backend/api/routers/auth.py`**

```python
from __future__ import annotations

from django.conf import settings
from django.http import HttpRequest
from ninja import Router

from api.schemas import AuthResponse, AuthUserOut
from core.auth import mint_anonymous_token

router = Router()


@router.post("/v1/signup", response={200: AuthResponse, 400: dict})
def signup(request: HttpRequest, anonymous: bool = False):
    if not anonymous:
        return 400, {"detail": "anonymous=true required (Phase 1)", "code": "anonymous_required"}
    user, token = mint_anonymous_token()
    return 200, AuthResponse(
        access_token=token,
        token_type="bearer",
        expires_in=settings.JWT_EXPIRY_SECONDS,
        user=AuthUserOut(id=user.id, is_anonymous=True),
    )
```

- [ ] **Step 5: Register router in `backend/api/ninja.py`**

Add after the existing imports:
```python
from api.routers.auth import router as auth_router
```

And after `api = NinjaAPI(...)`:
```python
api.add_router("/auth", auth_router)
```

- [ ] **Step 6: Run tests, expect PASS**

```bash
uv run pytest api/tests/test_auth.py -v
```

Expected: 2 passed.

- [ ] **Step 7: Commit**

```bash
git add backend/api/routers/ backend/api/ninja.py backend/api/tests/test_auth.py
git commit -m "feat(backend): anonymous signup endpoint at /auth/v1/signup"
```

---

### Task 9: Boards router (list, update)

**Files:**
- Create: `backend/api/routers/boards.py`
- Modify: `backend/api/ninja.py`
- Test: `backend/api/tests/test_boards.py`

- [ ] **Step 1: Add an `auth_client` fixture to `backend/api/conftest.py`**

```python
import pytest
from django.test import Client

from core.auth import mint_anonymous_token


@pytest.fixture
def client():
    return Client()


@pytest.fixture
def auth_client(db):
    user, token = mint_anonymous_token()
    c = Client(HTTP_AUTHORIZATION=f"Bearer {token}")
    c.user = user
    return c
```

- [ ] **Step 2: Write failing test `backend/api/tests/test_boards.py`**

```python
import pytest

from core.models import Board

pytestmark = pytest.mark.django_db


def test_list_boards_returns_only_users_boards(auth_client):
    Board.objects.create(user=auth_client.user, title="Mine")
    other = Board.objects.create(user_id=__import__("uuid").uuid4(), title="Theirs")
    res = auth_client.get("/api/boards")
    assert res.status_code == 200
    titles = [b["title"] for b in res.json()]
    assert "Mine" in titles
    assert "Theirs" not in titles


def test_list_boards_requires_auth(client):
    res = client.get("/api/boards")
    assert res.status_code == 401


def test_update_board(auth_client):
    board = Board.objects.create(user=auth_client.user, title="Old")
    res = auth_client.patch(
        f"/api/boards/{board.id}",
        data={"title": "New", "background_color": "#000"},
        content_type="application/json",
    )
    assert res.status_code == 200
    board.refresh_from_db()
    assert board.title == "New"
    assert board.background_color == "#000"


def test_update_other_users_board_returns_404(auth_client):
    import uuid
    other = Board.objects.create(user_id=uuid.uuid4(), title="Theirs")
    res = auth_client.patch(
        f"/api/boards/{other.id}",
        data={"title": "Hacked"},
        content_type="application/json",
    )
    assert res.status_code == 404
```

- [ ] **Step 3: Run tests, expect FAIL**

```bash
uv run pytest api/tests/test_boards.py -v
```

Expected: 404 / route-not-found errors.

- [ ] **Step 4: Implement `backend/api/routers/boards.py`**

```python
from __future__ import annotations

from uuid import UUID

from django.http import HttpRequest
from django.shortcuts import get_object_or_404
from ninja import Router

from api.schemas import BoardOut, BoardUpdateIn
from core.auth import JWTBearer
from core.models import Board

router = Router(auth=JWTBearer())


@router.get("/boards", response=list[BoardOut])
def list_boards(request: HttpRequest):
    return list(Board.objects.for_user(request.auth).order_by("-updated_at"))


@router.patch("/boards/{board_id}", response=BoardOut)
def update_board(request: HttpRequest, board_id: UUID, payload: BoardUpdateIn):
    board = get_object_or_404(Board, id=board_id, user_id=request.auth.id)
    for field, value in payload.dict(exclude_unset=True).items():
        setattr(board, field, value)
    board.save()
    return board
```

- [ ] **Step 5: Register router in `backend/api/ninja.py`**

Add:
```python
from api.routers.boards import router as boards_router
api.add_router("/api", boards_router)
```

- [ ] **Step 6: Run tests, expect PASS**

```bash
uv run pytest api/tests/test_boards.py -v
```

Expected: 4 passed.

- [ ] **Step 7: Commit**

```bash
git add backend/api/routers/boards.py backend/api/ninja.py backend/api/conftest.py backend/api/tests/test_boards.py
git commit -m "feat(backend): boards router with ownership checks"
```

---

### Task 10: Notes router (list-by-board, upsert with embed, delete)

**Files:**
- Create: `backend/api/routers/notes.py`
- Modify: `backend/api/ninja.py`
- Test: `backend/api/tests/test_notes.py`

- [ ] **Step 1: Write failing test `backend/api/tests/test_notes.py`**

```python
import uuid
from unittest.mock import patch

import pytest

from core.models import Board, Note

pytestmark = pytest.mark.django_db


@pytest.fixture
def board(auth_client):
    return Board.objects.create(user=auth_client.user, title="b")


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


def test_list_notes_for_board(auth_client, board):
    Note.objects.create(
        board=board, user=auth_client.user, color="#fff", pos_x=0, pos_y=0, z_index=0
    )
    res = auth_client.get(f"/api/boards/{board.id}/notes")
    assert res.status_code == 200
    assert len(res.json()) == 1


def test_list_notes_for_other_users_board_returns_404(auth_client):
    other_board = Board.objects.create(user_id=uuid.uuid4(), title="theirs")
    res = auth_client.get(f"/api/boards/{other_board.id}/notes")
    assert res.status_code == 404


def test_upsert_creates_note_and_calls_embedding(auth_client, board):
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
    note = Note.objects.get(id=note_id)
    assert list(note.embedding) == fake_vector


def test_upsert_skips_embedding_when_content_unchanged(auth_client, board):
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
    note = Note.objects.get(id=note_id)
    assert note.color == "#000"


def test_upsert_on_other_users_board_returns_404(auth_client):
    other_board = Board.objects.create(user_id=uuid.uuid4(), title="theirs")
    note_id = uuid.uuid4()
    with patch("api.routers.notes.generate_embedding", return_value=None):
        res = auth_client.put(
            f"/api/notes/{note_id}",
            data=_note_payload(other_board.id),
            content_type="application/json",
        )
    assert res.status_code == 404


def test_delete_note(auth_client, board):
    note = Note.objects.create(
        board=board, user=auth_client.user, color="#fff", pos_x=0, pos_y=0, z_index=0
    )
    res = auth_client.delete(f"/api/notes/{note.id}")
    assert res.status_code == 204
    assert not Note.objects.filter(id=note.id).exists()


def test_delete_other_users_note_returns_404(auth_client):
    other_board = Board.objects.create(user_id=uuid.uuid4(), title="theirs")
    note = Note.objects.create(
        board=other_board, user_id=other_board.user_id,
        color="#fff", pos_x=0, pos_y=0, z_index=0
    )
    res = auth_client.delete(f"/api/notes/{note.id}")
    assert res.status_code == 404
```

- [ ] **Step 2: Run tests, expect FAIL**

```bash
uv run pytest api/tests/test_notes.py -v
```

Expected: 404 / route-not-found errors.

- [ ] **Step 3: Implement `backend/api/routers/notes.py`**

```python
from __future__ import annotations

import base64
from uuid import UUID

from django.http import HttpRequest
from django.shortcuts import get_object_or_404
from ninja import Router

from api.schemas import NoteOut, NoteUpsertIn
from core.auth import JWTBearer
from core.embeddings import generate_embedding
from core.models import Board, Note

router = Router(auth=JWTBearer())


def _decode_drawing(b64: str | None) -> bytes | None:
    return base64.b64decode(b64) if b64 else None


def _encode_drawing(data: bytes | memoryview | None) -> str | None:
    return base64.b64encode(bytes(data)).decode() if data else None


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
    get_object_or_404(Board, id=board_id, user_id=request.auth.id)
    notes = Note.objects.filter(board_id=board_id).order_by("z_index")
    return [_serialize(n) for n in notes]


@router.put("/notes/{note_id}", response=NoteOut)
def upsert_note(request: HttpRequest, note_id: UUID, payload: NoteUpsertIn):
    get_object_or_404(Board, id=payload.board_id, user_id=request.auth.id)
    existing = Note.objects.filter(id=note_id).first()

    # Determine whether to call Gemini.
    new_text = payload.content_text or ""
    if existing is not None and existing.content_text == payload.content_text:
        embedding = existing.embedding  # reuse
    else:
        embedding = generate_embedding(new_text)

    note, _ = Note.objects.update_or_create(
        id=note_id,
        defaults={
            "board_id": payload.board_id,
            "user_id": request.auth.id,
            "content_text": payload.content_text,
            "content_drawing": _decode_drawing(payload.content_drawing),
            "color": payload.color,
            "pos_x": payload.pos_x,
            "pos_y": payload.pos_y,
            "z_index": payload.z_index,
            "template": payload.template,
            "checklist_items": [item.dict() for item in payload.checklist_items],
            "embedding": embedding,
        },
    )
    return _serialize(note)


@router.delete("/notes/{note_id}", response={204: None})
def delete_note(request: HttpRequest, note_id: UUID):
    note = get_object_or_404(Note, id=note_id, user_id=request.auth.id)
    note.delete()
    return 204, None
```

- [ ] **Step 4: Register in `backend/api/ninja.py`**

Add:
```python
from api.routers.notes import router as notes_router
api.add_router("/api", notes_router)
```

- [ ] **Step 5: Run tests, expect PASS**

```bash
uv run pytest api/tests/test_notes.py -v
```

Expected: 7 passed.

- [ ] **Step 6: Commit**

```bash
git add backend/api/routers/notes.py backend/api/ninja.py backend/api/tests/test_notes.py
git commit -m "feat(backend): notes router with embed-on-write and skip-rule"
```

---

### Task 11: Profiles router

**Files:**
- Create: `backend/api/routers/profiles.py`
- Modify: `backend/api/ninja.py`
- Test: `backend/api/tests/test_profiles.py`

- [ ] **Step 1: Write failing test `backend/api/tests/test_profiles.py`**

```python
import pytest

from core.models import Profile

pytestmark = pytest.mark.django_db


def test_get_profile_auto_creates_on_first_call(auth_client):
    assert not Profile.objects.filter(user=auth_client.user).exists()
    res = auth_client.get("/api/profile")
    assert res.status_code == 200
    assert res.json() == {"settings": {}}
    assert Profile.objects.filter(user=auth_client.user).exists()


def test_upsert_profile(auth_client):
    res = auth_client.put(
        "/api/profile",
        data={"settings": {"defaultNoteColor": "#000"}},
        content_type="application/json",
    )
    assert res.status_code == 200
    profile = Profile.objects.get(user=auth_client.user)
    assert profile.settings == {"defaultNoteColor": "#000"}
```

- [ ] **Step 2: Run tests, expect FAIL**

```bash
uv run pytest api/tests/test_profiles.py -v
```

- [ ] **Step 3: Implement `backend/api/routers/profiles.py`**

```python
from __future__ import annotations

from django.http import HttpRequest
from ninja import Router

from api.schemas import ProfileOut, ProfileUpsertIn
from core.auth import JWTBearer
from core.models import Profile

router = Router(auth=JWTBearer())


@router.get("/profile", response=ProfileOut)
def get_profile(request: HttpRequest):
    profile, _ = Profile.objects.get_or_create(user=request.auth)
    return ProfileOut(settings=profile.settings)


@router.put("/profile", response=ProfileOut)
def upsert_profile(request: HttpRequest, payload: ProfileUpsertIn):
    profile, _ = Profile.objects.update_or_create(
        user=request.auth, defaults={"settings": payload.settings}
    )
    return ProfileOut(settings=profile.settings)
```

- [ ] **Step 4: Register in `backend/api/ninja.py`**

```python
from api.routers.profiles import router as profiles_router
api.add_router("/api", profiles_router)
```

- [ ] **Step 5: Run tests, expect PASS**

```bash
uv run pytest api/tests/test_profiles.py -v
```

Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add backend/api/routers/profiles.py backend/api/ninja.py backend/api/tests/test_profiles.py
git commit -m "feat(backend): profile router with auto-create on get"
```

---

### Task 12: RPC router (`match_notes`)

**Files:**
- Create: `backend/api/routers/rpc.py`
- Modify: `backend/api/ninja.py`
- Test: `backend/api/tests/test_rpc.py`

- [ ] **Step 1: Write failing test `backend/api/tests/test_rpc.py`**

```python
import uuid

import pytest

from core.models import Board, Note

pytestmark = pytest.mark.django_db


def _fake_embedding(seed: float) -> list[float]:
    return [seed] * 768


def test_match_notes_returns_positions(auth_client):
    board = Board.objects.create(user=auth_client.user, title="b")
    n1 = Note.objects.create(
        board=board, user=auth_client.user, color="#fff", pos_x=0, pos_y=0, z_index=0,
        content_text="cat", embedding=_fake_embedding(0.1),
    )
    n2 = Note.objects.create(
        board=board, user=auth_client.user, color="#fff", pos_x=0, pos_y=0, z_index=1,
        content_text="kitten", embedding=_fake_embedding(0.1),
    )
    n3 = Note.objects.create(
        board=board, user=auth_client.user, color="#fff", pos_x=0, pos_y=0, z_index=2,
        content_text="rocket", embedding=_fake_embedding(0.9),
    )
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
    other_board = Board.objects.create(user_id=uuid.uuid4(), title="theirs")
    res = auth_client.post(
        "/api/rpc/match_notes",
        data={"board_uuid": str(other_board.id)},
        content_type="application/json",
    )
    assert res.status_code == 404


def test_match_notes_returns_empty_for_board_with_no_notes(auth_client):
    board = Board.objects.create(user=auth_client.user, title="b")
    res = auth_client.post(
        "/api/rpc/match_notes",
        data={"board_uuid": str(board.id)},
        content_type="application/json",
    )
    assert res.status_code == 200
    assert res.json() == []
```

- [ ] **Step 2: Run tests, expect FAIL**

```bash
uv run pytest api/tests/test_rpc.py -v
```

- [ ] **Step 3: Implement `backend/api/routers/rpc.py`**

```python
from __future__ import annotations

from django.db import connection
from django.http import HttpRequest
from django.shortcuts import get_object_or_404
from ninja import Router

from api.schemas import MatchNoteResult, MatchNotesIn
from core.auth import JWTBearer
from core.models import Board

router = Router(auth=JWTBearer())


@router.post("/rpc/match_notes", response=list[MatchNoteResult])
def match_notes(request: HttpRequest, payload: MatchNotesIn):
    get_object_or_404(Board, id=payload.board_uuid, user_id=request.auth.id)
    with connection.cursor() as cur:
        cur.execute("SELECT id, new_x, new_y FROM match_notes(%s);", [str(payload.board_uuid)])
        rows = cur.fetchall()
    return [
        MatchNoteResult(id=row[0], new_x=row[1], new_y=row[2]) for row in rows
    ]
```

- [ ] **Step 4: Register in `backend/api/ninja.py`**

```python
from api.routers.rpc import router as rpc_router
api.add_router("/api", rpc_router)
```

- [ ] **Step 5: Run tests, expect PASS**

```bash
uv run pytest api/tests/test_rpc.py -v
```

Expected: 3 passed.

- [ ] **Step 6: Run the entire backend test suite**

```bash
uv run pytest -v
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add backend/api/routers/rpc.py backend/api/ninja.py backend/api/tests/test_rpc.py
git commit -m "feat(backend): match_notes RPC endpoint backed by Postgres function"
```

---

### Task 13: Smoke script

**Files:**
- Create: `backend/scripts/smoke.sh`

- [ ] **Step 1: Create `backend/scripts/smoke.sh`**

```bash
#!/usr/bin/env bash
# End-to-end smoke test against a running local backend.
# Usage: ./scripts/smoke.sh
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8000}"

echo "==> signup"
TOKEN=$(curl -sf -X POST "$BASE/auth/v1/signup?anonymous=true" | python -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="Authorization: Bearer $TOKEN"

echo "==> create board (via direct ORM not exposed yet — use a known UUID and let auto-create elsewhere)"
# Boards are normally created by the Swift app; for smoke we insert via psql to keep the test deterministic.
BOARD_ID=$(python -c 'import uuid;print(uuid.uuid4())')
USER_ID=$(python -c 'import sys,json,base64;tok=sys.argv[1].split(".")[1];tok+="="*((4-len(tok)%4)%4);print(json.loads(base64.urlsafe_b64decode(tok))["sub"])' "$TOKEN")
docker exec -i lucidboard-db psql -U lucidboard -d lucidboard -c \
  "INSERT INTO boards (id, user_id, title, background_color, background_layout, created_at, updated_at) VALUES ('$BOARD_ID', '$USER_ID', 'Smoke', '#FFFFFF', 'grid', now(), now());"

echo "==> list boards"
curl -sf -H "$AUTH" "$BASE/api/boards" | python -m json.tool

echo "==> create note"
NOTE_ID=$(python -c 'import uuid;print(uuid.uuid4())')
curl -sf -X PUT -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"board_id\":\"$BOARD_ID\",\"color\":\"#FFF9C4\",\"pos_x\":1.0,\"pos_y\":2.0,\"z_index\":0,\"content_text\":\"smoke\",\"template\":\"plain\",\"checklist_items\":[]}" \
  "$BASE/api/notes/$NOTE_ID" | python -m json.tool

echo "==> list notes"
curl -sf -H "$AUTH" "$BASE/api/boards/$BOARD_ID/notes" | python -m json.tool

echo "==> delete note"
curl -sf -X DELETE -H "$AUTH" "$BASE/api/notes/$NOTE_ID" -o /dev/null -w "delete status: %{http_code}\n"

echo "==> SMOKE OK"
```

- [ ] **Step 2: Make it executable and run it against a live server**

```bash
chmod +x backend/scripts/smoke.sh
cd backend
docker compose up -d
uv run manage.py migrate
uv run manage.py runserver &
SERVER_PID=$!
sleep 2
./scripts/smoke.sh
kill $SERVER_PID
```

Expected: ends with `==> SMOKE OK`.

- [ ] **Step 3: Commit**

```bash
git add backend/scripts/smoke.sh
git commit -m "feat(backend): end-to-end smoke script"
```

---

### Task 14: Backend README

**Files:**
- Create: `backend/README.md`

- [ ] **Step 1: Create `backend/README.md`**

```markdown
# LucidBoard Local Backend

Lightweight Django Ninja API that replaces Supabase for local development.
Production still uses Supabase — this exists so a developer can hack on
the Swift app without depending on a remote Supabase project or running
the full Supabase Docker stack.

## Bootstrap

```bash
cp .env.example .env
# Optional: set GEMINI_API_KEY in .env (without it, embeddings are null)
docker compose up -d              # postgres+pgvector on :5432
uv sync
uv run manage.py migrate
uv run manage.py runserver        # http://127.0.0.1:8000
```

In Xcode, set `BACKEND_KIND = local` in `Config.xcconfig` and build/run.

## Testing

```bash
uv run pytest -v
./scripts/smoke.sh   # against a running server
```

## API surface

| Method | Path | Auth |
|---|---|---|
| `POST` | `/auth/v1/signup?anonymous=true` | none |
| `GET` | `/api/health` | none |
| `GET` | `/api/boards` | bearer |
| `PATCH` | `/api/boards/{id}` | bearer |
| `GET` | `/api/boards/{id}/notes` | bearer |
| `PUT` | `/api/notes/{id}` | bearer |
| `DELETE` | `/api/notes/{id}` | bearer |
| `GET` | `/api/profile` | bearer |
| `PUT` | `/api/profile` | bearer |
| `POST` | `/api/rpc/match_notes` | bearer |

## Limitations (Phase 1)

- Anonymous-only auth (no email/password, no OAuth)
- No realtime/WebSocket sync (LocalAPIRepository returns inert subscription)
- Local dev only — no production deployment config
- No data migration from Supabase (starts empty)
```

- [ ] **Step 2: Commit**

```bash
git add backend/README.md
git commit -m "docs(backend): bootstrap and API reference"
```

---

### Task 15: Swift `TokenStore`

**Files:**
- Create: `frontend/LucidBoard/Services/TokenStore.swift`
- Test: `frontend/LucidBoardTests/TokenStoreTests.swift`

`★ Note ─────────────────────────────────────`
`TokenStore` uses Apple's `Security` framework for Keychain access. Keychain isn't available in unit tests by default — `TokenStoreTests` uses an in-memory variant for assertion. The production `KeychainTokenStore` is exercised only via the smoke test and manual app run.
`─────────────────────────────────────────────`

- [ ] **Step 1: Write failing test `frontend/LucidBoardTests/TokenStoreTests.swift`**

```swift
import XCTest
@testable import LucidBoard

final class TokenStoreTests: XCTestCase {
    func test_storesAndRetrievesToken() {
        let store = InMemoryTokenStore()
        store.save(token: "abc.def.ghi", userId: UUID(uuidString: "00000000-0000-0000-0000-00000000DEAD")!)
        XCTAssertEqual(store.currentToken, "abc.def.ghi")
        XCTAssertEqual(store.currentUserId?.uuidString.lowercased(), "00000000-0000-0000-0000-00000000dead")
    }

    func test_clearEmptiesStorage() {
        let store = InMemoryTokenStore()
        store.save(token: "x", userId: UUID())
        store.clear()
        XCTAssertNil(store.currentToken)
        XCTAssertNil(store.currentUserId)
    }

    func test_isExpiredTrueForExpiredJWT() {
        let store = InMemoryTokenStore()
        // exp = 1 (Jan 1 1970)
        let expiredJWT = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.sig"
        store.save(token: expiredJWT, userId: UUID())
        XCTAssertTrue(store.isCurrentTokenExpired)
    }

    func test_isExpiredFalseForFutureJWT() {
        let store = InMemoryTokenStore()
        // exp = 9999999999 (year 2286)
        let futureJWT = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig"
        store.save(token: futureJWT, userId: UUID())
        XCTAssertFalse(store.isCurrentTokenExpired)
    }
}
```

- [ ] **Step 2: Run test, expect FAIL**

In Xcode: ⌘U (or `xcodebuild test -scheme LucidBoard`). Expected: build fails — `TokenStore`/`InMemoryTokenStore` not defined.

- [ ] **Step 3: Implement `frontend/LucidBoard/Services/TokenStore.swift`**

```swift
import Foundation
import Security

protocol TokenStore: AnyObject {
    var currentToken: String? { get }
    var currentUserId: UUID? { get }
    var isCurrentTokenExpired: Bool { get }
    func save(token: String, userId: UUID)
    func clear()
}

extension TokenStore {
    var isCurrentTokenExpired: Bool {
        guard let token = currentToken else { return true }
        return Self.jwtIsExpired(token)
    }

    static func jwtIsExpired(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return true }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        b64.append(String(repeating: "=", count: (4 - b64.count % 4) % 4))
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return true }
        return Date(timeIntervalSince1970: exp) <= Date()
    }
}

final class InMemoryTokenStore: TokenStore {
    private(set) var currentToken: String?
    private(set) var currentUserId: UUID?

    func save(token: String, userId: UUID) {
        currentToken = token
        currentUserId = userId
    }

    func clear() {
        currentToken = nil
        currentUserId = nil
    }
}

final class KeychainTokenStore: TokenStore {
    private let service = "com.lucidboard.api.token"
    private let tokenAccount = "access_token"
    private let userIdAccount = "user_id"

    var currentToken: String? { read(account: tokenAccount).flatMap { String(data: $0, encoding: .utf8) } }
    var currentUserId: UUID? {
        read(account: userIdAccount)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(UUID.init(uuidString:))
    }

    func save(token: String, userId: UUID) {
        write(account: tokenAccount, value: Data(token.utf8))
        write(account: userIdAccount, value: Data(userId.uuidString.utf8))
    }

    func clear() {
        delete(account: tokenAccount)
        delete(account: userIdAccount)
    }

    // --- Keychain helpers ---

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func write(account: String, value: Data) {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = value
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess ? item as? Data : nil
    }

    private func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**

⌘U in Xcode. Expected: 4 `TokenStoreTests` pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/LucidBoard/Services/TokenStore.swift frontend/LucidBoardTests/TokenStoreTests.swift
git commit -m "feat(swift): TokenStore protocol with Keychain and in-memory impls"
```

---

### Task 16: Swift `AppRepository` protocol + factory

**Files:**
- Create: `frontend/LucidBoard/Services/AppRepository.swift`
- Test: `frontend/LucidBoardTests/AppRepositoryFactoryTests.swift`

- [ ] **Step 1: Write failing test `frontend/LucidBoardTests/AppRepositoryFactoryTests.swift`**

```swift
import XCTest
@testable import LucidBoard

final class AppRepositoryFactoryTests: XCTestCase {
    func test_makeLocalAPIWhenBackendKindIsLocal() {
        let repo = AppRepositoryFactory.make(
            backendKind: "local",
            localAPIBaseURL: "http://127.0.0.1:8000",
            tokenStore: InMemoryTokenStore()
        )
        XCTAssertTrue(repo is LocalAPIRepository)
    }

    func test_makeSupabaseByDefault() {
        let repo = AppRepositoryFactory.make(
            backendKind: "supabase",
            localAPIBaseURL: "http://127.0.0.1:8000",
            tokenStore: InMemoryTokenStore()
        )
        XCTAssertTrue(repo is SupabaseRepository)
    }
}
```

- [ ] **Step 2: Run test, expect FAIL** (types not defined)

- [ ] **Step 3: Implement `frontend/LucidBoard/Services/AppRepository.swift`**

```swift
import Foundation

enum NoteChange {
    case upsert(Note)
    case delete(id: UUID)
}

protocol NoteSubscription {
    func cancel()
}

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

    // Realtime
    func subscribeToNotes(
        boardId: UUID,
        onChange: @escaping (NoteChange) -> Void
    ) -> NoteSubscription
}

final class InertNoteSubscription: NoteSubscription {
    func cancel() {}
}

enum AppRepositoryFactory {
    static func make(
        backendKind: String,
        localAPIBaseURL: String,
        tokenStore: TokenStore
    ) -> AppRepository {
        switch backendKind {
        case "local":
            return LocalAPIRepository(baseURL: localAPIBaseURL, tokenStore: tokenStore)
        default:
            return SupabaseRepository()
        }
    }

    /// Convenience: read xcconfig values from the bundle.
    static func makeFromBundle() -> AppRepository {
        let backendKind = (Bundle.main.object(forInfoDictionaryKey: "BACKEND_KIND") as? String) ?? "supabase"
        let baseURL = (Bundle.main.object(forInfoDictionaryKey: "LOCAL_API_URL") as? String) ?? "http://127.0.0.1:8000"
        return make(backendKind: backendKind, localAPIBaseURL: baseURL, tokenStore: KeychainTokenStore())
    }
}
```

- [ ] **Step 4: Create stub `SupabaseRepository.swift` and `LocalAPIRepository.swift` so the factory compiles**

`frontend/LucidBoard/Services/SupabaseRepository.swift`:
```swift
import Foundation

final class SupabaseRepository: AppRepository {
    func signInAnonymously() async throws { fatalError("Task 17") }
    var isSignedIn: Bool { fatalError("Task 17") }
    func fetchBoards() async throws -> [Board] { fatalError("Task 17") }
    func updateBoard(_ board: Board) async throws { fatalError("Task 17") }
    func fetchNotes(boardId: UUID) async throws -> [Note] { fatalError("Task 17") }
    func upsertNote(_ note: Note) async throws { fatalError("Task 17") }
    func deleteNote(id: UUID) async throws { fatalError("Task 17") }
    func fetchProfile() async throws -> AppSettings? { fatalError("Task 17") }
    func updateProfile(settings: AppSettings) async throws { fatalError("Task 17") }
    func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] { fatalError("Task 17") }
    func subscribeToNotes(boardId: UUID, onChange: @escaping (NoteChange) -> Void) -> NoteSubscription {
        fatalError("Task 17")
    }
}
```

`frontend/LucidBoard/Services/LocalAPIRepository.swift`:
```swift
import Foundation

final class LocalAPIRepository: AppRepository {
    private let baseURL: String
    private let tokenStore: TokenStore

    init(baseURL: String, tokenStore: TokenStore) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
    }

    func signInAnonymously() async throws { fatalError("Task 18") }
    var isSignedIn: Bool { fatalError("Task 18") }
    func fetchBoards() async throws -> [Board] { fatalError("Task 18") }
    func updateBoard(_ board: Board) async throws { fatalError("Task 18") }
    func fetchNotes(boardId: UUID) async throws -> [Note] { fatalError("Task 18") }
    func upsertNote(_ note: Note) async throws { fatalError("Task 18") }
    func deleteNote(id: UUID) async throws { fatalError("Task 18") }
    func fetchProfile() async throws -> AppSettings? { fatalError("Task 18") }
    func updateProfile(settings: AppSettings) async throws { fatalError("Task 18") }
    func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] { fatalError("Task 18") }
    func subscribeToNotes(boardId: UUID, onChange: @escaping (NoteChange) -> Void) -> NoteSubscription {
        InertNoteSubscription()
    }
}
```

- [ ] **Step 5: Run tests, expect PASS** (factory tests; other tests will hit `fatalError` only if invoked — they aren't yet)

- [ ] **Step 6: Commit**

```bash
git add frontend/LucidBoard/Services/AppRepository.swift \
        frontend/LucidBoard/Services/SupabaseRepository.swift \
        frontend/LucidBoard/Services/LocalAPIRepository.swift \
        frontend/LucidBoardTests/AppRepositoryFactoryTests.swift
git commit -m "feat(swift): AppRepository protocol + factory with stubs"
```

---

### Task 17: Swift `SupabaseRepository` (real impl)

**Files:**
- Modify: `frontend/LucidBoard/Services/SupabaseRepository.swift`

`★ Note ─────────────────────────────────────`
This implementation moves the existing logic from `SupabaseService.swift` and `BoardViewModel.subscribeToRealtime()` behind the protocol. `SupabaseService.swift` stays as-is (it's the underlying client); the new `SupabaseRepository` is a thin adapter. We add Realtime support to the adapter — which `BoardViewModel` no longer manages directly after Task 19.
`─────────────────────────────────────────────`

- [ ] **Step 1: Replace `frontend/LucidBoard/Services/SupabaseRepository.swift`**

```swift
import Foundation
import Supabase
import Realtime

private struct NoteIDRecord: Decodable { let id: UUID }

final class SupabaseRepository: AppRepository {
    private let service = SupabaseService.shared

    func signInAnonymously() async throws { try await service.signInAnonymously() }

    var isSignedIn: Bool {
        (try? service.client.auth.currentUser) != nil
    }

    func fetchBoards() async throws -> [Board] {
        try await service.fetchBoards()
    }

    func updateBoard(_ board: Board) async throws {
        try await service.updateBoard(board)
    }

    func fetchNotes(boardId: UUID) async throws -> [Note] {
        try await service.fetchNotes(boardId: boardId)
    }

    func upsertNote(_ note: Note) async throws {
        try await service.upsertNote(note)
    }

    func deleteNote(id: UUID) async throws {
        try await service.deleteNote(id: id)
    }

    func fetchProfile() async throws -> AppSettings? {
        try await service.fetchProfile()
    }

    func updateProfile(settings: AppSettings) async throws {
        try await service.updateProfile(settings: settings)
    }

    func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] {
        try await service.autoOrganize(boardId: boardId)
    }

    func subscribeToNotes(
        boardId: UUID,
        onChange: @escaping (NoteChange) -> Void
    ) -> NoteSubscription {
        let token = SupabaseSubscription()
        Task {
            do {
                let client = try service.client
                let channel = client.channel("notes_board_\(boardId.uuidString)")
                token.channel = channel
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "notes",
                    filter: "board_id=eq.\(boardId.uuidString)"
                )
                await channel.subscribe()
                for await change in changes {
                    switch change {
                    case .insert(let action):
                        if let note: Note = try? action.record.decode() { onChange(.upsert(note)) }
                    case .update(let action):
                        if let note: Note = try? action.record.decode() { onChange(.upsert(note)) }
                    case .delete(let action):
                        if let r: NoteIDRecord = try? action.oldRecord.decode() {
                            onChange(.delete(id: r.id))
                        }
                    default: break
                    }
                }
            } catch {
                print("Realtime subscribe failed: \(error)")
            }
        }
        return token
    }
}

private final class SupabaseSubscription: NoteSubscription {
    weak var channel: RealtimeChannel?
    func cancel() {
        guard let channel else { return }
        Task { await channel.unsubscribe() }
    }
}
```

- [ ] **Step 2: Build the project**

```bash
xcodebuild -scheme LucidBoard -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add frontend/LucidBoard/Services/SupabaseRepository.swift
git commit -m "feat(swift): SupabaseRepository wraps existing service + Realtime"
```

---

### Task 18: Swift `LocalAPIRepository` (real impl)

**Files:**
- Modify: `frontend/LucidBoard/Services/LocalAPIRepository.swift`
- Test: `frontend/LucidBoardTests/LocalAPIRepositoryTests.swift`

- [ ] **Step 1: Write failing test `frontend/LucidBoardTests/LocalAPIRepositoryTests.swift`**

```swift
import XCTest
@testable import LucidBoard

final class LocalAPIRepositoryTests: XCTestCase {
    var session: URLSession!
    var repo: LocalAPIRepository!
    var tokenStore: InMemoryTokenStore!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        tokenStore = InMemoryTokenStore()
        repo = LocalAPIRepository(
            baseURL: "http://test.invalid",
            tokenStore: tokenStore,
            session: session
        )
        MockURLProtocol.reset()
    }

    func test_signInAnonymously_postsToSignupAndStoresToken() async throws {
        MockURLProtocol.responder = { req in
            XCTAssertEqual(req.url?.path, "/auth/v1/signup")
            XCTAssertEqual(req.url?.query, "anonymous=true")
            let userId = "11111111-1111-1111-1111-111111111111"
            let body = """
            {"access_token":"eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig",
             "token_type":"bearer","expires_in":3600,
             "user":{"id":"\(userId)","is_anonymous":true}}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        try await repo.signInAnonymously()
        XCTAssertEqual(tokenStore.currentToken?.prefix(3), "eyJ")
        XCTAssertEqual(tokenStore.currentUserId?.uuidString.lowercased(),
                       "11111111-1111-1111-1111-111111111111")
    }

    func test_fetchBoards_attachesBearerHeader() async throws {
        tokenStore.save(
            token: "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig",
            userId: UUID()
        )
        MockURLProtocol.responder = { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"),
                           "Bearer eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        let boards = try await repo.fetchBoards()
        XCTAssertEqual(boards.count, 0)
    }

    func test_401_triggersResignAndRetry() async throws {
        tokenStore.save(
            token: "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig",
            userId: UUID()
        )
        var callCount = 0
        MockURLProtocol.responder = { req in
            callCount += 1
            if req.url?.path == "/auth/v1/signup" {
                let body = """
                {"access_token":"eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig",
                 "token_type":"bearer","expires_in":3600,
                 "user":{"id":"22222222-2222-2222-2222-222222222222","is_anonymous":true}}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            // First boards call: 401. After signup, retry returns 200.
            if callCount < 3 {
                return (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        let _ = try await repo.fetchBoards()
        XCTAssertGreaterThanOrEqual(callCount, 3)
    }

    func test_localAPI_subscribeToNotes_returnsInert() {
        var called = false
        let sub = repo.subscribeToNotes(boardId: UUID()) { _ in called = true }
        sub.cancel()
        XCTAssertFalse(called)
    }
}

// MARK: - URL Protocol mock

final class MockURLProtocol: URLProtocol {
    static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func reset() { responder = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "no responder", code: 0))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

- [ ] **Step 2: Run tests, expect FAIL** (LocalAPIRepository init has different signature, methods unimplemented).

- [ ] **Step 3: Replace `frontend/LucidBoard/Services/LocalAPIRepository.swift`**

```swift
import Foundation

enum LocalAPIError: Error {
    case unauthorized
    case notFound
    case validation(String)
    case network(URLError)
    case server(status: Int, code: String?)
    case decoding(Error)
}

private struct AuthResponse: Decodable {
    let access_token: String
    let user: User
    struct User: Decodable { let id: UUID; let is_anonymous: Bool }
}

private struct ErrorBody: Decodable {
    let detail: String?
    let code: String?
}

final class LocalAPIRepository: AppRepository {
    private let baseURL: URL
    private let tokenStore: TokenStore
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: String, tokenStore: TokenStore, session: URLSession = .shared) {
        guard let url = URL(string: baseURL) else { fatalError("Invalid LOCAL_API_URL: \(baseURL)") }
        self.baseURL = url
        self.tokenStore = tokenStore
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: Auth

    func signInAnonymously() async throws {
        var req = URLRequest(url: baseURL.appending(path: "auth/v1/signup").appending(queryItems: [.init(name: "anonymous", value: "true")]))
        req.httpMethod = "POST"
        let (data, response) = try await session.data(for: req)
        try Self.assertOK(response, data: data)
        let body = try decoder.decode(AuthResponse.self, from: data)
        tokenStore.save(token: body.access_token, userId: body.user.id)
    }

    var isSignedIn: Bool {
        guard let _ = tokenStore.currentToken else { return false }
        return !tokenStore.isCurrentTokenExpired
    }

    // MARK: Boards

    func fetchBoards() async throws -> [Board] {
        try await get("api/boards", as: [Board].self)
    }

    func updateBoard(_ board: Board) async throws {
        struct Body: Encodable {
            let title: String
            let background_color: String
            let background_layout: String
        }
        let body = Body(title: board.title,
                        background_color: board.backgroundColor,
                        background_layout: board.backgroundLayout.rawValue)
        let _: Board = try await send("api/boards/\(board.id)", method: "PATCH", body: body)
    }

    // MARK: Notes

    func fetchNotes(boardId: UUID) async throws -> [Note] {
        try await get("api/boards/\(boardId)/notes", as: [Note].self)
    }

    func upsertNote(_ note: Note) async throws {
        struct Body: Encodable {
            let board_id: UUID
            let content_text: String?
            let content_drawing: String?
            let color: String
            let pos_x: Float
            let pos_y: Float
            let z_index: Int
            let template: String
            let checklist_items: [ChecklistItem]
        }
        let body = Body(
            board_id: note.boardId,
            content_text: note.contentText,
            content_drawing: note.contentDrawing?.base64EncodedString(),
            color: note.color,
            pos_x: note.posX,
            pos_y: note.posY,
            z_index: note.zIndex,
            template: note.template.rawValue,
            checklist_items: note.checklistItems ?? []
        )
        let _: Note = try await send("api/notes/\(note.id)", method: "PUT", body: body)
    }

    func deleteNote(id: UUID) async throws {
        try await sendVoid("api/notes/\(id)", method: "DELETE")
    }

    // MARK: Profile

    func fetchProfile() async throws -> AppSettings? {
        struct Wrapper: Decodable { let settings: AppSettings }
        do {
            let wrapper: Wrapper = try await get("api/profile", as: Wrapper.self)
            return wrapper.settings
        } catch LocalAPIError.notFound {
            return nil
        }
    }

    func updateProfile(settings: AppSettings) async throws {
        struct Body: Encodable { let settings: AppSettings }
        let _: AnyEmpty = try await send("api/profile", method: "PUT", body: Body(settings: settings))
    }

    // MARK: AI

    func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] {
        struct Body: Encodable { let board_uuid: UUID }
        struct Row: Decodable { let id: UUID; let new_x: Float; let new_y: Float }
        let rows: [Row] = try await send("api/rpc/match_notes", method: "POST", body: Body(board_uuid: boardId))
        var out: [UUID: (Float, Float)] = [:]
        for row in rows { out[row.id] = (row.new_x, row.new_y) }
        return out
    }

    // MARK: Realtime (inert)

    func subscribeToNotes(
        boardId: UUID,
        onChange: @escaping (NoteChange) -> Void
    ) -> NoteSubscription {
        InertNoteSubscription()
    }

    // MARK: - Plumbing

    private struct AnyEmpty: Decodable {}

    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        try await request(path, method: "GET", body: Optional<AnyEmpty>.none)
    }

    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T {
        try await request(path, method: method, body: body)
    }

    private func sendVoid(_ path: String, method: String) async throws {
        let _: AnyEmpty = try await request(path, method: method, body: Optional<AnyEmpty>.none)
    }

    private func request<T: Decodable, B: Encodable>(_ path: String, method: String, body: B?) async throws -> T {
        let (data, response) = try await perform(path: path, method: method, body: body)
        try Self.assertOK(response, data: data)
        if T.self == AnyEmpty.self { return AnyEmpty() as! T }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw LocalAPIError.decoding(error) }
    }

    private func perform<B: Encodable>(path: String, method: String, body: B?) async throws -> (Data, URLResponse) {
        let url = baseURL.appending(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token = tokenStore.currentToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 401, !path.hasPrefix("auth/") {
                try await signInAnonymously()
                if let token = tokenStore.currentToken {
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                return try await session.data(for: req)
            }
            return (data, response)
        } catch let urlError as URLError {
            throw LocalAPIError.network(urlError)
        }
    }

    private static func assertOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LocalAPIError.server(status: -1, code: nil)
        }
        switch http.statusCode {
        case 200...299: return
        case 401: throw LocalAPIError.unauthorized
        case 404: throw LocalAPIError.notFound
        case 422:
            let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw LocalAPIError.validation(err?.detail ?? "Validation failed")
        default:
            let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw LocalAPIError.server(status: http.statusCode, code: err?.code)
        }
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**

⌘U. Expected: 4 `LocalAPIRepositoryTests` pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/LucidBoard/Services/LocalAPIRepository.swift frontend/LucidBoardTests/LocalAPIRepositoryTests.swift
git commit -m "feat(swift): LocalAPIRepository with retry-on-401 + inert subscription"
```

---

### Task 19: Wire `AppRepository` into the app

**Files:**
- Modify: `frontend/LucidBoard/LucidBoardApp.swift`
- Modify: `frontend/LucidBoard/ViewModels/BoardViewModel.swift`
- Modify: `frontend/LucidBoard/ViewModels/NoteViewModel.swift`
- Modify: `frontend/LucidBoard/Services/SettingsManager.swift`

`★ Note ─────────────────────────────────────`
This is the largest refactor in the plan. We're replacing every `SupabaseService.shared` reference and removing the direct Realtime usage from `BoardViewModel`. The replacement keeps all method signatures identical; only the call site changes.
`─────────────────────────────────────────────`

- [ ] **Step 1: Replace `frontend/LucidBoard/LucidBoardApp.swift`**

```swift
import SwiftUI

private struct AppRepositoryKey: EnvironmentKey {
    static let defaultValue: AppRepository = SupabaseRepository()
}

extension EnvironmentValues {
    var appRepository: AppRepository {
        get { self[AppRepositoryKey.self] }
        set { self[AppRepositoryKey.self] = newValue }
    }
}

@main
struct LucidBoardApp: App {
    private let appRepository: AppRepository
    @StateObject private var settingsManager: SettingsManager
    @StateObject private var boardVM: BoardViewModel

    init() {
        let repo = AppRepositoryFactory.makeFromBundle()
        self.appRepository = repo
        let initialBoard = Board(
            id: UUID(),
            userId: UUID(),
            title: "My First Board",
            backgroundColor: "#FFFFFF",
            backgroundLayout: .grid,
            createdAt: Date(),
            updatedAt: Date()
        )
        _settingsManager = StateObject(wrappedValue: SettingsManager(repository: repo))
        _boardVM = StateObject(wrappedValue: BoardViewModel(board: initialBoard, repository: repo))

        Task { try? await repo.signInAnonymously() }
    }

    var body: some Scene {
        WindowGroup {
            BoardView(viewModel: boardVM)
                .environment(\.appRepository, appRepository)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch settingsManager.settings.preferredColorScheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}
```

- [ ] **Step 2: Replace `frontend/LucidBoard/ViewModels/BoardViewModel.swift`**

```swift
import SwiftUI
import Combine

class BoardViewModel: ObservableObject {
    @Published var board: Board
    @Published var noteViewModels: [UUID: NoteViewModel] = [:]

    @Published var offset: CGSize = .zero
    @Published var scale: CGFloat = 1.0
    @Published var isOrganizing: Bool = false

    var lastOffset: CGSize = .zero
    var lastScale: CGFloat = 1.0

    private var lastLocalUpdates: [UUID: Date] = [:]
    private let broadcastBuffer: TimeInterval = 2.0

    private let repository: AppRepository
    private var subscription: NoteSubscription?

    init(board: Board, repository: AppRepository) {
        self.board = board
        self.repository = repository

        Task {
            await fetchNotes()
            await MainActor.run { self.subscribe() }
        }
    }

    deinit { subscription?.cancel() }

    @MainActor
    func fetchNotes() async {
        do {
            let notes = try await repository.fetchNotes(boardId: board.id)
            for note in notes { createViewModel(for: note) }
        } catch {
            print("Error fetching notes: \(error)")
        }
    }

    private func createViewModel(for note: Note) {
        let vm = NoteViewModel(note: note, repository: repository)
        vm.onLocalUpdate = { [weak self] id in self?.lastLocalUpdates[id] = Date() }
        noteViewModels[note.id] = vm
    }

    @MainActor
    private func subscribe() {
        subscription = repository.subscribeToNotes(boardId: board.id) { [weak self] change in
            Task { @MainActor in self?.handleChange(change) }
        }
    }

    @MainActor
    private func handleChange(_ change: NoteChange) {
        switch change {
        case .upsert(let note): updateOrAddNote(note)
        case .delete(let id): noteViewModels.removeValue(forKey: id)
        }
    }

    private func updateOrAddNote(_ note: Note) {
        if let lastLocal = lastLocalUpdates[note.id], Date().timeIntervalSince(lastLocal) < broadcastBuffer {
            return
        }
        if let existingVM = noteViewModels[note.id] {
            guard !existingVM.isDragging else { return }
            if note.updatedAt > existingVM.note.updatedAt {
                withAnimation(.spring()) { existingVM.note = note }
            }
        } else {
            createViewModel(for: note)
        }
    }

    func updateBackgroundColor(_ color: String) {
        board.backgroundColor = color
        board.updatedAt = Date()
        syncBoard()
    }

    func updateBackgroundLayout(_ layout: BackgroundLayout) {
        board.backgroundLayout = layout
        board.updatedAt = Date()
        syncBoard()
    }

    private func syncBoard() {
        Task { try? await repository.updateBoard(board) }
    }

    @MainActor
    func triggerAutoOrganize() async {
        guard !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }
        do {
            let newPositions = try await repository.autoOrganize(boardId: board.id)
            for (id, pos) in newPositions {
                if let noteVM = noteViewModels[id] {
                    lastLocalUpdates[id] = Date()
                    withAnimation(.spring(response: 1.0, dampingFraction: 0.7)) {
                        noteVM.note.posX = pos.0
                        noteVM.note.posY = pos.1
                    }
                    noteVM.syncNote()
                }
            }
        } catch {
            print("Error auto-organizing: \(error)")
        }
    }

    @MainActor
    func deleteNote(id: UUID) {
        noteViewModels.removeValue(forKey: id)
        Task { try? await repository.deleteNote(id: id) }
    }

    @MainActor
    func bringToFront(id: UUID) {
        guard let vm = noteViewModels[id] else { return }
        let maxZ = noteViewModels.values.map { $0.note.zIndex }.max() ?? 0
        guard vm.note.zIndex < maxZ else { return }
        vm.note.zIndex = maxZ + 1
        lastLocalUpdates[id] = Date()
        vm.syncNote()
    }

    func addNote(at point: CGPoint) {
        let settings = SettingsManager.shared.settings
        let newNote = Note(
            id: UUID(),
            boardId: board.id,
            userId: board.userId,
            contentText: "",
            contentDrawing: nil,
            color: settings.defaultNoteColor,
            posX: Float(point.x),
            posY: Float(point.y),
            zIndex: (noteViewModels.values.map { $0.note.zIndex }.max() ?? 0) + 1,
            template: settings.defaultNoteTemplate,
            checklistItems: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        lastLocalUpdates[newNote.id] = Date()
        createViewModel(for: newNote)
        Task { try? await repository.upsertNote(newNote) }
    }

    func handlePanGesture(_ translation: CGSize) {
        offset = CGSize(width: lastOffset.width + translation.width,
                        height: lastOffset.height + translation.height)
    }
    func finalizePanGesture() { lastOffset = offset }
    func handleZoomGesture(_ magnification: CGFloat) { scale = lastScale * magnification }
    func finalizeZoomGesture() { lastScale = scale }
}
```

- [ ] **Step 3: Replace `frontend/LucidBoard/ViewModels/NoteViewModel.swift`**

```swift
import SwiftUI
import Combine
import PencilKit

class NoteViewModel: ObservableObject, Identifiable {
    @Published var note: Note
    @Published var isDragging: Bool = false
    @Published var drawing: PKDrawing = PKDrawing()

    var onLocalUpdate: ((UUID) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private let repository: AppRepository

    init(note: Note, repository: AppRepository) {
        self.note = note
        self.repository = repository

        if let drawingData = note.contentDrawing {
            do { self.drawing = try PKDrawing(data: drawingData) }
            catch { print("Error deserializing drawing: \(error)") }
        }

        $drawing
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] newDrawing in
                guard let self else { return }
                self.note.contentDrawing = newDrawing.dataRepresentation()
                self.syncNote()
            }
            .store(in: &cancellables)
    }

    func syncNote() {
        self.note.updatedAt = Date()
        onLocalUpdate?(note.id)
        Task { try? await repository.upsertNote(self.note) }
    }

    var id: UUID { note.id }

    func updatePosition(to point: CGPoint) {
        note.posX = Float(point.x)
        note.posY = Float(point.y)
        onLocalUpdate?(note.id)
    }

    func finalizePosition() { syncNote() }

    func updateTemplate(_ template: NoteTemplate) {
        note.template = template
        if template == .checklist && (note.checklistItems == nil || note.checklistItems?.isEmpty == true) {
            note.checklistItems = [ChecklistItem()]
        }
        syncNote()
    }

    func addChecklistItem() {
        if note.checklistItems == nil { note.checklistItems = [] }
        note.checklistItems?.append(ChecklistItem())
        syncNote()
    }

    func toggleChecklistItem(id: UUID) {
        if let index = note.checklistItems?.firstIndex(where: { $0.id == id }) {
            note.checklistItems?[index].isCompleted.toggle()
            syncNote()
        }
    }

    func updateChecklistItemText(id: UUID, text: String) {
        if let index = note.checklistItems?.firstIndex(where: { $0.id == id }) {
            note.checklistItems?[index].text = text
            syncNote()
        }
    }

    func deleteChecklistItem(id: UUID) {
        note.checklistItems?.removeAll(where: { $0.id == id })
        syncNote()
    }
}
```

- [ ] **Step 4: Replace `frontend/LucidBoard/Services/SettingsManager.swift`**

```swift
import Foundation
import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager(repository: AppRepositoryFactory.makeFromBundle())

    @AppStorage("app_settings") private var settingsData: Data = Data()

    @Published var settings: AppSettings {
        didSet {
            save()
            if settings.isSyncEnabled { syncSubject.send(settings) }
        }
    }

    private let repository: AppRepository
    private let syncSubject = PassthroughSubject<AppSettings, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(repository: AppRepository) {
        self.repository = repository
        let data = UserDefaults.standard.data(forKey: "app_settings") ?? Data()
        if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
        setupSync()
        Task { await fetchRemoteSettings() }
    }

    private func setupSync() {
        syncSubject
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] settings in
                guard let self else { return }
                Task { try? await self.repository.updateProfile(settings: settings) }
            }
            .store(in: &cancellables)
    }

    private func fetchRemoteSettings() async {
        guard settings.isSyncEnabled else { return }
        do {
            if let remoteSettings = try await repository.fetchProfile() {
                await MainActor.run { self.settings = remoteSettings }
            }
        } catch {
            print("Settings sync: \(error.localizedDescription)")
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) { settingsData = encoded }
    }
}
```

- [ ] **Step 5: Build the project**

```bash
xcodebuild -scheme LucidBoard -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 6: Run all Swift tests**

```bash
xcodebuild -scheme LucidBoard -destination 'platform=macOS' test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add frontend/LucidBoard/LucidBoardApp.swift \
        frontend/LucidBoard/ViewModels/BoardViewModel.swift \
        frontend/LucidBoard/ViewModels/NoteViewModel.swift \
        frontend/LucidBoard/Services/SettingsManager.swift
git commit -m "refactor(swift): inject AppRepository, drop direct SupabaseService usage"
```

---

### Task 20: xcconfig keys + final wiring

**Files:**
- Modify: `frontend/LucidBoard/Sample.xcconfig`
- Modify: `frontend/LucidBoard/Config.xcconfig` (only if exists locally)
- Modify: `frontend/LucidBoard/Info.plist` (add new keys so `Bundle.main.object(forInfoDictionaryKey:)` returns them)

`★ Note ─────────────────────────────────────`
xcconfig values reach runtime via `Info.plist` substitution (the standard `$(BACKEND_KIND)` pattern). The Info.plist file in this Xcode project is generated — check the project's "Info" tab in Xcode for where to add the entries, or edit `LucidBoard.xcodeproj/project.pbxproj` to add `INFOPLIST_KEY_BACKEND_KIND` and `INFOPLIST_KEY_LOCAL_API_URL` to the target's build settings.
`─────────────────────────────────────────────`

- [ ] **Step 1: Replace `frontend/LucidBoard/Sample.xcconfig`**

```
// Get these from your Supabase Project Settings > API
SUPABASE_URL = https://your-project-id.supabase.co
SUPABASE_KEY = your-anon-public-key

// Local-dev backend (Django Ninja). Set BACKEND_KIND=local to use it.
// Default is 'supabase' so a fresh clone behaves like before.
BACKEND_KIND = supabase
LOCAL_API_URL = http://127.0.0.1:8000
```

- [ ] **Step 2: If `Config.xcconfig` exists locally, add the same two keys**

This file is developer-local and not committed (or is gitignored). Manually add:
```
BACKEND_KIND = local
LOCAL_API_URL = http://127.0.0.1:8000
```

- [ ] **Step 3: Add Info.plist entries**

In Xcode, open the LucidBoard target's Info tab. Add two custom entries:

| Key | Type | Value |
|---|---|---|
| `BACKEND_KIND` | String | `$(BACKEND_KIND)` |
| `LOCAL_API_URL` | String | `$(LOCAL_API_URL)` |

If editing `project.pbxproj` directly, add to the target's `INFOPLIST_KEY_*` block:
```
INFOPLIST_KEY_BACKEND_KIND = "$(BACKEND_KIND)";
INFOPLIST_KEY_LOCAL_API_URL = "$(LOCAL_API_URL)";
```

- [ ] **Step 4: End-to-end manual verification**

```bash
# Terminal 1
cd backend
docker compose up -d
uv run manage.py migrate
uv run manage.py runserver
```

In Xcode:
- Set `BACKEND_KIND = local` in `Config.xcconfig`
- Build and run on macOS
- App launches, creates an anonymous user, calls `/api/boards`, renders the default board
- Add a note; it persists across app restart
- Trigger Auto-Organize; notes reposition

Switch `BACKEND_KIND = supabase` in `Config.xcconfig`, build, and verify the Supabase path still works.

- [ ] **Step 5: Final commit**

```bash
git add frontend/LucidBoard/Sample.xcconfig \
        LucidBoard.xcodeproj/project.pbxproj
git commit -m "feat(swift): xcconfig keys to switch between Supabase and local API"
```

---

## Post-Implementation Checklist

- [ ] Backend: `uv run pytest -v` — all green
- [ ] Backend: `./scripts/smoke.sh` — ends with `==> SMOKE OK`
- [ ] Swift: `xcodebuild test` — all green
- [ ] Manual: app launches with `BACKEND_KIND=local`, creates/edits/clusters notes
- [ ] Manual: app launches with `BACKEND_KIND=supabase`, still works against Supabase (Realtime included)
- [ ] Spec acceptance criteria in `docs/superpowers/specs/2026-05-21-supabase-to-django-ninja-local-dev-design.md` §11 are satisfied
