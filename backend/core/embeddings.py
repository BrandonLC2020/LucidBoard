from __future__ import annotations

import logging

import google.generativeai as genai
from django.conf import settings

logger = logging.getLogger(__name__)

_MODEL = "models/text-embedding-004"


def _embed(text: str) -> dict:
    """Real Gemini call, isolated for mocking in tests."""
    genai.configure(api_key=settings.GEMINI_API_KEY)
    return genai.embed_content(model=_MODEL, content=text)


def generate_embedding(text: str) -> list[float] | None:
    """Return a 768-dim embedding for `text`, or None on any failure.

    Returns None — without raising — when text is empty, the API key is
    not configured, or the Gemini call fails. Caller must persist None
    as a null embedding column.
    """
    if not text or not text.strip():
        return None
    if not settings.GEMINI_API_KEY:
        logger.warning("GEMINI_API_KEY not set; storing null embedding")
        return None
    try:
        result = _embed(text.strip())
        return list(result["embedding"])
    except Exception:  # noqa: BLE001 — deliberate broad catch for graceful degradation
        logger.exception("Gemini embedding failed; storing null embedding")
        return None
