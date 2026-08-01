from django.conf import settings
import jwt

from core.repository import get_user


def test_anonymous_signup_creates_user_and_returns_token(client):
    res = client.post("/auth/v1/signup?anonymous=true")
    assert res.status_code == 200
    body = res.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == settings.JWT_EXPIRY_SECONDS
    assert body["user"]["is_anonymous"] is True
    payload = jwt.decode(
        body["access_token"], settings.JWT_SECRET,
        algorithms=["HS256"], audience="authenticated",
    )
    assert payload["sub"] == body["user"]["id"]
    import uuid
    assert get_user(uuid.UUID(body["user"]["id"])) is not None


def test_anonymous_signup_without_query_param_returns_400(client):
    res = client.post("/auth/v1/signup")
    assert res.status_code == 400
    assert res.json()["code"] == "anonymous_required"
