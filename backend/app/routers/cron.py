from fastapi import APIRouter, Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.errors import ApiError
from app.services.reminders import run_reminder_tick
from app.services.streak_reminders import run_streak_reminder_tick

router = APIRouter(prefix="/api/cron", tags=["cron"])


@router.post("/reminders")
async def reminders_tick_route(x_cron_secret: str | None = Header(default=None), db: AsyncSession = Depends(get_db)):
    """Triggered on a schedule by a GitHub Actions workflow, not by a user
    (§ lesson reminder fix, 2026-09-07). Guarded by a shared secret rather
    than require_auth/require_admin: the caller has no user session at
    all, just the secret configured on both sides. An unset CRON_SECRET
    refuses every request rather than accepting an unauthenticated one.

    Runs both independent reminder ticks on the same GitHub Actions
    schedule (no reason to double the infra — they don't share state or
    dedup tables, see each module's own header). The study/lesson reminder
    briefly moved to a local device notification (§ study reminder local
    delivery, 2026-09-15) and was moved back to push the same day after a
    real-device MIUI test — see reminders.py's own header for why."""
    if not settings.cron_secret or x_cron_secret != settings.cron_secret:
        raise ApiError(401, "unauthorized")
    lesson_result = await run_reminder_tick(db)
    streak_result = await run_streak_reminder_tick(db)
    return {"lessonReminder": lesson_result, "streakReminder": streak_result}
