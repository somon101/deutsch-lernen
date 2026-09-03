from pydantic import BaseModel, EmailStr, Field, field_validator

from app.models.enums import Role, UserStatus
from app.services.username import validate_username


class CreateUserRequest(BaseModel):
    firstName: str = Field(min_length=1)
    lastName: str = Field(min_length=1)
    email: EmailStr
    username: str
    password: str = Field(min_length=6)
    role: Role = Role.USER
    canEditProfile: bool = True

    @field_validator("username")
    @classmethod
    def _check_username(cls, v: str) -> str:
        return validate_username(v)


class UpdateUserRequest(BaseModel):
    firstName: str | None = Field(default=None, min_length=1)
    lastName: str | None = Field(default=None, min_length=1)
    email: EmailStr | None = None
    username: str | None = None
    role: Role | None = None
    status: UserStatus | None = None
    canEditProfile: bool | None = None

    @field_validator("username")
    @classmethod
    def _check_username(cls, v: str | None) -> str | None:
        return validate_username(v) if v is not None else v


class ResetPasswordRequest(BaseModel):
    newPassword: str = Field(min_length=6)


class NotifyUserRequest(BaseModel):
    """One ad-hoc push message an admin sends straight to one user (§
    individual push, 2026-08-30) — deliberately not persisted as a
    Notification row (no message history), unlike the broadcast
    notifications send_notification() records."""

    message: str = Field(min_length=1, max_length=500)

    @field_validator("message")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Сообщение не может быть пустым")
        return v


class ChangePasswordRequest(BaseModel):
    """Self-service password change — unlike ResetPasswordRequest (admin
    resetting someone else's password, no proof of identity needed beyond
    being an admin), this requires the caller's current password."""

    currentPassword: str
    newPassword: str = Field(min_length=6)


class UpdateProfileRequest(BaseModel):
    firstName: str | None = Field(default=None, min_length=1)
    lastName: str | None = Field(default=None, min_length=1)
    email: EmailStr | None = None
    username: str | None = None
    bio: str | None = Field(default=None, max_length=150)
    # Raw ISO string, not Pydantic's `datetime` — the latter parses "...Z"
    # into a tz-AWARE datetime, which asyncpg refuses to bind to this
    # column's actual Postgres type ("timestamp without time zone"),
    # raising a DataError that surfaced to users as a bare 500. Parsed with
    # the same from_iso() every other tz-naive timestamp field in this API
    # already goes through (see app/utils.py) — not a special case.
    birthDate: str | None = None
    # Which Language the profile's overall-progress number is shown for —
    # null is a valid, explicit "no language chosen" value, not "leave
    # unchanged" (that's what omitting the field from the request does).
    selectedLanguageId: str | None = None
    # Which instructional-language variant of course content ("ru"/"tg") is
    # shown — see app/services/content_locale.py. Same "explicit null clears
    # it" semantics as selectedLanguageId above; validated in the router
    # against SUPPORTED_CONTENT_LOCALES rather than by a DB FK.
    contentLocale: str | None = None

    @field_validator("username")
    @classmethod
    def _check_username(cls, v: str | None) -> str | None:
        return validate_username(v) if v is not None else v
