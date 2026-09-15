from datetime import datetime

from sqlalchemy import Boolean, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class NotificationSettings(Base):
    """Single-row table (id is always "singleton") holding the admin-facing
    on/off switches for automatic sending. One boolean per event type — a
    future event type adds one column here, not a new table."""

    __tablename__ = "NotificationSettings"

    id: Mapped[str] = mapped_column(String, primary_key=True, default="singleton")
    autoSendOnNewLesson: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    # Global kill switch for the streak-at-risk push reminder (§ streak
    # reminder, 2026-09-15) — no per-user setting exists for this at all;
    # an ordinary user never sees or controls it, only this one admin-wide
    # switch does. Off by default so the mechanism never starts pushing
    # anyone the moment this column is added.
    streakReminderEnabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)
