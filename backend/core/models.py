from django.contrib.auth.models import AbstractBaseUser


class User(AbstractBaseUser):
    """Stub — Task 2 will replace this with the full model.

    Do NOT run makemigrations before Task 2; this stub exists only to
    satisfy AUTH_USER_MODEL validation during manage.py check.
    """

    USERNAME_FIELD = "id"
    REQUIRED_FIELDS: list[str] = []
