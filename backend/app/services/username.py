import re

# Mirrors server/src/username.ts exactly, including the Russian error text —
# usernames are plain latin letters only, compared case-insensitively.
USERNAME_PATTERN = re.compile(r"^[A-Za-z]+$")
USERNAME_MIN = 3
USERNAME_MAX = 32


def validate_username(value: str) -> str:
    if len(value) < USERNAME_MIN:
        raise ValueError(f"Логин должен содержать не менее {USERNAME_MIN} букв")
    if len(value) > USERNAME_MAX:
        raise ValueError(f"Логин должен содержать не более {USERNAME_MAX} букв")
    if not USERNAME_PATTERN.match(value):
        raise ValueError("Логин может содержать только латинские буквы (A-Z, a-z), без цифр, пробелов и знаков")
    return value


def normalize_username(username: str) -> str:
    """The value the case-insensitive unique constraint is checked against."""
    return username.lower()
