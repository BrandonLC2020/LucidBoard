from __future__ import annotations

import os

import pytest
import requests

from core.firestore_client import get_client, reset_client_for_tests


def _emulator_host() -> str:
    host = os.environ.get("FIRESTORE_EMULATOR_HOST")
    if not host:
        pytest.exit(
            "FIRESTORE_EMULATOR_HOST is not set — start the emulator first:\n"
            "  firebase emulators:start --only firestore --project demo-lucidboard",
            returncode=1,
        )
    return host


@pytest.fixture(autouse=True)
def clear_firestore():
    """Wipe every document in the emulator before each test."""
    host = _emulator_host()
    project_id = os.environ.get("FIRESTORE_PROJECT_ID", "demo-lucidboard")
    reset_client_for_tests()
    url = f"http://{host}/emulator/v1/projects/{project_id}/databases/(default)/documents"
    requests.delete(url, timeout=5)
    yield
    requests.delete(url, timeout=5)


@pytest.fixture
def firestore_client():
    return get_client()
