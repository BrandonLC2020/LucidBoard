from __future__ import annotations

from google.cloud import firestore

from django.conf import settings

_client: firestore.Client | None = None


def get_client() -> firestore.Client:
    """Return a process-wide Firestore client.

    Routes to the emulator automatically when `FIRESTORE_EMULATOR_HOST` is
    set in the environment (the google-cloud-firestore client checks this
    var itself) — no credentials are needed against the emulator.
    """
    global _client
    if _client is None:
        _client = firestore.Client(project=settings.FIRESTORE_PROJECT_ID)
    return _client


def reset_client_for_tests() -> None:
    """Drop the cached client so tests can rebuild it against a fresh emulator."""
    global _client
    _client = None
