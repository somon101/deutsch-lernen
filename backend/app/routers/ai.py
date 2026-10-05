from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_admin, require_staff
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.schemas.ai import AiApplyInput, AiFillInput, AiPreviewInput, AiSettingsUpdateInput
from app.services import ai_client, ai_fill, ai_lessons, ai_settings

# Admin-only: the key costs money and is the platform's, not a teacher's.
settings_router = APIRouter(prefix="/api/admin/ai-settings", tags=["ai"])
# Staff: any teacher may generate once the admin has configured a key.
router = APIRouter(prefix="/api/builder", tags=["ai"], dependencies=[Depends(require_staff)])


@settings_router.get("")
async def get_settings(admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    return {"settings": ai_settings.settings_dto(await ai_settings.get_ai_settings(db))}


@settings_router.patch("")
async def update_settings(body: AiSettingsUpdateInput, admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    row = await ai_settings.update_ai_settings(db, api_key=body.apiKey, model=body.model, system_prompt=body.systemPrompt)
    return {"settings": ai_settings.settings_dto(row)}


@settings_router.post("/test")
async def test_connection(admin: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    api_key, model = await ai_settings.get_api_key(db)
    if not api_key:
        raise ApiError(400, "Сначала сохраните API-ключ")
    reply = await ai_client.chat_json(api_key, model, 'Answer with JSON: {"ok": true}', "ping", max_tokens=20)
    return {"ok": bool(reply.get("ok", True))}


@router.post("/courses/{course_id}/ai/preview")
async def preview_lesson(course_id: str, body: AiPreviewInput, db: AsyncSession = Depends(get_db)):
    return await ai_lessons.preview_lesson(db, course_id, instructions=body.instructions, previous=body.previous)


@router.post("/courses/{course_id}/ai/apply")
async def apply_lessons(course_id: str, body: AiApplyInput, db: AsyncSession = Depends(get_db)):
    return await ai_lessons.apply_plans(db, course_id, body.lessons)


@router.post("/courses/{course_id}/lessons/{lesson_id}/ai/fill")
async def fill_lesson(course_id: str, lesson_id: str, body: AiFillInput, db: AsyncSession = Depends(get_db)):
    return await ai_fill.fill_lesson(db, course_id, lesson_id, instructions=body.instructions)
