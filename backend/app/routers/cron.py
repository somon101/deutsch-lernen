from fastapi import APIRouter, Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.errors import ApiError
from app.services.streak_reminders import run_streak_reminder_tick

router = APIRouter(prefix="/api/cron", tags=["cron"])


@router.post("/reminders")
async def reminders_tick_route(x_cron_secret: str | None = Header(default=None), db: AsyncSession = Depends(get_db)):
    """Triggered on a schedule by a GitHub Actions workflow, not by a user
    (§ lesson reminder fix, 2026-09-07). Guarded by a shared secret rather
    than require_auth/require_admin: the caller has no user session at
    all, just the secret configured on both sides. An unset CRON_SECRET
    refuses every request rather than accepting an unauthenticated one.

    § streak reminder, 2026-09-15 — same URL/secret/GitHub Actions
    schedule as before (no infra change needed), but now runs the
    streak-at-risk tick instead of the old lesson-reminder tick: the
    lesson/study reminder moved to a LOCAL device notification (see
    frontend's local_reminder_service.dart), which needs no server tick at
    all — services/reminders.py's run_reminder_tick and LessonReminderLog
    are kept in the codebase (harmless, unused) rather than deleted, since
    removing a live table is a separate, riskier change than simply no
    longer calling it."""
    if not settings.cron_secret or x_cron_secret != settings.cron_secret:
        raise ApiError(401, "unauthorized")
    return await run_streak_reminder_tick(db)
