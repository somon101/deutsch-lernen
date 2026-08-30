import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class Follow(Base):
    """One user following another (§ subscriptions, 2026-08-30) — a plain
    directed edge, no approval step. `followerId` is who did the following,
    `followingId` is who they're following. "Mutual" (both directions
    existing) and follower/following counts are always computed fresh from
    this table, never stored redundantly, same convention progress/
    time/streak already use rather than a cached counter column."""

    __tablename__ = "Follow"
    __table_args__ = (UniqueConstraint("followerId", "followingId", name="Follow_followerId_followingId_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    followerId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    followingId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
