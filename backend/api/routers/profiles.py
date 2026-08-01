from __future__ import annotations

from django.http import HttpRequest
from ninja import Router

from api.schemas import ProfileOut, ProfileUpsertIn
from core.auth import JWTBearer
from core.repository import get_profile, upsert_profile

router = Router(auth=JWTBearer())


@router.get("/profile", response=ProfileOut)
def get_profile_view(request: HttpRequest):
    profile = get_profile(request.auth.id)
    if profile is None:
        profile = upsert_profile(request.auth.id, settings={})
    return ProfileOut(settings=profile.settings)


@router.put("/profile", response=ProfileOut)
def upsert_profile_view(request: HttpRequest, payload: ProfileUpsertIn):
    profile = upsert_profile(request.auth.id, settings=payload.settings)
    return ProfileOut(settings=profile.settings)
