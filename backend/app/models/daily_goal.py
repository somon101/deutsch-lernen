import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class UserPreference(Base):
    """Per-user settings that must follow the account, not the device
    (§ daily goal, 2026-09-03).

    The settings screen previously wrote every choice to the device's own
    SharedPreferences, with a TODO saying no endpoint existed. This is that
    endpoint's storage. Only the daily goal lives here so far — the rest of
    the screen is still device-local, and moving it is a separate job.

    One typed column per setting rather than a key/value bag: a column can
    be constrained and queried, and cannot hold a value the schema does not
    know about.
    """

    __tablename__ = "UserPreference"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False, unique=True)
    dailyGoalMinutes: Mapped[int] = mapped_column(Integer, nullable=False, default=10)
    # The two sound settings (§ sound settings, 2026-09-03). Separate columns
    # on purpose: silencing the exercise chimes and silencing word
    # pronunciation are different wishes, and one flag could not express both.
    lessonSoundEnabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    wordAudioEnabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow)
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)


class DailyGoalAward(Base):
    """One row per user per calendar day on which the daily goal was met and
    its points paid (§ daily goal, 2026-09-03).

    The UNIQUE (userId, awardDate) is not bookkeeping — it IS the guarantee
    that the reward is paid once. A refresh, a replayed request, a second
    device, two Cloud Run instances and two genuinely simultaneous requests
    all try to insert the same row; Postgres accepts exactly one and rejects
    the rest. An application-level "have we already paid?" check could not
    make that promise, because two requests can both read "no" before either
    writes.

    `goalMinutes` and `secondsAtAward` are kept so the row explains itself
    later: which goal was in force when it was paid, and how much study time
    stood behind it.
    """

    __tablename__ = "DailyGoalAward"
    __table_args__ = (UniqueConstraint("userId", "awardDate", name="DailyGoalAward_userId_awardDate_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    awardDate: Mapped[date] = mapped_column(Date(), nullable=False, default=lambda: utcnow().date())
    goalMinutes: Mapped[int] = mapped_column(Integer, nullable=False)
    points: Mapped[int] = mapped_column(Integer, nullable=False)
    secondsAtAward: Mapped[int] = mapped_column(Integer, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow)
