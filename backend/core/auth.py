from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import jwt
from django.conf import settings
from ninja.security import HttpBearer

from core.models import User
from core.repository import create_anonymous_user, get_user


def mint_anonymous_token() -> tuple[User, str]:
    """Create a fresh anonymous user and return (user, signed_jwt)."""
    user = create_anonymous_user()
    now = datetime.now(tz=timezone.utc)
    payload = {
        "sub": str(user.id),
        "role": "authenticated",
        "aud": "authenticated",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=settings.JWT_EXPIRY_SECONDS)).timestamp()),
        "is_anonymous": True,
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")
    return user, token


def decode_token(token: str) -> User:
    """Verify a JWT and return the User it identifies.

    Raises jwt.InvalidTokenError subclasses on failure
    (InvalidSignatureError, ExpiredSignatureError, ...), and ValueError
    if the token's subject no longer exists in Firestore.
    """
    payload = jwt.decode(
        token, settings.JWT_SECRET, algorithms=["HS256"], audience="authenticated"
    )
    user = get_user(uuid.UUID(payload["sub"]))
    if user is None:
        raise ValueError(f"user {payload['sub']} not found")
    return user


class JWTBearer(HttpBearer):
    """Ninja auth class. Returns the User on success, None on failure."""

    def authenticate(self, request, token: str) -> User | None:
        try:
            user = decode_token(token)
        except (jwt.InvalidTokenError, ValueError):
            return None
        request.user = user
        return user
