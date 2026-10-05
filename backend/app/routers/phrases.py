from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_staff
from app.db import get_db
from app.errors import ApiError
from app.schemas.phrase import PhraseImportPayload, PhraseInput, PhraseUpdateInput
from app.services import phrases as svc

router = APIRouter(prefix="/api/builder/phrases", tags=["phrases"], dependencies=[Depends(require_staff)])


@router.get("")
async def list_phrases(
    languageId: str | None = None, q: str | None = None, used: bool | None = None, limit: int = 50, offset: int = 0, db: AsyncSession = Depends(get_db)
):
    return await svc.list_phrases(db, language_id=languageId, query=q, limit=max(1, min(limit, 200)), offset=max(0, offset), used=used)


@router.post("", status_code=201)
async def create_phrase(body: PhraseInput, db: AsyncSession = Depends(get_db)):
    phrase = await svc.create_phrase(
        db, language_id=body.languageId, text=body.text, translation=body.translation, translations=body.translations, topic_id=body.topicId
    )
    return {"phrase": phrase}


@router.patch("/{phrase_id}")
async def update_phrase(phrase_id: str, body: PhraseUpdateInput, db: AsyncSession = Depends(get_db)):
    phrase = await svc.update_phrase(db, phrase_id, body.model_dump(exclude_unset=True))
    if not phrase:
        raise ApiError(404, "Фраза не найдена")
    return {"phrase": phrase}


@router.delete("/{phrase_id}")
async def delete_phrase(phrase_id: str, db: AsyncSession = Depends(get_db)):
    if not await svc.delete_phrase(db, phrase_id):
        raise ApiError(404, "Фраза не найдена")
    return {"ok": True}


@router.post("/import")
async def import_phrases(body: PhraseImportPayload, db: AsyncSession = Depends(get_db)):
    return await svc.import_phrases(db, body.languageId, [p.model_dump() for p in body.phrases])
