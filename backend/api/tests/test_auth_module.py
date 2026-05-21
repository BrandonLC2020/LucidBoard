from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import pytest
from django.conf import settings

from core.auth import decode_token, mint_anonymous_token
from core.models import User

pytestmark = pytest.mark.django_db


def test_mint_anonymous_token_creates_user():
    user, token = mint_anonymous_token()
    assert User.objects.filter(id=user.id).exists()
    assert user.is_anonymous_user is True


def test_mint_anonymous_token_has_correct_claims():
    user, token = mint_anonymous_token()
    payload = jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"], audience="authenticated")
    assert payload["sub"] == str(user.id)
    assert payload["role"] == "authenticated"
    assert payload["aud"] == "authenticated"
    assert payload["is_anonymous"] is True
    assert payload["exp"] - payload["iat"] == settings.JWT_EXPIRY_SECONDS


def test_decode_token_returns_user_for_valid_token():
    user, token = mint_anonymous_token()
    decoded_user = decode_token(token)
    assert decoded_user.id == user.id


def test_decode_token_raises_on_invalid_signature():
    user, _ = mint_anonymous_token()
    bad_token = jwt.encode(
        {"sub": str(user.id), "aud": "authenticated", "exp": 9999999999, "iat": 0,
         "role": "authenticated", "is_anonymous": True},
        "wrong-secret",
        algorithm="HS256",
    )
    with pytest.raises(jwt.InvalidSignatureError):
        decode_token(bad_token)


def test_decode_token_raises_on_expired_token():
    expired_payload = {
        "sub": str(uuid4()),
        "aud": "authenticated",
        "iat": int((datetime.now(tz=timezone.utc) - timedelta(hours=2)).timestamp()),
        "exp": int((datetime.now(tz=timezone.utc) - timedelta(hours=1)).timestamp()),
        "role": "authenticated",
        "is_anonymous": True,
    }
    expired_token = jwt.encode(expired_payload, settings.JWT_SECRET, algorithm="HS256")
    with pytest.raises(jwt.ExpiredSignatureError):
        decode_token(expired_token)
