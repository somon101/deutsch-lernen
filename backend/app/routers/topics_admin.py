from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_staff
from app.db import get_db
from app.errors import ApiError
from app.services import topics_admin as svc

router = APIRouter(prefix="/api/builder/topics", tags=["topics"], dependencies=[Depends(require_staff)])


class _Strict(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)


class TopicCreate(_Strict):
    languageId: str
    name: str = Field(min_length=1, max_length=200)


class TopicRename(_Strict):
    name: str = Field(min_length=1, max_length=200)


class TopicImportItem(_Strict):
    name: str = Field(min_length=1, max_length=200)


class TopicImport(BaseModel):
    languageId: str
    topics: list[TopicImportItem] = Field(min_length=1, max_length=5000)


@router.get("")
async def list_topics(
    languageId: str | None = None, q: str | None = None, used: bool | None = None, limit: int = 50, offset: int = 0, db: AsyncSession = Depends(get_db)
):
    return await svc.list_topics_page(db, language_id=languageId, query=q, limit=max(1, min(limit, 200)), offset=max(0, offset), used=used)


@router.post("", status_code=201)
async def create_topic(body: TopicCreate, db: AsyncSession = Depends(get_db)):
    return {"topic": await svc.create_topic(db, body.languageId, body.name)}


@router.patch("/{topic_id}")
async def rename_topic(topic_id: str, body: TopicRename, db: AsyncSession = Depends(get_db)):
    topic = await svc.rename_topic(db, topic_id, body.name)
    if not topic:
        raise ApiError(404, "Тема не найдена")
    return {"topic": topic}


@router.delete("/{topic_id}")
async def delete_topic(topic_id: str, db: AsyncSession = Depends(get_db)):
    if not await svc.delete_topic(db, topic_id):
        raise ApiError(404, "Тема не найдена")
    return {"ok": True}


@router.post("/import")
async def import_topics(body: TopicImport, db: AsyncSession = Depends(get_db)):
    return await svc.import_topics(db, body.languageId, [t.name for t in body.topics])
