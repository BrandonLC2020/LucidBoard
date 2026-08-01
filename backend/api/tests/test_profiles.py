from core.repository import get_profile


def test_get_profile_auto_creates_on_first_call(auth_client):
    assert get_profile(auth_client.user.id) is None
    res = auth_client.get("/api/profile")
    assert res.status_code == 200
    assert res.json() == {"settings": {}}
    assert get_profile(auth_client.user.id) is not None


def test_upsert_profile(auth_client):
    res = auth_client.put(
        "/api/profile",
        data={"settings": {"defaultNoteColor": "#000"}},
        content_type="application/json",
    )
    assert res.status_code == 200
    profile = get_profile(auth_client.user.id)
    assert profile.settings == {"defaultNoteColor": "#000"}
