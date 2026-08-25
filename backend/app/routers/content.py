from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.models.user import User
from app.services.content import get_lesson_content, list_legacy_lessons

# Read-only for any signed-in learner — same function the staff-facing admin
# GET uses (routers/admin.py).
router = APIRouter(prefix="/api/content", tags=["content"])


@router.get("")
async def read_lesson_list(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return {"lessons": await list_legacy_lessons(db)}


@router.get("/{lesson_id}")
async def read_content(lesson_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return {"content": await get_lesson_content(db, lesson_id)}
