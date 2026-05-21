import uuid

import pytest

from core.models import Board, Note, User

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
    other_user = User.objects.create_anonymous()
    other_board = Board.objects.create(user=other_user, title="theirs")
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
