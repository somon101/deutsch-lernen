import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.enums import Role, UserStatus
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.answer_log import AnswerLog
    from app.models.login_event import LoginEvent
    from app.models.push_token import PushToken


class User(Base):
    __tablename__ = "User"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    # 9-digit public-facing identifier — see schema.prisma's User.publicId
    # comment. `id` above stays the real primary key everywhere internally;
    # this is only ever shown to/used by end users (profile, QR card).
    publicId: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    firstName: Mapped[str] = mapped_column(String, nullable=False)
    lastName: Mapped[str] = mapped_column(String, nullable=False)
    email: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    phone: Mapped[str | None] = mapped_column(String, nullable=True)
    username: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    # Lower-cased copy of `username`, kept in sync on every write — same
    # split as the Prisma schema, so case-insensitive uniqueness/login stays
    # DB-enforced rather than just app-checked.
    usernameLower: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    passwordHash: Mapped[str] = mapped_column(String, nullable=False)
    role: Mapped[Role] = mapped_column(Enum(Role, name="Role", create_type=False), nullable=False, default=Role.USER)
    status: Mapped[UserStatus] = mapped_column(
        Enum(UserStatus, name="UserStatus", create_type=False), nullable=False, default=UserStatus.ACTIVE
    )
    avatarUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    # Free-text "about me" — capped at 150 chars app-side (UpdateProfileRequest),
    # not by a DB column length constraint.
    bio: Mapped[str | None] = mapped_column(String, nullable=True)
    birthDate: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)
    canEditProfile: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    # Which Language this user's profile progress is shown for (§ per-language
    # overall progress, 2026-08-29) — a personal preference, not something a
    # teacher/admin sets. SET NULL on delete: losing the referenced Language
    # should never block deleting it or break this user's row.
    selectedLanguageId: Mapped[str | None] = mapped_column(String, ForeignKey("Language.id", ondelete="SET NULL"), nullable=True)
    lastLoginAt: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)
    lastActiveAt: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)
    # createdAt has a real DB-level default (confirmed via information_schema:
    # column_default = CURRENT_TIMESTAMP), so server_default is enough here.
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, server_default="now()")
    # updatedAt has NO DB-level default (Prisma's @updatedAt is a
    # client-side behavior: Prisma Client stamps it on every write, insert
    # included) — server_default would be silently ineffective against the
    # already-existing table, so both default (insert) and onupdate
    # (update) must be supplied here, matching Prisma's actual behavior
    # rather than assuming the DB does it. Every future model with an
    # @updatedAt field needs this same treatment, not server_default.
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    loginEvents: Mapped[list["LoginEvent"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    answerLogs: Mapped[list["AnswerLog"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    pushTokens: Mapped[list["PushToken"]] = relationship(back_populates="user", cascade="all, delete-orphan")
