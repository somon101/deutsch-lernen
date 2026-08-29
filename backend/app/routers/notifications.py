from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth, require_staff
from app.db import get_db
from app.models.user import User
from app.schemas.notifications import NotificationSettingsUpdateInput, PushTokenRegisterInput
from app.services import push as svc

router = APIRouter(prefix="/api", tags=["notifications"])


@router.post("/me/push-token", status_code=201)
async def register_push_token(body: PushTokenRegisterInput, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    await svc.register_token(db, user.id, body.token, body.platform)
    return {"ok": True}


@router.get("/admin/notification-settings")
async def get_notification_settings(admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    row = await svc.get_settings(db)
    return {"settings": {"autoSendOnNewLesson": row.autoSendOnNewLesson}}


@router.patch("/admin/notification-settings")
async def update_notification_settings(body: NotificationSettingsUpdateInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    row = await svc.set_auto_send_on_new_lesson(db, body.autoSendOnNewLesson)
    return {"settings": {"autoSendOnNewLesson": row.autoSendOnNewLesson}}


@router.get("/admin/notifications")
async def list_notifications(admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    return {"notifications": await svc.list_recent_notifications(db)}
