import pytest

from core.models import Profile

pytestmark = pytest.mark.django_db


def test_get_profile_auto_creates_on_first_call(auth_client):
    assert not Profile.objects.filter(user=auth_client.user).exists()
    res = auth_client.get("/api/profile")
    assert res.status_code == 200
    assert res.json() == {"settings": {}}
    assert Profile.objects.filter(user=auth_client.user).exists()


def test_upsert_profile(auth_client):
    res = auth_client.put(
        "/api/profile",
        data={"settings": {"defaultNoteColor": "#000"}},
        content_type="application/json",
    )
    assert res.status_code == 200
    profile = Profile.objects.get(user=auth_client.user)
    assert profile.settings == {"defaultNoteColor": "#000"}
