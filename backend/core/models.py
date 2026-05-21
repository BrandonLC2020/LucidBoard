from __future__ import annotations

import uuid

from django.contrib.auth.models import AbstractBaseUser
from django.db import models
from pgvector.django import VectorField

from core.managers import AnonymousUserManager, UserScopedManager


class User(AbstractBaseUser):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # db_column avoids shadowing AbstractBaseUser.is_anonymous property
    is_anonymous_user = models.BooleanField(default=True, db_column="is_anonymous")
    created_at = models.DateTimeField(auto_now_add=True)

    objects = AnonymousUserManager()

    USERNAME_FIELD = "id"
    REQUIRED_FIELDS: list[str] = []

    class Meta:
        db_table = "users"

    @property
    def is_authenticated(self) -> bool:  # ninja/django use this
        return True


class Board(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, db_column="user_id")
    title = models.TextField()
    background_color = models.TextField(default="#FFFFFF")
    background_layout = models.TextField(default="grid")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserScopedManager()

    class Meta:
        db_table = "boards"


class Note(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    board = models.ForeignKey(Board, on_delete=models.CASCADE, db_column="board_id")
    user = models.ForeignKey(User, on_delete=models.CASCADE, db_column="user_id")
    content_text = models.TextField(null=True, blank=True)
    content_drawing = models.BinaryField(null=True, blank=True)
    color = models.TextField()
    pos_x = models.FloatField()
    pos_y = models.FloatField()
    z_index = models.IntegerField()
    template = models.TextField(default="plain")
    checklist_items = models.JSONField(default=list)
    embedding = VectorField(dimensions=768, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserScopedManager()

    class Meta:
        db_table = "notes"


class Profile(models.Model):
    user = models.OneToOneField(
        User, on_delete=models.CASCADE, primary_key=True, db_column="id"
    )
    settings = models.JSONField(default=dict)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "profiles"
