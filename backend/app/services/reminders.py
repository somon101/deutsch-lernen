"""Lesson-reminder push, with a repeat chain (§ lesson reminder fix,
2026-09-07).

**Briefly superseded 2026-09-15, reinstated the same day**: for a few
hours the study/lesson reminder was delivered as a LOCAL device
notification instead (frontend's core/notifications/
local_reminder_service.dart, scheduled on-device via AlarmManager) to make
it independent of server/network availability at fire time. A real
on-device test on a Xiaomi/MIUI phone found that guarantee doesn't hold in
practice: MIUI's own "Автозапуск" (autostart) restriction blocked the
app's background process from completing the notification after the
alarm fired (confirmed via `adb shell dumpsys alarm`/`logcat` —
`AutoStartManagerService: MIUILOG- Reject RestartService` for this exact
package), with no in-app way to detect or fix that short of asking every
user to manually grant autostart per OEM. Push notifications, by
contrast, ride Google Play Services' own already-whitelisted process, so
they aren't affected by that same restriction — confirmed working on the
very same device throughout. Given how common MIUI-family phones are,
"works offline at the exact fire second" lost to "actually fires" — this
module is active again, `local_reminder_service.dart` and its plumbing
were removed rather than left as unreachable code, and routers/cron.py's
POST /api/cron/reminders now calls both this tick and
services/streak_reminders.py's run_streak_reminder_tick.

Root cause of "the reminder never fires" (found before writing any of this):
the Settings screen's reminder toggle/time picker was 100% device-local
SharedPreferences state (settings_repository.dart, literal "TODO: подключить
API" in its own header) — nothing was ever sent to the server, there was no
column to store it in, and nothing periodic ever ran to check it. The push
*delivery* mechanism (services/push.py's send_push_to_user) already worked
fine; it just had no caller for this feature. So this is a genuine gap being
filled, not a bug in existing reminder logic — there was no server-side
reminder logic to have a bug in.

`run_reminder_tick` is meant to be invoked on a schedule (a GitHub Actions
cron workflow hitting POST /api/cron/reminders every ~10 minutes, since
Cloud Run itself has no built-in scheduler — see that workflow file). Each
call:

  1. Loads every UserPreference row with push AND the reminder both enabled
     and a known timezone (no timezone -> can't compute their local time ->
     skipped, never guessed at).
  2. For each, computes local "now" via zoneinfo (handles DST correctly by
     construction — it looks up the real transition rules for the zone,
     never a fixed offset that would go stale twice a year).
  3. Skips anyone whose local `now` hasn't reached their reminder time yet
     today, and anyone whose `User.lastActiveAt` already falls on today's
     local date (they opened the app — the day's chain is simply never
     started for them, and never resumes even if this tick runs again later
     the same day, since that same lastActiveAt check applies every time).
  4. Sends the first reminder of the local day via an INSERT that can only
     succeed once (LessonReminderLog's UNIQUE (userId, reminderDate)) —
     concurrent ticks/instances/restarts all attempt it, Postgres accepts
     exactly one.
  5. On a later tick, sends a repeat only once REPEAT_INTERVAL has passed
     since `lastSentAt`, claiming that turn with an UPDATE guarded by
     `lastSentAt = <the value just read>` — the same
     read-then-conditional-write shape as the INSERT above, so two ticks
     racing to send the same repeat can't both win.

A new local day naturally starts the whole chain over: `reminderDate` is
different, so step 4 applies again as if the user were new.
"""

from datetime import date, datetime, timedelta
from datetime import timezone as dt_timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.daily_goal import UserPreference
from app.models.lesson_reminder import LessonReminderLog
from app.models.user import User
from app.services.push import send_push_to_user
from app.utils import utcnow

REMINDER_TITLE = "Пора заниматься!"
REMINDER_BODY = "Ты ещё не заходил в уроки. Не дай своему прогрессу остановиться."
REPEAT_INTERVAL = timedelta(hours=2)


def _as_utc(naive_utc: datetime) -> datetime:
    """Every timestamp column in this app is naive-but-conceptually-UTC (see
    utils.py's own docstring) — this is the one added step needed before
    `.astimezone()` can be trusted to convert it into someone's real local
    time instead of silently treating it as naive local time."""
    return naive_utc.replace(tzinfo=dt_timezone.utc)


async def run_reminder_tick(db: AsyncSession) -> dict:
    now_utc = utcnow()
    prefs = (
        await db.execute(
            select(UserPreference).where(
                UserPreference.pushEnabled.is_(True),
                UserPreference.lessonReminderEnabled.is_(True),
                UserPreference.timezone.is_not(None),
            )
        )
    ).scalars().all()

    checked = 0
    sent = 0
    for pref in prefs:
        checked += 1
        try:
            if await _maybe_send_for_user(db, pref, now_utc):
                sent += 1
        except Exception as exc:  # noqa: BLE001 — one user's failure must never stop the tick
            print(f"reminders: не удалось обработать пользователя {pref.userId}: {exc!r}")
    return {"checked": checked, "sent": sent}


async def _maybe_send_for_user(db: AsyncSession, pref: UserPreference, now_utc: datetime) -> bool:
    try:
        tz = ZoneInfo(pref.timezone)
    except Exception:
        return False  # a stored value that isn't a real IANA name anymore

    local_now = _as_utc(now_utc).astimezone(tz)
    reminder_at_today = local_now.replace(hour=pref.lessonReminderHour, minute=pref.lessonReminderMinute, second=0, microsecond=0)
    if local_now < reminder_at_today:
        return False  # not their reminder time yet today

    user = await db.get(User, pref.userId)
    if user is None:
        return False
    if user.lastActiveAt is not None and _as_utc(user.lastActiveAt).astimezone(tz).date() == local_now.date():
        return False  # already opened the app today (their local day) — chain doesn't start/continue

    today_local: date = local_now.date()
    log = (
        await db.execute(select(LessonReminderLog).where(LessonReminderLog.userId == pref.userId, LessonReminderLog.reminderDate == today_local))
    ).scalar_one_or_none()

    if log is None:
        db.add(LessonReminderLog(userId=pref.userId, reminderDate=today_local, sendCount=1, lastSentAt=now_utc))
        try:
            await db.commit()
        except IntegrityError:
            # Another instance/tick already created today's row between our
            # SELECT and this INSERT — that one is sending, we are not.
            await db.rollback()
            return False
        await send_push_to_user(db, user_id=pref.userId, title=REMINDER_TITLE, body=REMINDER_BODY, deep_link="/")
        return True

    if now_utc - log.lastSentAt < REPEAT_INTERVAL:
        return False  # too soon since the last one for a repeat to be due

    # Column-bound update() rather than raw SQL text() — lets SQLAlchemy's
    # own type system bind `now_utc`/`log.lastSentAt` correctly regardless of
    # backend, instead of relying on the DBAPI driver's own guess for a bare
    # parameter dict. The `lastSentAt == log.lastSentAt` clause is the actual
    # guard: only a request that read the SAME lastSentAt this one did can
    # win the update, so two racing repeats can't both succeed.
    result = await db.execute(
        update(LessonReminderLog)
        .where(LessonReminderLog.userId == pref.userId, LessonReminderLog.reminderDate == today_local, LessonReminderLog.lastSentAt == log.lastSentAt)
        .values(sendCount=LessonReminderLog.sendCount + 1, lastSentAt=now_utc)
    )
    await db.commit()
    if result.rowcount == 0:
        # Someone else already advanced lastSentAt past what we read —
        # that repeat has already been claimed and sent.
        return False
    await send_push_to_user(db, user_id=pref.userId, title=REMINDER_TITLE, body=REMINDER_BODY, deep_link="/")
    return True
