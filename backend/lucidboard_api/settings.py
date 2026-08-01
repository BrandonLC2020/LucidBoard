import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-only-change-me")
JWT_SECRET = os.environ.get("JWT_SECRET", "dev-only-change-me-jwt")
JWT_EXPIRY_SECONDS = int(os.environ.get("JWT_EXPIRY_SECONDS", "3600"))
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

FIRESTORE_PROJECT_ID = os.environ.get("FIRESTORE_PROJECT_ID", "demo-lucidboard")
# google-cloud-firestore reads FIRESTORE_EMULATOR_HOST directly from the
# environment; re-export it here only so `.env` is the single source of
# truth even though load_dotenv already populated os.environ.
FIRESTORE_EMULATOR_HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "")
if FIRESTORE_EMULATOR_HOST:
    os.environ.setdefault("FIRESTORE_EMULATOR_HOST", FIRESTORE_EMULATOR_HOST)

DEBUG = True
ALLOWED_HOSTS = ["*"]

INSTALLED_APPS = [
    "core",
]

MIDDLEWARE = [
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "lucidboard_api.urls"
WSGI_APPLICATION = "lucidboard_api.wsgi.application"
ASGI_APPLICATION = "lucidboard_api.asgi.application"

USE_TZ = True
TIME_ZONE = "UTC"
