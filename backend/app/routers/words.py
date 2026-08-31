from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.services.vocabulary import get_word, get_words

router = APIRouter(prefix="/api/words", tags=["words"])


@router.get("/")
async def get_words_route(
    ids: str = Query(..., description="Comma-separated wordId list"),
    user: User = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
):
    """The universal batch access point (§8/§9, § word cards, 2026-08-31) —
    any future feature (an exercise generator picking random learned words,
    for instance) gets full card data for as many wordIds as it needs in
    one call, one query, regardless of how many ids are asked for."""
    word_ids = [i.strip() for i in ids.split(",") if i.strip()]
    return {"words": await get_words(db, word_ids)}


@router.get("/{word_id}")
async def get_word_route(word_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """The universal single-word access point (§8, § word cards,
    2026-08-31) — wordId in, the full card (word/translation/pronunciation/
    audio/image/category/language) out."""
    word = await get_word(db, word_id)
    if not word:
        raise ApiError(404, "Слово не найдено")
    return word
