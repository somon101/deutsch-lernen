import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class DailyActivity(Base):
    """One row per (user, activityType, calendar day) — the discrete "a
    qualifying activity happened" signal streaks/weekly-activity are built
    from (§ streak mode, 2026-08-29), deliberately separate from
    ActivityTime: ActivityTime tracks continuous time spent regardless of
    whether anything was ever finished, but a streak must NOT count a lesson
    that was opened and abandoned — only a real completion. `activityType`
    is a free string precisely so a future feature (words_reviewed,
    exercise_completed, test_completed, ...) can start recording its own
    qualifying events with zero schema change: any row on a given day, of
    any type, makes that day "active" — see get_streak_days/get_week_activity,
    which never filter by activityType, only by (user, day).

    Idempotent per day: completing three lessons on the same day still
    yields exactly one "lesson_completed" row for that day, since a streak
    only cares whether the day had activity, not how much."""

    __tablename__ = "DailyActivity"
    __table_args__ = (UniqueConstraint("userId", "activityType", "activityDate", name="DailyActivity_userId_activityType_activityDate_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    activityType: Mapped[str] = mapped_column(String, nullable=False)
    activityDate: Mapped[date] = mapped_column(Date(), nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
