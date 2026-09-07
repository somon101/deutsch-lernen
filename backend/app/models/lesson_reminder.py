import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class LessonReminderLog(Base):
    """One row per user per LOCAL calendar day the reminder chain has sent
    at least one push for (§ lesson reminder fix, 2026-09-07).

    Same idempotency shape as DailyGoalAward: the UNIQUE (userId,
    reminderDate) is what makes "exactly one first reminder per day" safe
    against a server restart, two Cloud Run instances, or two overlapping
    cron ticks — whichever request's INSERT lands first wins, Postgres
    rejects the rest. `sendCount`/`lastSentAt` then drive the repeat chain:
    a later tick only sends again once `lastSentAt` is at least the repeat
    interval in the past, and claims that turn with an UPDATE ... WHERE
    "lastSentAt" = <the value it read> — the same
    read-then-conditional-write pattern, so two ticks racing to send the
    SAME repeat can't both succeed.
    """

    __tablename__ = "LessonReminderLog"
    __table_args__ = (UniqueConstraint("userId", "reminderDate", name="LessonReminderLog_userId_reminderDate_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    reminderDate: Mapped[date] = mapped_column(Date(), nullable=False)
    sendCount: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    lastSentAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow)
