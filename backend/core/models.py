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
