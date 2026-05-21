from unittest.mock import patch

import pytest

from core.embeddings import generate_embedding


def test_generate_embedding_returns_none_for_empty_text():
    assert generate_embedding("") is None
    assert generate_embedding("   ") is None


def test_generate_embedding_calls_gemini_and_returns_vector(settings):
    settings.GEMINI_API_KEY = "fake-api-key"
    fake_vector = [0.1] * 768
    fake_response = type("R", (), {"__getitem__": lambda self, k: fake_vector})()
    with patch("core.embeddings._embed") as mock_embed:
        mock_embed.return_value = {"embedding": fake_vector}
        result = generate_embedding("Hello world")
    mock_embed.assert_called_once_with("Hello world")
    assert result == fake_vector


def test_generate_embedding_returns_none_on_gemini_error():
    with patch("core.embeddings._embed", side_effect=RuntimeError("boom")):
        result = generate_embedding("Hello world")
    assert result is None


def test_generate_embedding_returns_none_when_no_api_key(settings):
    settings.GEMINI_API_KEY = ""
    result = generate_embedding("Hello world")
    assert result is None
