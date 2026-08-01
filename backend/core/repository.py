from __future__ import annotations

import uuid
from datetime import datetime, timezone

from core.firestore_client import get_client
from core.models import Board, Profile, User

USERS = "users"
PROFILES = "profiles"
BOARDS = "boards"


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


# --- Boards ---

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
