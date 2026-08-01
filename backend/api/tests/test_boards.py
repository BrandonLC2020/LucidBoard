from core.repository import create_anonymous_user, create_board, get_board


def test_list_boards_returns_only_users_boards(auth_client):
    create_board(auth_client.user.id, title="Mine")
    other_user = create_anonymous_user()
    create_board(other_user.id, title="Theirs")
    res = auth_client.get("/api/boards")
    assert res.status_code == 200
    titles = [b["title"] for b in res.json()]
    assert "Mine" in titles
    assert "Theirs" not in titles


def test_list_boards_requires_auth(client):
    res = client.get("/api/boards")
    assert res.status_code == 401


def test_update_board(auth_client):
    board = create_board(auth_client.user.id, title="Old")
    res = auth_client.patch(
        f"/api/boards/{board.id}",
        data={"title": "New", "background_color": "#000"},
        content_type="application/json",
    )
    assert res.status_code == 200
    updated = get_board(board.id)
    assert updated.title == "New"
    assert updated.background_color == "#000"


def test_update_other_users_board_returns_404(auth_client):
    other_user = create_anonymous_user()
    other = create_board(other_user.id, title="Theirs")
    res = auth_client.patch(
        f"/api/boards/{other.id}",
        data={"title": "Hacked"},
        content_type="application/json",
    )
    assert res.status_code == 404
