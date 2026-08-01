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
