from fastapi import APIRouter, Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_db
from app.errors import ApiError
from app.services.reminders import run_reminder_tick

router = APIRouter(prefix="/api/cron", tags=["cron"])


@router.post("/reminders")
async def reminders_tick_route(x_cron_secret: str | None = Header(default=None), db: AsyncSession = Depends(get_db)):
    """Triggered on a schedule by a GitHub Actions workflow, not by a user
    (§ lesson reminder fix, 2026-09-07) — Cloud Run has no built-in
    scheduler, so an external caller has to be the one pinging this. Guarded
    by a shared secret rather than require_auth/require_admin: the caller
    has no user session at all, just the secret configured on both sides.
    An unset CRON_SECRET refuses every request rather than accepting an
    unauthenticated one."""
    if not settings.cron_secret or x_cron_secret != settings.cron_secret:
        raise ApiError(401, "unauthorized")
    return await run_reminder_tick(db)
