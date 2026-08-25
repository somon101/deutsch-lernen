from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.auth.hash import hash_password, verify_password
from app.db import get_db
from app.errors import ApiError
from app.models.lesson_state import LessonAttempt, LessonState
from app.models.user import User
from app.schemas.lesson_state import AttemptRequest, LessonStateRequest
from app.schemas.user import ChangePasswordRequest, UpdateProfileRequest
from app.services.lesson_state import to_dto
from app.services.progress import AttemptInput, compute_score, get_progress_summary_for_user
from app.services.serialize import public_user
from app.services.username import conflict_message, normalize_username
from app.uploads.storage import AVATARS_DIR, delete_file, save_avatar
from app.utils import from_iso, utcnow

router = APIRouter(prefix="/api/me", tags=["me"])


@router.get("/")
async def get_me(user: User = Depends(require_auth)):
    return {"user": public_user(user)}


@router.patch("/")
async def update_me(
    body: UpdateProfileRequest,
    user: User = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
):
    # Server-side enforcement of the admin-controlled edit permission — not
    # just hidden on the frontend.
    if not user.canEditProfile:
        raise ApiError(403, "Редактирование профиля отключено администратором")

    changes = body.model_dump(exclude_unset=True)
    username_lower = normalize_username(changes["username"]) if "username" in changes else None
    if "birthDate" in changes:
        changes["birthDate"] = from_iso(changes["birthDate"])
    for field, value in changes.items():
        setattr(user, field, value)
    if username_lower is not None:
        user.usernameLower = username_lower

    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise ApiError(409, await conflict_message(db, changes.get("email"), username_lower, user.id))
    await db.refresh(user)
    return {"user": public_user(user)}


@router.patch("/password")
async def change_password(
    body: ChangePasswordRequest,
    user: User = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
):
    if not verify_password(body.currentPassword, user.passwordHash):
        raise ApiError(400, "Неверный текущий пароль")
    user.passwordHash = hash_password(body.newPassword)
    await db.commit()
    return {"ok": True}


@router.post("/avatar")
async def upload_avatar(
    avatar: UploadFile = File(...),
    user: User = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
):
    filename = await save_avatar(avatar)
    previous_url = user.avatarUrl
    user.avatarUrl = f"/uploads/avatars/{filename}"
    await db.commit()
    await db.refresh(user)
    if previous_url:
        delete_file(AVATARS_DIR, previous_url)
    return {"user": public_user(user)}


@router.delete("/avatar")
async def delete_avatar(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    if user.avatarUrl:
        delete_file(AVATARS_DIR, user.avatarUrl)
    user.avatarUrl = None
    await db.commit()
    await db.refresh(user)
    return {"user": public_user(user)}


@router.get("/progress")
async def get_progress(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    summary = await get_progress_summary_for_user(db, user.id)
    return {"progress": summary}


@router.get("/lesson-state")
async def get_lesson_states(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(LessonState).where(LessonState.userId == user.id))
    return {"states": [to_dto(s) for s in result.scalars().all()]}


@router.put("/lesson-state/{lesson_id}")
async def put_lesson_state(
    lesson_id: str,
    body: LessonStateRequest,
    user: User = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(LessonState).where(LessonState.userId == user.id, LessonState.lessonId == lesson_id))
    state = result.scalar_one_or_none()

    values = dict(
        completedStages=list(body.completedStages),
        vocabIndex=body.vocabIndex,
        miniTestCorrect=body.miniTestResult.correct if body.miniTestResult else None,
        miniTestTotal=body.miniTestResult.total if body.miniTestResult else None,
        miniTestAt=from_iso(body.miniTestResult.completedAt) if body.miniTestResult else None,
        practiceCorrect=body.practiceResult.correct if body.practiceResult else None,
        practiceTotal=body.practiceResult.total if body.practiceResult else None,
        practiceAt=from_iso(body.practiceResult.completedAt) if body.practiceResult else None,
        reviewCorrect=body.reviewResult.correct if body.reviewResult else None,
        reviewTotal=body.reviewResult.total if body.reviewResult else None,
        reviewAt=from_iso(body.reviewResult.completedAt) if body.reviewResult else None,
        completedAt=from_iso(body.completedAt),
    )

    if state is None:
        # Always scoped to the authenticated user's id — a client cannot
        # write into someone else's lesson state.
        state = LessonState(
            userId=user.id,
            lessonId=lesson_id,
            startedAt=from_iso(body.startedAt) or utcnow(),
            **values,
        )
        db.add(state)
    else:
        for field, value in values.items():
            setattr(state, field, value)

    await db.commit()
    await db.refresh(state)
    return {"state": to_dto(state)}


@router.post("/progress/{lesson_id}/attempts", status_code=201)
async def post_attempt(
    lesson_id: str,
    body: AttemptRequest,
    user: User = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
):
    score = compute_score(AttemptInput(**body.model_dump()))
    db.add(LessonAttempt(userId=user.id, lessonId=lesson_id, score=score, **body.model_dump()))
    await db.commit()

    summary = await get_progress_summary_for_user(db, user.id)
    entry = next((s for s in summary if s["lessonId"] == lesson_id), None)
    return {"progress": entry}
