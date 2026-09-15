import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class StreakReminderLog(Base):
    """One row per user per day the streak-at-risk push chain has sent at
    least one push for (§ streak reminder, 2026-09-15).

    Deliberately its own table, not a reuse of LessonReminderLog — the two
    reminder mechanisms (lesson/study reminder, now delivered as a LOCAL
    notification, vs. this admin-gated streak push) must stay fully
    independent, per the explicit requirement that neither affects the
    other. Same proven idempotency shape as LessonReminderLog/
    DailyGoalAward though: UNIQUE (userId, reminderDate) is what makes "at
    most one first push per day" safe against restarts/parallel workers/
    replayed requests, and the repeat chain claims each next slot with a
    conditional UPDATE guarded by `lastSentAt = <value just read>` so two
    racing ticks can't both send the same repeat.

    `reminderDate` is a UTC calendar date — matching get_streak_days' own
    `utcnow().date()` "today" exactly, not the user's local date, so this
    log's notion of "day" never drifts from the streak calculation it's
    reporting on.
    """

    __tablename__ = "StreakReminderLog"
    __table_args__ = (UniqueConstraint("userId", "reminderDate", name="StreakReminderLog_userId_reminderDate_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    reminderDate: Mapped[date] = mapped_column(Date(), nullable=False)
    sendCount: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    lastSentAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow)
