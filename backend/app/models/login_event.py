import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.user import User


class LoginEvent(Base):
    """One row per successful login — lets an admin see a user's full login
    history, not just the most recent one."""

    __tablename__ = "LoginEvent"
    __table_args__ = (Index("LoginEvent_userId_createdAt_idx", "userId", "createdAt"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, server_default="now()")

    user: Mapped["User"] = relationship(back_populates="loginEvents")
