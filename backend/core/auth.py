from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
from django.conf import settings
from ninja.security import HttpBearer

from core.models import User


def mint_anonymous_token() -> tuple[User, str]:
    """Create a fresh anonymous user and return (user, signed_jwt)."""
    user = User.objects.create_anonymous()
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
    """Verify a JWT and return the User row it identifies.

    Raises jwt.InvalidTokenError subclasses on failure
    (InvalidSignatureError, ExpiredSignatureError, ...).
    """
    payload = jwt.decode(
        token, settings.JWT_SECRET, algorithms=["HS256"], audience="authenticated"
    )
    return User.objects.get(id=payload["sub"])


class JWTBearer(HttpBearer):
    """Ninja auth class. Returns the User on success, None on failure."""

    def authenticate(self, request, token: str) -> User | None:
        try:
            user = decode_token(token)
        except (jwt.InvalidTokenError, User.DoesNotExist):
            return None
        request.user = user
        return user
