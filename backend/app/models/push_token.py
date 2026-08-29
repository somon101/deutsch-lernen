import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.user import User


class PushToken(Base):
    """One row per device a user has granted notification permission on.
    `token` is the FCM registration token — unique, since re-registering the
    same token (app reopened, token refreshed by FCM) just updates the row
    rather than creating a duplicate."""

    __tablename__ = "PushToken"
    __table_args__ = (Index("PushToken_userId_idx", "userId"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    token: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    platform: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    user: Mapped["User"] = relationship(back_populates="pushTokens")
