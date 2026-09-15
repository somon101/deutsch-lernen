"""Streak-at-risk push reminder (§ streak reminder, 2026-09-15) — the
second, fully independent reminder mechanism, deliberately separate from
the study/lesson reminder in services/reminders.py (which is now delivered
as a LOCAL device notification, not a server push at all).

This one is server+push only, and admin-gated globally
(NotificationSettings.streakReminderEnabled) rather than per-user — no
setting is ever shown to an ordinary user for it. When enabled, it reuses
the EXISTING streak calculation (services/progress.py's get_streak_days)
unmodified: the only thing built here is the delivery chain around it
(when to check, who's already safe today, how not to double-send).

Design decisions worth being explicit about, since the request has no
single "right" answer for them:
  - Trigger hour (STREAK_CHECK_HOUR): the spec doesn't ask for a
    per-user-configurable time (the whole point is no user-facing setting
    exists), so a single fixed local hour is used, computed in each user's
    own timezone (UserPreference.timezone, already captured for the
    lesson-reminder feature and reused here unchanged) — giving most of
    the day to pass before nudging anyone.
  - "Today" for the stop condition and the repeat-log's own date column is
    the UTC calendar date, matching get_streak_days'/DailyActivity's own
    `utcnow().date()` convention exactly (see progress.py) — not the
    user's local date. Mixing local-time triggering with UTC-day
    bookkeeping is intentional: the trigger hour is about when a human
    should be nudged, but "has the streak condition been met today" must
    use the SAME notion of "today" the streak calculation itself uses, or
    the two could disagree about whether the streak is actually safe.
"""

from datetime import date, datetime, timedelta
from datetime import timezone as dt_timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.daily_activity import DailyActivity
from app.models.daily_goal import UserPreference
from app.models.streak_reminder import StreakReminderLog
from app.models.user import User
from app.services.progress import get_streak_days
from app.services.push import get_settings, send_push_to_user
from app.utils import utcnow

# Local hour (in each user's own timezone) after which a user with no
# activity yet today starts being considered for a reminder. The repeat
# interval itself is admin-editable (NotificationSettings.
# streakReminderIntervalMinutes, § streak reminder repeat interval,
# 2026-09-15) rather than a constant here.
STREAK_CHECK_HOUR = 20


def _as_utc(naive_utc: datetime) -> datetime:
    """See services/reminders.py's identical helper docstring — every
    timestamp column in this app is naive-but-conceptually-UTC."""
    return naive_utc.replace(tzinfo=dt_timezone.utc)


def _streak_push_body(streak: int) -> str:
    day_word = "день" if streak % 10 == 1 and streak % 100 != 11 else ("дня" if 2 <= streak % 10 <= 4 and not (12 <= streak % 100 <= 14) else "дней")
    return f"Твоя серия из {streak} {day_word} подряд под угрозой! Зайди в приложение сегодня, чтобы не потерять её."


async def run_streak_reminder_tick(db: AsyncSession) -> dict:
    settings = await get_settings(db)
    if not settings.streakReminderEnabled:
        # Zero per-user work when the admin switch is off — not just "skip
        # sending", genuinely nothing is queried or computed.
        return {"checked": 0, "sent": 0, "enabled": False}

    prefs = (
        await db.execute(select(UserPreference).where(UserPreference.pushEnabled.is_(True), UserPreference.timezone.is_not(None)))
    ).scalars().all()

    repeat_interval = timedelta(minutes=settings.streakReminderIntervalMinutes)
    now_utc = utcnow()
    checked = 0
    sent = 0
    for pref in prefs:
        checked += 1
        try:
            if await _maybe_send_for_user(db, pref, now_utc, repeat_interval):
                sent += 1
        except Exception as exc:  # noqa: BLE001 — one user's failure must never stop the tick
            print(f"streak_reminders: не удалось обработать пользователя {pref.userId}: {exc!r}")
    return {"checked": checked, "sent": sent, "enabled": True}


async def _maybe_send_for_user(db: AsyncSession, pref: UserPreference, now_utc: datetime, repeat_interval: timedelta) -> bool:
    try:
        tz = ZoneInfo(pref.timezone)
    except Exception:
        return False

    local_now = _as_utc(now_utc).astimezone(tz)
    check_at_today = local_now.replace(hour=STREAK_CHECK_HOUR, minute=0, second=0, microsecond=0)
    if local_now < check_at_today:
        return False  # too early in this user's own day

    utc_today: date = now_utc.date()  # matches get_streak_days'/DailyActivity's own "today"

    already_active_today = await db.scalar(
        select(DailyActivity.id).where(DailyActivity.userId == pref.userId, DailyActivity.activityDate == utc_today).limit(1)
    )
    if already_active_today:
        return False  # the existing stop condition: today already counts toward the streak

    streak = await get_streak_days(db, pref.userId)  # the EXISTING calculation, unmodified
    if streak < 1:
        return False  # nothing at risk — this mechanism only warns about a real streak

    user = await db.get(User, pref.userId)
    if user is None:
        return False

    log = (
        await db.execute(select(StreakReminderLog).where(StreakReminderLog.userId == pref.userId, StreakReminderLog.reminderDate == utc_today))
    ).scalar_one_or_none()

    if log is None:
        db.add(StreakReminderLog(userId=pref.userId, reminderDate=utc_today, sendCount=1, lastSentAt=now_utc))
        try:
            await db.commit()
        except IntegrityError:
            # Another instance/tick already created today's row between our
            # SELECT and this INSERT — that one is sending, we are not.
            await db.rollback()
            return False
        await send_push_to_user(db, user_id=pref.userId, title="Серия под угрозой", body=_streak_push_body(streak), deep_link="/leaderboard")
        return True

    if now_utc - log.lastSentAt < repeat_interval:
        return False  # too soon since the last one for a repeat to be due

    # Column-bound update(), not raw SQL — see services/reminders.py's own
    # note on why (a real, previously-shipped bug in this exact pattern).
    # The `lastSentAt == log.lastSentAt` clause is the actual guard.
    result = await db.execute(
        update(StreakReminderLog)
        .where(StreakReminderLog.userId == pref.userId, StreakReminderLog.reminderDate == utc_today, StreakReminderLog.lastSentAt == log.lastSentAt)
        .values(sendCount=StreakReminderLog.sendCount + 1, lastSentAt=now_utc)
    )
    await db.commit()
    if result.rowcount == 0:
        return False  # someone else already claimed this repeat

    # Recomputed streak (from step above, this same tick) is what's sent —
    # never a value cached from an earlier tick/send, satisfying "заново
    # рассчитывает актуальное количество streak перед каждым повторным PUSH".
    await send_push_to_user(db, user_id=pref.userId, title="Серия под угрозой", body=_streak_push_body(streak), deep_link="/leaderboard")
    return True
