from typing import Literal

from pydantic import BaseModel


class PushTokenRegisterInput(BaseModel):
    token: str
    platform: Literal["android", "ios", "web"]


class NotificationSettingsUpdateInput(BaseModel):
    """Both optional (§ streak reminder, 2026-09-15) — toggling one setting
    no longer requires resending the other's current value."""

    autoSendOnNewLesson: bool | None = None
    streakReminderEnabled: bool | None = None
