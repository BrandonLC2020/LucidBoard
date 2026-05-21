from __future__ import annotations

import jwt
from django.http import HttpRequest
from ninja import NinjaAPI
from ninja.errors import AuthenticationError, ValidationError

api = NinjaAPI(title="LucidBoard Local API", version="0.1.0", urls_namespace="api")


@api.get("/api/health")
def health(request: HttpRequest):
    return {"status": "ok"}


@api.exception_handler(AuthenticationError)
def on_auth_error(request, exc):
    return api.create_response(
        request, {"detail": "Unauthorized", "code": "unauthorized"}, status=401
    )


@api.exception_handler(jwt.ExpiredSignatureError)
def on_expired(request, exc):
    return api.create_response(
        request, {"detail": "Token expired", "code": "token_expired"}, status=401
    )


@api.exception_handler(ValidationError)
def on_validation(request, exc):
    return api.create_response(
        request,
        {"detail": "Validation failed", "code": "validation_error", "errors": exc.errors},
        status=422,
    )
