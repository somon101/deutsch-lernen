"""Generic push-notification mechanism (PushToken/Notification/
NotificationSettings — see schema.prisma's comment above those models).
Today only one event type is wired up (lesson_created, from
courses.create_lesson); a future event calls send_notification() with a new
`type` and reuses everything here unchanged.

Firebase Cloud Messaging is called directly over HTTP (v1 API) using a
hand-rolled service-account JWT exchange — pyjwt and httpx are already
project dependencies, so this needed no new one. When
settings.push_enabled is False (no Firebase project configured yet), sending
is a safe no-op: the Notification row is still written, so the admin UI and
"resend" history work the same either way, nothing is ever delivered.
"""

import time
import uuid
from datetime import datetime

import httpx
import jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.notification import Notification
from app.models.notification_settings import NotificationSettings
from app.models.push_token import PushToken
from app.utils import to_iso_z, utcnow

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_TOKEN_URL = "https://oauth2.googleapis.com/token"

# Cached in-process between calls — a fresh JWT/access-token exchange for
# every single push would be wasteful; refreshed a minute before actual
# expiry to stay safely inside FCM's window.
_cached_access_token: str | None = None
_cached_access_token_expires_at: float = 0.0


def _notification_dto(n: Notification) -> dict:
    return {
        "id": n.id,
        "type": n.type,
        "title": n.title,
        "body": n.body,
        "deepLink": n.deepLink,
        "courseId": n.courseId,
        "lessonId": n.lessonId,
        "createdAt": to_iso_z(n.createdAt),
    }


async def get_settings(db: AsyncSession) -> NotificationSettings:
    row = await db.get(NotificationSettings, "singleton")
    if row is None:
        # Belt-and-braces — the migration seeds this row, but a
        # get-or-create here means a future dev database that only ran
        # `create_all` (no migration history) still works.
        row = NotificationSettings(id="singleton")
        db.add(row)
        await db.commit()
        await db.refresh(row)
    return row


async def set_auto_send_on_new_lesson(db: AsyncSession, enabled: bool) -> NotificationSettings:
    row = await get_settings(db)
    row.autoSendOnNewLesson = enabled
    await db.commit()
    await db.refresh(row)
    return row


async def register_token(db: AsyncSession, user_id: str, token: str, platform: str) -> None:
    existing = (await db.execute(select(PushToken).where(PushToken.token == token))).scalar_one_or_none()
    if existing:
        existing.userId = user_id
        existing.platform = platform
        existing.updatedAt = utcnow()
    else:
        db.add(PushToken(id=str(uuid.uuid4()), userId=user_id, token=token, platform=platform))
    await db.commit()


async def list_recent_notifications(db: AsyncSession, limit: int = 50) -> list[dict]:
    rows = (await db.execute(select(Notification).order_by(Notification.createdAt.desc()).limit(limit))).scalars().all()
    return [_notification_dto(n) for n in rows]


async def _get_fcm_access_token() -> str | None:
    """Exchanges the service-account key for a short-lived OAuth2 access
    token (RFC 7523 JWT bearer flow) — this is what google-auth's own
    Credentials.refresh() does internally; done by hand here since the
    project doesn't otherwise depend on google-auth."""
    global _cached_access_token, _cached_access_token_expires_at
    if _cached_access_token and time.time() < _cached_access_token_expires_at - 60:
        return _cached_access_token

    import json

    try:
        key_info = json.loads(settings.firebase_service_account_json)
    except (json.JSONDecodeError, TypeError):
        print("Push: firebase_service_account_json is not valid JSON — skipping send.")
        return None

    now = int(time.time())
    claims = {
        "iss": key_info["client_email"],
        "scope": _FCM_SCOPE,
        "aud": _TOKEN_URL,
        "iat": now,
        "exp": now + 3600,
    }
    assertion = jwt.encode(claims, key_info["private_key"], algorithm="RS256")

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            _TOKEN_URL,
            data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
        )
    if response.status_code != 200:
        print(f"Push: token exchange failed: {response.status_code} {response.text}")
        return None

    body = response.json()
    _cached_access_token = body["access_token"]
    _cached_access_token_expires_at = time.time() + body.get("expires_in", 3600)
    return _cached_access_token


async def _send_to_token(client: httpx.AsyncClient, access_token: str, token: str, title: str, body: str, deep_link: str | None) -> bool:
    url = f"https://fcm.googleapis.com/v1/projects/{settings.firebase_project_id}/messages:send"
    payload = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "data": {"deepLink": deep_link or ""},
        }
    }
    try:
        response = await client.post(url, json=payload, headers={"Authorization": f"Bearer {access_token}"})
    except httpx.HTTPError as exc:
        print(f"Push: request to FCM failed for a token: {exc!r}")
        return False
    if response.status_code == 200:
        return True
    # 404/NOT_FOUND and 400/INVALID_ARGUMENT (UNREGISTERED) both mean the
    # token is dead — the device uninstalled the app or its token rotated.
    # Never fatal to the caller; just noise-reduced logging.
    print(f"Push: FCM rejected a token ({response.status_code}): {response.text[:200]}")
    return False


async def send_notification(
    db: AsyncSession,
    *,
    type: str,
    title: str,
    body: str,
    deep_link: str | None = None,
    course_id: str | None = None,
    lesson_id: str | None = None,
    created_by_id: str | None = None,
) -> dict:
    """Records the notification and — if a Firebase project is configured —
    delivers it to every currently-registered device. Always returns the
    saved Notification row; delivery failures (missing config, a dead
    token, FCM being briefly unreachable) never raise, so this is always
    safe to call from another operation (e.g. lesson creation) without risk
    of breaking it."""
    record = Notification(
        id=str(uuid.uuid4()),
        type=type,
        title=title,
        body=body,
        deepLink=deep_link,
        courseId=course_id,
        lessonId=lesson_id,
        createdById=created_by_id,
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)

    if not settings.push_enabled:
        return _notification_dto(record)

    tokens = (await db.execute(select(PushToken.token))).scalars().all()
    if not tokens:
        return _notification_dto(record)

    try:
        access_token = await _get_fcm_access_token()
        if not access_token:
            return _notification_dto(record)
        async with httpx.AsyncClient(timeout=30.0) as client:
            for device_token in tokens:
                await _send_to_token(client, access_token, device_token, title, body, deep_link)
    except Exception as exc:  # noqa: BLE001 — a push failure must never bubble up
        print(f"Push: send_notification failed: {exc!r}")

    return _notification_dto(record)


async def send_push_to_user(db: AsyncSession, *, user_id: str, title: str, body: str, deep_link: str | None = None) -> bool:
    """An ad-hoc push straight to one user's registered device(s), with NO
    Notification row written (§ individual push, 2026-08-30) — for one-off
    messages (an admin messaging one user, a system task-completion alert)
    that were never meant to be part of the broadcast notification history
    send_notification() keeps. Reuses the exact same FCM delivery path
    (_get_fcm_access_token/_send_to_token) as send_notification; only who
    it's sent to and whether it's recorded differ — deliberately generic on
    `user_id`/`title`/`body`/`deep_link` so any future individual-push
    scenario is just another call to this same function, not a new
    mechanism.

    Returns True if at least one of the user's devices was delivered to
    (False on no push config, no registered device, or every send failing)
    — never raises, same "a push failure must never break the caller"
    contract as send_notification."""
    if not settings.push_enabled:
        return False
    tokens = (await db.execute(select(PushToken.token).where(PushToken.userId == user_id))).scalars().all()
    if not tokens:
        return False
    try:
        access_token = await _get_fcm_access_token()
        if not access_token:
            return False
        delivered = False
        async with httpx.AsyncClient(timeout=30.0) as client:
            for device_token in tokens:
                ok = await _send_to_token(client, access_token, device_token, title, body, deep_link)
                delivered = delivered or ok
        return delivered
    except Exception as exc:  # noqa: BLE001 — a push failure must never bubble up
        print(f"Push: send_push_to_user failed: {exc!r}")
        return False


async def notify_lesson_created(db: AsyncSession, *, course_id: str, course_title: str, lesson_id: str, lesson_title: str, created_by_id: str | None) -> dict:
    """The one event wired up today — called either automatically (from
    courses.create_lesson, gated on the settings toggle) or via the admin's
    manual "Отправить уведомление" button, which always sends regardless of
    the toggle."""
    return await send_notification(
        db,
        type="lesson_created",
        title="Новый урок",
        body=f"«{lesson_title}» — курс «{course_title}»",
        deep_link=f"/courses/{course_id}/lesson/{lesson_id}/vocabulary",
        course_id=course_id,
        lesson_id=lesson_id,
        created_by_id=created_by_id,
    )
