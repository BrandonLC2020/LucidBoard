import uuid

from core.matching import match_notes
from core.models import Note
from core.repository import create_anonymous_user, create_board, upsert_note


def _fake_embedding(seed: float) -> list[float]:
    return [seed] * 768


def _make_note(board_id, user_id, *, content_text, embedding, z_index=0) -> Note:
    note_id = uuid.uuid4()
    return upsert_note(
        note_id,
        board_id=board_id,
        user_id=user_id,
        content_text=content_text,
        content_drawing=None,
        color="#fff",
        pos_x=0,
        pos_y=0,
        z_index=z_index,
        template="plain",
        checklist_items=[],
        embedding=embedding,
    )


def test_match_notes_returns_positions(auth_client):
    board = create_board(auth_client.user.id, title="b")
    n1 = _make_note(board.id, auth_client.user.id, content_text="cat", embedding=_fake_embedding(0.1))
    n2 = _make_note(board.id, auth_client.user.id, content_text="kitten", embedding=_fake_embedding(0.1), z_index=1)
    n3 = _make_note(board.id, auth_client.user.id, content_text="rocket", embedding=_fake_embedding(0.9), z_index=2)
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
    other_user = create_anonymous_user()
    other_board = create_board(other_user.id, title="theirs")
    res = auth_client.post(
        "/api/rpc/match_notes",
        data={"board_uuid": str(other_board.id)},
        content_type="application/json",
    )
    assert res.status_code == 404


def test_match_notes_returns_empty_for_board_with_no_notes(auth_client):
    board = create_board(auth_client.user.id, title="b")
    res = auth_client.post(
        "/api/rpc/match_notes",
        data={"board_uuid": str(board.id)},
        content_type="application/json",
    )
    assert res.status_code == 200
    assert res.json() == []


def test_match_notes_pure_function_clusters_similar_notes_together():
    board_id = uuid.uuid4()
    user_id = uuid.uuid4()
    # NOTE: _fake_embedding(seed) = [seed] * 768 always points in the same
    # direction regardless of seed, so any two such vectors are parallel and
    # have cosine distance exactly 0 (cosine distance, like pgvector's `<=>`,
    # is scale-invariant). To actually exercise "dissimilar -> different
    # cluster", n3 needs a non-parallel vector, so it uses an alternating
    # +/- pattern (orthogonal to the uniform direction) instead of
    # _fake_embedding.
    n1 = Note(id=uuid.uuid4(), board_id=board_id, user_id=user_id, color="#fff",
               pos_x=0, pos_y=0, z_index=0, embedding=_fake_embedding(0.1))
    n2 = Note(id=uuid.uuid4(), board_id=board_id, user_id=user_id, color="#fff",
               pos_x=0, pos_y=0, z_index=1, embedding=_fake_embedding(0.1))
    n3 = Note(id=uuid.uuid4(), board_id=board_id, user_id=user_id, color="#fff",
               pos_x=0, pos_y=0, z_index=2,
               embedding=[0.9 if i % 2 == 0 else -0.9 for i in range(768)])
    positions = match_notes([n1, n2, n3])
    by_id = {p.id: p for p in positions}
    # n1 and n2 are identical embeddings (distance 0) -> same cluster -> same x.
    assert by_id[n1.id].new_x == by_id[n2.id].new_x
    # n3 is far from both -> different cluster -> different x.
    assert by_id[n3.id].new_x != by_id[n1.id].new_x


def test_match_notes_pure_function_handles_no_embeddings():
    board_id = uuid.uuid4()
    user_id = uuid.uuid4()
    n1 = Note(id=uuid.uuid4(), board_id=board_id, user_id=user_id, color="#fff",
               pos_x=0, pos_y=0, z_index=0, embedding=None)
    positions = match_notes([n1])
    assert len(positions) == 1
    assert positions[0].id == n1.id
