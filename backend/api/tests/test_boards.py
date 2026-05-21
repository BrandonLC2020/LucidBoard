import pytest

from core.models import Board, User

pytestmark = pytest.mark.django_db


def test_list_boards_returns_only_users_boards(auth_client):
    Board.objects.create(user=auth_client.user, title="Mine")
    other_user = User.objects.create_anonymous()
    Board.objects.create(user=other_user, title="Theirs")
    res = auth_client.get("/api/boards")
    assert res.status_code == 200
    titles = [b["title"] for b in res.json()]
    assert "Mine" in titles
    assert "Theirs" not in titles


def test_list_boards_requires_auth(client):
    res = client.get("/api/boards")
    assert res.status_code == 401


def test_update_board(auth_client):
    board = Board.objects.create(user=auth_client.user, title="Old")
    res = auth_client.patch(
        f"/api/boards/{board.id}",
        data={"title": "New", "background_color": "#000"},
        content_type="application/json",
    )
    assert res.status_code == 200
    board.refresh_from_db()
    assert board.title == "New"
    assert board.background_color == "#000"


def test_update_other_users_board_returns_404(auth_client):
    other_user = User.objects.create_anonymous()
    other = Board.objects.create(user=other_user, title="Theirs")
    res = auth_client.patch(
        f"/api/boards/{other.id}",
        data={"title": "Hacked"},
        content_type="application/json",
    )
    assert res.status_code == 404
