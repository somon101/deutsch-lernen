from typing import Literal

from pydantic import BaseModel


class PushTokenRegisterInput(BaseModel):
    token: str
    platform: Literal["android", "ios", "web"]


class NotificationSettingsUpdateInput(BaseModel):
    autoSendOnNewLesson: bool
