from __future__ import annotations

from django.contrib.auth.models import BaseUserManager
from django.db import models


class UserScopedManager(models.Manager):
    """Manager that filters queries to a specific user_id.

    Used as a helper from views: `Board.objects.for_user(user)`.
    """

    def for_user(self, user):
        return self.filter(user_id=user.id)


class AnonymousUserManager(BaseUserManager):
    """User manager that only supports anonymous users.

    Phase 1 anonymous-only auth. `create_anonymous()` makes a row with
    is_anonymous=True. No password support.
    """

    def create_anonymous(self):
        user = self.model(is_anonymous_user=True)
        user.set_unusable_password()
        user.save(using=self._db)
        return user
