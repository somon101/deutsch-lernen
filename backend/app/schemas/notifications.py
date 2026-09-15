from typing import Literal

from pydantic import BaseModel, Field


class PushTokenRegisterInput(BaseModel):
    token: str
    platform: Literal["android", "ios", "web"]


class NotificationSettingsUpdateInput(BaseModel):
    """All optional (§ streak reminder, 2026-09-15) — toggling one setting
    no longer requires resending the others' current values."""

    autoSendOnNewLesson: bool | None = None
    streakReminderEnabled: bool | None = None
    # Minutes between repeat streak-at-risk pushes (§ streak reminder repeat
    # interval, 2026-09-15). Lower bound of 1 rather than 0: 0 would mean
    # "resend on every single cron tick", which isn't a real interval.
    streakReminderIntervalMinutes: int | None = Field(default=None, gt=0)
