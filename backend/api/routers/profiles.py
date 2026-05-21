from __future__ import annotations

from django.http import HttpRequest
from ninja import Router

from api.schemas import ProfileOut, ProfileUpsertIn
from core.auth import JWTBearer
from core.models import Profile

router = Router(auth=JWTBearer())


@router.get("/profile", response=ProfileOut)
def get_profile(request: HttpRequest):
    profile, _ = Profile.objects.get_or_create(user=request.auth)
    return ProfileOut(settings=profile.settings)


@router.put("/profile", response=ProfileOut)
def upsert_profile(request: HttpRequest, payload: ProfileUpsertIn):
    profile, _ = Profile.objects.update_or_create(
        user=request.auth, defaults={"settings": payload.settings}
    )
    return ProfileOut(settings=profile.settings)
