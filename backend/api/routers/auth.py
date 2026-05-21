from __future__ import annotations

from django.conf import settings
from django.http import HttpRequest
from ninja import Router

from api.schemas import AuthResponse, AuthUserOut
from core.auth import mint_anonymous_token

router = Router()


@router.post("/v1/signup", response={200: AuthResponse, 400: dict})
def signup(request: HttpRequest, anonymous: bool = False):
    if not anonymous:
        return 400, {"detail": "anonymous=true required (Phase 1)", "code": "anonymous_required"}
    user, token = mint_anonymous_token()
    return 200, AuthResponse(
        access_token=token,
        token_type="bearer",
        expires_in=settings.JWT_EXPIRY_SECONDS,
        user=AuthUserOut(id=user.id, is_anonymous=True),
    )
