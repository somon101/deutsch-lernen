"""Public API for external programs: words, phrases and rules of the ONE
language an API key belongs to. Auth: header `X-API-Key`. Anything with an
id from another language answers 404, exactly like a missing id."""

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.errors import ApiError
from app.models.api_key import ApiKey
from app.models.phrase import Phrase
from app.models.rule import Rule
from app.models.vocabulary_item import VocabularyItem
from app.models.vocabulary_translation import VocabularyTranslation
from app.schemas.phrase import PhraseImportItem
from app.schemas.rule import RuleImportItem
from app.schemas.vocabulary import VocabularyImportWordInput
from app.services import courses as courses_svc
from app.services import phrases as phrases_svc
from app.services import rules as rules_svc
from app.services.api_keys import require_api_key
from app.services.content import DuplicateWordError
from app.services.vocabulary import delete_word_globally, list_dictionary_words

router = APIRouter(prefix="/api/v1", tags=["public-api"])


class _Strict(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)


class WordCreate(_Strict):
    word: str = Field(min_length=1)
    translation: str = Field(min_length=1)
    translation_tg: str = Field(min_length=1)
    transcription: str = ""
    category: str | None = None


class WordUpdate(_Strict):
    word: str | None = Field(default=None, min_length=1)
    translation: str | None = Field(default=None, min_length=1)
    translation_tg: str | None = Field(default=None, min_length=1)
    transcription: str | None = None
    category: str | None = None


class PhraseCreate(_Strict):
    text: str = Field(min_length=1, max_length=500)
    translation: str = Field(min_length=1, max_length=1000)
    translation_tg: str = Field(min_length=1, max_length=1000)
    topic: str | None = Field(default=None, max_length=100)


class PhraseUpdate(_Strict):
    text: str | None = Field(default=None, min_length=1, max_length=500)
    translation: str | None = Field(default=None, min_length=1, max_length=1000)
    translation_tg: str | None = Field(default=None, min_length=1, max_length=1000)
    topic: str | None = Field(default=None, max_length=100)


class RuleBody(_Strict):
    text: str = Field(min_length=1, max_length=2000)


class WordsImport(BaseModel):
    words: list[VocabularyImportWordInput] = Field(min_length=1, max_length=5000)


class PhrasesImport(BaseModel):
    phrases: list[PhraseImportItem] = Field(min_length=1, max_length=5000)


class RulesImport(BaseModel):
    rules: list[RuleImportItem] = Field(min_length=1, max_length=5000)


def _limit(limit: int) -> int:
    return max(1, min(limit, 500))


# ---------------------------------------------------------------- language


@router.get("/language")
async def whoami(key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    from app.models.language import Language

    language = await db.get(Language, key.languageId)
    return {"language": {"id": key.languageId, "name": language.name if language else None}, "key": key.name}


# ------------------------------------------------------------------- words


def _word_out(w: dict) -> dict:
    return {
        "id": w["wordId"],
        "word": w["word"],
        "translation": w["translation"],
        "translation_tg": w.get("translationTg"),
        "transcription": w.get("pronunciation"),
        "category": w.get("categoryName"),
        "imageUrl": w.get("imageUrl"),
        "audioUrl": w.get("audioUrl"),
    }


async def _own_word(db: AsyncSession, key: ApiKey, word_id: str) -> VocabularyItem:
    word = await db.get(VocabularyItem, word_id)
    if not word or word.languageId != key.languageId:
        raise ApiError(404, "Слово не найдено")
    return word


async def _word_dto(db: AsyncSession, word: VocabularyItem) -> dict:
    tg = await db.scalar(
        select(VocabularyTranslation.translation).where(VocabularyTranslation.vocabularyItemId == word.id, VocabularyTranslation.locale == "tg")
    )
    page = await list_dictionary_words(db, query=word.german, language_id=word.languageId, limit=200)
    for w in page["words"]:
        if w["wordId"] == word.id:
            return _word_out(w)
    return {"id": word.id, "word": word.german, "translation": word.translation, "translation_tg": tg, "transcription": word.pronunciation}


@router.get("/words")
async def list_words(q: str | None = None, limit: int = 100, offset: int = Query(0, ge=0), key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    page = await list_dictionary_words(db, query=q, language_id=key.languageId, limit=_limit(limit), offset=offset)
    return {"words": [_word_out(w) for w in page["words"]], "total": page["total"]}


@router.get("/words/{word_id}")
async def get_word(word_id: str, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    return {"word": await _word_dto(db, await _own_word(db, key, word_id))}


@router.post("/words", status_code=201)
async def create_word(body: WordCreate, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    try:
        created = await courses_svc.add_dictionary_word(
            db,
            language_id=key.languageId,
            german=body.word,
            translation=body.translation,
            translation_tg=body.translation_tg,
            pronunciation=body.transcription,
            category_name=body.category,
        )
    except DuplicateWordError as e:
        raise ApiError(409, str(e))
    return {"word": await _word_dto(db, await db.get(VocabularyItem, created["id"]))}


@router.patch("/words/{word_id}")
async def update_word(word_id: str, body: WordUpdate, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    word = await _own_word(db, key, word_id)
    changes = {
        "german": body.word,
        "translation": body.translation,
        "pronunciation": body.transcription,
        "categoryName": body.category,
    }
    try:
        await courses_svc.update_vocabulary_word(db, word.courseId, word.lessonId, word.id, {k: v for k, v in changes.items() if v is not None})
    except DuplicateWordError as e:
        raise ApiError(409, str(e))
    if body.translation_tg is not None:
        await courses_svc.set_vocabulary_translation(db, word.courseId, word.lessonId, word.id, "tg", body.translation_tg)
    await db.refresh(word)
    return {"word": await _word_dto(db, word)}


@router.delete("/words/{word_id}")
async def delete_word(word_id: str, force: bool = False, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    await _own_word(db, key, word_id)
    result = await delete_word_globally(db, word_id, force=force)
    if not result["ok"]:
        if result["reason"] == "not_found":
            raise ApiError(404, "Слово не найдено")
        usage = result["usage"]
        raise ApiError(
            409,
            f"Слово используется: уроков {len(usage['linkedLessons']) + 1}, учеников {usage['learnerCount']}. "
            "Чтобы удалить всё равно, повторите запрос с ?force=true",
        )
    return {"ok": True}


@router.post("/words/import")
async def import_words(body: WordsImport, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    try:
        return await courses_svc.import_dictionary_words(db, key.languageId, [w.model_dump() for w in body.words])
    except DuplicateWordError as e:
        raise ApiError(409, str(e))


# ----------------------------------------------------------------- phrases


def _phrase_out(p: dict) -> dict:
    return {
        "id": p["id"],
        "text": p["text"],
        "translation": p["translation"],
        "translation_tg": (p.get("translations") or {}).get("tg"),
        "topic": p.get("topicName"),
    }


async def _own_phrase(db: AsyncSession, key: ApiKey, phrase_id: str) -> Phrase:
    phrase = await db.get(Phrase, phrase_id)
    if not phrase or phrase.languageId != key.languageId:
        raise ApiError(404, "Фраза не найдена")
    return phrase


@router.get("/phrases")
async def list_phrases(q: str | None = None, limit: int = 100, offset: int = Query(0, ge=0), key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    page = await phrases_svc.list_phrases(db, language_id=key.languageId, query=q, limit=_limit(limit), offset=offset)
    return {"phrases": [_phrase_out(p) for p in page["phrases"]], "total": page["total"]}


@router.get("/phrases/{phrase_id}")
async def get_phrase(phrase_id: str, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    phrase = await _own_phrase(db, key, phrase_id)
    return {"phrase": _phrase_out((await phrases_svc._dtos(db, [phrase]))[0])}


@router.post("/phrases", status_code=201)
async def create_phrase(body: PhraseCreate, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    topic_id = await phrases_svc.topic_id_for_name(db, key.languageId, body.topic)
    dto = await phrases_svc.create_phrase(
        db, language_id=key.languageId, text=body.text, translation=body.translation, translations={"tg": body.translation_tg}, topic_id=topic_id
    )
    return {"phrase": _phrase_out(dto)}


@router.patch("/phrases/{phrase_id}")
async def update_phrase(phrase_id: str, body: PhraseUpdate, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    await _own_phrase(db, key, phrase_id)
    changes: dict = {}
    if body.text is not None:
        changes["text"] = body.text
    if body.translation is not None:
        changes["translation"] = body.translation
    if body.translation_tg is not None:
        changes["translations"] = {"tg": body.translation_tg}
    if body.topic is not None:
        changes["topicId"] = await phrases_svc.topic_id_for_name(db, key.languageId, body.topic)
    dto = await phrases_svc.update_phrase(db, phrase_id, changes)
    return {"phrase": _phrase_out(dto)}


@router.delete("/phrases/{phrase_id}")
async def delete_phrase(phrase_id: str, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    await _own_phrase(db, key, phrase_id)
    await phrases_svc.delete_phrase(db, phrase_id)
    return {"ok": True}


@router.post("/phrases/import")
async def import_phrases(body: PhrasesImport, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    return await phrases_svc.import_phrases(db, key.languageId, [p.model_dump() for p in body.phrases])


# ------------------------------------------------------------------- rules


async def _own_rule(db: AsyncSession, key: ApiKey, rule_id: str) -> Rule:
    rule = await db.get(Rule, rule_id)
    if not rule or rule.languageId != key.languageId:
        raise ApiError(404, "Правило не найдено")
    return rule


def _rule_out(r: dict) -> dict:
    return {"id": r["id"], "text": r["text"]}


@router.get("/rules")
async def list_rules(q: str | None = None, limit: int = 100, offset: int = Query(0, ge=0), key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    page = await rules_svc.list_rules(db, language_id=key.languageId, query=q, limit=_limit(limit), offset=offset)
    return {"rules": [_rule_out(r) for r in page["rules"]], "total": page["total"]}


@router.get("/rules/{rule_id}")
async def get_rule(rule_id: str, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    return {"rule": _rule_out(rules_svc.rule_dto(await _own_rule(db, key, rule_id)))}


@router.post("/rules", status_code=201)
async def create_rule(body: RuleBody, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    return {"rule": _rule_out(await rules_svc.create_rule(db, language_id=key.languageId, text=body.text))}


@router.patch("/rules/{rule_id}")
async def update_rule(rule_id: str, body: RuleBody, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    await _own_rule(db, key, rule_id)
    return {"rule": _rule_out(await rules_svc.update_rule(db, rule_id, body.text))}


@router.delete("/rules/{rule_id}")
async def delete_rule(rule_id: str, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    await _own_rule(db, key, rule_id)
    await rules_svc.delete_rule(db, rule_id)
    return {"ok": True}


@router.post("/rules/import")
async def import_rules(body: RulesImport, key: ApiKey = Depends(require_api_key), db: AsyncSession = Depends(get_db)):
    return await rules_svc.import_rules(db, key.languageId, [r.text for r in body.rules])
