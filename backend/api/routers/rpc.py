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
