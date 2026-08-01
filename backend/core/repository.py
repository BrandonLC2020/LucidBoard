from __future__ import annotations

import uuid
from datetime import datetime, timezone

from core.firestore_client import get_client
from core.models import Board, Note, Profile, User

USERS = "users"
PROFILES = "profiles"
BOARDS = "boards"
NOTES = "notes"


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


# --- Notes ---

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
