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
