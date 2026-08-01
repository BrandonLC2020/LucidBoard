import uuid
from unittest.mock import patch

from core.repository import create_anonymous_user, create_board, get_note


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
    other_user = create_anonymous_user()
    return create_board(other_user.id, title="theirs")


def test_list_notes_for_board(auth_client):
    board = create_board(auth_client.user.id, title="b")
    with patch("api.routers.notes.generate_embedding", return_value=None):
        auth_client.put(
            f"/api/notes/{uuid.uuid4()}",
            data=_note_payload(board.id),
            content_type="application/json",
        )
    res = auth_client.get(f"/api/boards/{board.id}/notes")
    assert res.status_code == 200
    assert len(res.json()) == 1


def test_list_notes_for_other_users_board_returns_404(auth_client):
    other_board = _make_other_board()
    res = auth_client.get(f"/api/boards/{other_board.id}/notes")
    assert res.status_code == 404


def test_upsert_creates_note_and_calls_embedding(auth_client):
    board = create_board(auth_client.user.id, title="b")
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
    note = get_note(note_id)
    assert note.embedding == fake_vector


def test_upsert_with_nonempty_checklist_items_round_trips(auth_client):
    board = create_board(auth_client.user.id, title="b")
    note_id = uuid.uuid4()
    item_id = uuid.uuid4()
    checklist_items = [{"id": str(item_id), "text": "buy milk", "is_completed": False}]
    with patch("api.routers.notes.generate_embedding", return_value=None):
        res = auth_client.put(
            f"/api/notes/{note_id}",
            data=_note_payload(board.id, checklist_items=checklist_items),
            content_type="application/json",
        )
    assert res.status_code == 200
    body = res.json()
    assert len(body["checklist_items"]) == 1
    returned_item = body["checklist_items"][0]
    assert returned_item["id"] == str(item_id)
    assert returned_item["text"] == "buy milk"
    assert returned_item["is_completed"] is False

    note = get_note(note_id)
    assert len(note.checklist_items) == 1
    assert note.checklist_items[0]["id"] == str(item_id)
    assert note.checklist_items[0]["text"] == "buy milk"
    assert note.checklist_items[0]["is_completed"] is False


def test_upsert_skips_embedding_when_content_unchanged(auth_client):
    board = create_board(auth_client.user.id, title="b")
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
    note = get_note(note_id)
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


def test_delete_note(auth_client):
    board = create_board(auth_client.user.id, title="b")
    note_id = uuid.uuid4()
    with patch("api.routers.notes.generate_embedding", return_value=None):
        auth_client.put(
            f"/api/notes/{note_id}",
            data=_note_payload(board.id),
            content_type="application/json",
        )
    res = auth_client.delete(f"/api/notes/{note_id}")
    assert res.status_code == 204
    assert get_note(note_id) is None


def test_delete_other_users_note_returns_404(auth_client):
    other_board = _make_other_board()
    other_note_id = uuid.uuid4()
    with patch("api.routers.notes.generate_embedding", return_value=None):
        # PUT as the other user directly via the repository (bypassing auth)
        # to seed a note that belongs to someone else.
        from core.repository import upsert_note
        upsert_note(
            other_note_id,
            board_id=other_board.id,
            user_id=other_board.user_id,
            content_text=None,
            content_drawing=None,
            color="#fff",
            pos_x=0,
            pos_y=0,
            z_index=0,
            template="plain",
            checklist_items=[],
            embedding=None,
        )
    res = auth_client.delete(f"/api/notes/{other_note_id}")
    assert res.status_code == 404
