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
