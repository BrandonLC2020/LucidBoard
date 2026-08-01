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
