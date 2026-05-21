import uuid
from unittest.mock import patch

import pytest

from core.models import Board, Note, User

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


def _make_other_board():
    other_user = User.objects.create_anonymous()
    return Board.objects.create(user=other_user, title="theirs")


def test_list_notes_for_board(auth_client, board):
    Note.objects.create(
        board=board, user=auth_client.user, color="#fff", pos_x=0, pos_y=0, z_index=0
    )
    res = auth_client.get(f"/api/boards/{board.id}/notes")
    assert res.status_code == 200
    assert len(res.json()) == 1


def test_list_notes_for_other_users_board_returns_404(auth_client):
    other_board = _make_other_board()
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
    other_board = _make_other_board()
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
    other_board = _make_other_board()
    note = Note.objects.create(
        board=other_board, user=other_board.user,
        color="#fff", pos_x=0, pos_y=0, z_index=0
    )
    res = auth_client.delete(f"/api/notes/{note.id}")
    assert res.status_code == 404
