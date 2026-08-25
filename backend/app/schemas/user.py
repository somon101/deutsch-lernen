from pydantic import BaseModel, EmailStr, Field, field_validator

from app.models.enums import Role, UserStatus
from app.services.username import validate_username


class CreateUserRequest(BaseModel):
    firstName: str = Field(min_length=1)
    lastName: str = Field(min_length=1)
    email: EmailStr
    phone: str | None = None
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
    phone: str | None = None
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


class UpdateProfileRequest(BaseModel):
    firstName: str | None = Field(default=None, min_length=1)
    lastName: str | None = Field(default=None, min_length=1)
    email: EmailStr | None = None
    phone: str | None = None
