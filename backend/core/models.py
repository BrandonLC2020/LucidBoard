from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID


@dataclass
class User:
    id: UUID
    is_anonymous_user: bool = True
    created_at: datetime | None = None

    @property
    def is_authenticated(self) -> bool:  # ninja/django use this
        return True

    @property
    def is_anonymous(self) -> bool:
        return self.is_anonymous_user


@dataclass
class Profile:
    user_id: UUID
    settings: dict = field(default_factory=dict)
    updated_at: datetime | None = None


@dataclass
class Board:
    id: UUID
    user_id: UUID
    title: str = "Untitled"
    background_color: str = "#FFFFFF"
    background_layout: str = "grid"
    created_at: datetime | None = None
    updated_at: datetime | None = None


@dataclass
class Note:
    id: UUID
    board_id: UUID
    user_id: UUID
    content_text: str | None = None
    content_drawing: bytes | None = None
    color: str = "#FFFFFF"
    pos_x: float = 0.0
    pos_y: float = 0.0
    z_index: int = 0
    template: str = "plain"
    checklist_items: list[dict] = field(default_factory=list)
    embedding: list[float] | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
