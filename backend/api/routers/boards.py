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
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(board, field, value)
    board.save()
    return board
