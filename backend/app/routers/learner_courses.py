from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.services import courses as svc

router = APIRouter(prefix="/api/courses", tags=["learner-courses"], dependencies=[Depends(require_auth)])


@router.get("/")
async def list_published_courses(db: AsyncSession = Depends(get_db)):
    all_courses = await svc.list_courses(db)
    return {"courses": [c for c in all_courses if c["status"] == "PUBLISHED"]}


@router.get("/{course_id}")
async def get_published_course(course_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    # 404 if the course is missing OR not published — drafts are
    # indistinguishable from nonexistent to a learner, even by guessed id.
    course = await svc.get_course(db, course_id)
    if not course or course["status"] != "PUBLISHED":
        raise ApiError(404, "Курс не найден")
    return {"course": course}


@router.get("/{course_id}/version")
async def get_published_course_version(course_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """Cheap cache-busting check (frontend caching plan, 2026-08-29) — lets
    the app confirm "is my cached copy of this course still current?"
    without downloading the whole course again. Same not-found rule as the
    full fetch: a draft course's version isn't distinguishable from a
    nonexistent one."""
    course = await svc.get_course(db, course_id)
    if not course or course["status"] != "PUBLISHED":
        raise ApiError(404, "Курс не найден")
    return {"version": await svc.get_course_version(db, course_id)}
