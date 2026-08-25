from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_admin, require_staff
from app.auth.hash import hash_password
from app.db import get_db
from app.errors import ApiError
from app.models.enums import Role, UserStatus
from app.models.login_event import LoginEvent
from app.models.user import User
from app.models.vocabulary_item import VocabularyItem
from app.schemas.content import ContentPayload
from app.schemas.user import CreateUserRequest, ResetPasswordRequest, UpdateUserRequest
from app.services import courses as courses_svc
from app.services.content import DuplicateWordError, get_lesson_content, normalize_word, save_lesson_content, set_legacy_lesson_media
from app.services.progress import get_progress_summary_for_user
from app.services.public_id import generate_public_id
from app.services.serialize import with_online_status
from app.services.username import conflict_message, normalize_username
from app.uploads.storage import COURSE_MEDIA_DIR, WORD_AUDIO_DIR, delete_file, save_course_media, save_word_audio
from app.utils import to_iso_z
router = APIRouter(prefix="/api/admin", tags=["admin"])


@router.get("/users")
async def list_users(user: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).order_by(User.createdAt.desc()))
    return {"users": [with_online_status(u) for u in result.scalars().all()]}


@router.post("/users", status_code=201)
async def create_user(
    body: CreateUserRequest,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    username_lower = normalize_username(body.username)
    new_user = User(
        publicId=await generate_public_id(db),
        firstName=body.firstName,
        lastName=body.lastName,
        email=body.email,
        phone=body.phone,
        username=body.username,
        usernameLower=username_lower,
        passwordHash=hash_password(body.password),
        role=body.role,
        canEditProfile=body.canEditProfile,
    )
    db.add(new_user)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise ApiError(409, await conflict_message(db, body.email, username_lower))
    await db.refresh(new_user)
    return {"user": with_online_status(new_user)}


@router.get("/users/{user_id}")
async def get_user(user_id: str, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    target = await db.get(User, user_id)
    if not target:
        raise ApiError(404, "Пользователь не найден")
    return {"user": with_online_status(target)}


@router.patch("/users/{user_id}")
async def update_user(
    user_id: str,
    body: UpdateUserRequest,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    changes = body.model_dump(exclude_unset=True)

    # Locking yourself out is unrecoverable through the UI — an admin who
    # blocks or demotes their own account could only be restored directly in
    # the database, so both are refused here. Any role other than ADMIN
    # counts as a demotion (not just "USER") now that TEACHER also exists.
    is_self = user_id == admin.id
    is_demotion = "role" in changes and changes["role"] != Role.ADMIN
    if is_self and changes.get("status") == UserStatus.BLOCKED:
        raise ApiError(400, "Нельзя заблокировать собственную учётную запись")
    if is_self and is_demotion:
        raise ApiError(400, "Нельзя снять с себя роль администратора")

    # Likewise, the platform must never be left without a working admin.
    if not is_self and (changes.get("status") == UserStatus.BLOCKED or is_demotion):
        target = await db.get(User, user_id)
        if target and target.role == Role.ADMIN and target.status == UserStatus.ACTIVE:
            active_admins = await db.scalar(
                select(func.count()).select_from(User).where(User.role == Role.ADMIN, User.status == UserStatus.ACTIVE)
            )
            if active_admins is not None and active_admins <= 1:
                raise ApiError(400, "Это последний активный администратор — действие отменено")

    target = await db.get(User, user_id)
    if not target:
        raise ApiError(404, "Пользователь не найден")

    username_lower = normalize_username(changes["username"]) if "username" in changes else None
    for field, value in changes.items():
        setattr(target, field, value)
    if username_lower is not None:
        target.usernameLower = username_lower

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise ApiError(409, await conflict_message(db, changes.get("email"), username_lower, user_id))
    await db.refresh(target)
    return {"user": with_online_status(target)}


@router.post("/users/{user_id}/reset-password")
async def reset_password(
    user_id: str,
    body: ResetPasswordRequest,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    target = await db.get(User, user_id)
    if not target:
        raise ApiError(404, "Пользователь не найден")
    target.passwordHash = hash_password(body.newPassword)
    await db.commit()
    return {"ok": True}


@router.get("/users/{user_id}/progress")
async def user_progress(user_id: str, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    target = await db.get(User, user_id)
    if not target:
        raise ApiError(404, "Пользователь не найден")
    return {"progress": await get_progress_summary_for_user(db, user_id)}


# Newest-first login history — capped at 50 so a long-lived account's page
# never has to render an unbounded list.
@router.get("/users/{user_id}/logins")
async def user_logins(user_id: str, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    target = await db.get(User, user_id)
    if not target:
        raise ApiError(404, "Пользователь не найден")
    result = await db.execute(
        select(LoginEvent).where(LoginEvent.userId == user_id).order_by(LoginEvent.createdAt.desc()).limit(50)
    )
    return {"logins": [{"id": e.id, "createdAt": to_iso_z(e.createdAt)} for e in result.scalars().all()]}


# ---------------------------------------------------------------------------
# Course content editing. requireStaff (ADMIN or TEACHER) rather than
# requireAdmin — a TEACHER has full access to lesson content, just not to
# user management above.
# ---------------------------------------------------------------------------


@router.get("/content/{lesson_id}")
async def get_content(lesson_id: str, user: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    return {"content": await get_lesson_content(db, lesson_id)}


@router.put("/content/{lesson_id}")
async def put_content(
    lesson_id: str,
    body: ContentPayload,
    user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    try:
        content = await save_lesson_content(db, lesson_id, body, user.id, body.model_fields_set)
    except DuplicateWordError as e:
        raise ApiError(409, str(e))
    return {"content": content}


# ---- Video/audio override for a legacy lesson ------------------------------
# Null means "use the bundled file" — same override-if-present pattern as
# materialText/vocabulary above.


@router.post("/content/{lesson_id}/media")
async def upload_legacy_media(
    lesson_id: str,
    kind: str = Form(...),
    file: UploadFile = File(...),
    user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    if kind not in ("video", "audio"):
        raise ApiError(400, "Укажите тип файла: video или audio")
    existing = await get_lesson_content(db, lesson_id)
    previous_url = existing["videoUrl"] if kind == "video" else existing["audioUrl"]

    filename = await save_course_media(file)
    content = await set_legacy_lesson_media(db, lesson_id, kind, f"/uploads/courses/{filename}")
    # Only delete the old file if no other lesson reuses it.
    if previous_url and not await courses_svc.media_url_still_in_use(db, previous_url, legacy_lesson_id=lesson_id):
        delete_file(COURSE_MEDIA_DIR, previous_url)
    return {"content": content}


@router.put("/content/{lesson_id}/media/reuse")
async def reuse_legacy_media(
    lesson_id: str,
    body: dict,
    user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    kind = body.get("kind")
    if kind not in ("video", "audio"):
        raise ApiError(400, "Укажите тип файла: video или audio")
    url = str(body.get("url") or "")
    library = await courses_svc.list_media_library(db, kind)
    if not any(entry["url"] == url for entry in library):
        raise ApiError(400, "Файл не найден в библиотеке")
    content = await set_legacy_lesson_media(db, lesson_id, kind, url)
    return {"content": content}


@router.delete("/content/{lesson_id}/media")
async def delete_legacy_media(
    lesson_id: str,
    kind: str = Query(...),
    user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    if kind not in ("video", "audio"):
        raise ApiError(400, "Укажите тип файла: video или audio")
    existing = await get_lesson_content(db, lesson_id)
    previous_url = existing["videoUrl"] if kind == "video" else existing["audioUrl"]
    if previous_url and not await courses_svc.media_url_still_in_use(db, previous_url, legacy_lesson_id=lesson_id):
        delete_file(COURSE_MEDIA_DIR, previous_url)
    content = await set_legacy_lesson_media(db, lesson_id, kind, None)
    return {"content": content}


# ---- Recorded pronunciation for a single word -----------------------------


async def _find_word(db: AsyncSession, lesson_id: str, german: str) -> VocabularyItem | None:
    """Locates a word by its normalized form, so casing/punctuation don't
    matter."""
    result = await db.execute(select(VocabularyItem).where(VocabularyItem.lessonId == lesson_id, VocabularyItem.germanKey == normalize_word(german)))
    return result.scalar_one_or_none()


@router.post("/content/{lesson_id}/word-audio")
async def upload_word_audio(
    lesson_id: str,
    german: str = Form(""),
    audio: UploadFile = File(...),
    user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    if not german:
        raise ApiError(400, "Не указано слово")
    word = await _find_word(db, lesson_id, german)
    if not word:
        raise ApiError(404, "Слово не найдено — сначала сохраните словарь")

    filename = await save_word_audio(audio)
    if word.audioUrl:
        delete_file(WORD_AUDIO_DIR, word.audioUrl)
    word.audioUrl = f"/uploads/words/{filename}"
    await db.commit()
    return {"german": word.german, "audioUrl": word.audioUrl}


@router.delete("/content/{lesson_id}/word-audio")
async def delete_word_audio(
    lesson_id: str,
    german: str = "",
    user: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    if not german:
        raise ApiError(400, "Не указано слово")
    word = await _find_word(db, lesson_id, german)
    if not word:
        raise ApiError(404, "Слово не найдено")
    if word.audioUrl:
        delete_file(WORD_AUDIO_DIR, word.audioUrl)
    word.audioUrl = None
    await db.commit()
    return {"german": word.german, "audioUrl": None}
