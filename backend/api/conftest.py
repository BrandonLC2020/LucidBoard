import pytest
from django.test import Client

from core.auth import mint_anonymous_token


@pytest.fixture
def client():
    return Client()


@pytest.fixture
def auth_client():
    user, token = mint_anonymous_token()
    c = Client(HTTP_AUTHORIZATION=f"Bearer {token}")
    c.user = user
    return c
