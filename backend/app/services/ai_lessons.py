"""AI lesson generator (§ AI lesson generator, 2026-10-03).

Two steps, so nothing reaches a course before a person has looked at it:

1. `preview_lesson` asks the model for ONE lesson plan (one request per
   lesson keeps every HTTP call well under the server's request timeout;
   the admin UI calls it once per lesson and passes the lessons it already
   has back in, so topics and words don't repeat). Nothing is written.
2. `apply_plan` turns the reviewed plans into ordinary graph lessons using
   the same service functions the constructor itself uses — a generated
   lesson is indistinguishable from a hand-built one and fully editable.

The model may only use words and phrases from our own bases: they are sent
under short aliases (w1, p1, ...) and every id it returns is checked
against them; anything else is dropped with a warning. Every question goes
through the same pydantic validation as the constructor's own form
(QuestionCreateInput), so an invalid one is dropped, never stored."""

from types import SimpleNamespace

from pydantic import ValidationError
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.course import Course
from app.models.course_lesson import CourseLesson
from app.models.language import Language
from app.models.lesson_vocabulary_link import LessonVocabularyLink
from app.models.level import Level
from app.models.material import Material
from app.models.phrase import Phrase
from app.models.vocabulary_item import VocabularyItem
from app.schemas.taxonomy import QuestionCreateInput
from app.services import ai_client, ai_settings
from app.services import courses as courses_svc
from app.services import lesson_graph
from app.services import taxonomy as taxonomy_svc
from app.services.phrases import topic_id_for_name

MAX_WORDS_IN_CONTEXT = 400
MAX_PHRASES_IN_CONTEXT = 300
MANUAL_KINDS = ("choice", "truefalse", "cloze", "scramble", "match")
AUTO_MATCH_COUNTS = (2, 4, 6, 8)

# Editable by the admin in «ИИ» (AiSettings.systemPrompt); this is the
# default and what «Вернуть стандартный» restores.
DEFAULT_RULES_PROMPT = """You are a methodologist who writes lessons for a language-learning platform.
The learners speak Russian and Tajik. You write ONE lesson of the given course and answer with ONE JSON object only.

STRICT RULES
- Use ONLY words and phrases from the lists you are given, referenced by their aliases (w1, w2, ... / p1, p2, ...). Never invent ids.
- Explanations (block titles and texts) are written in Russian ("title", "content") AND in Tajik ("title_tg", "content_tg").
- Examples, sentences and answers in the studied language stay in the studied language.
- 3 to 5 explanation blocks. Each block explains one small idea with examples and has 1 to 3 questions that check exactly that block.
- 10 to 20 words for the lesson ("wordIds"), chosen to fit the lesson topic.
- Question prompts are in Russian ("prompt") with a Tajik version ("prompt_tg").
- Question kinds:
  * choice:    {"kind":"choice","prompt":..,"prompt_tg":..,"options":[3 or 4 strings],"correctAnswer": one of options}
  * truefalse: {"kind":"truefalse","prompt": a statement,"prompt_tg":..,"correct": true|false}
  * cloze:     {"kind":"cloze","prompt": a sentence in the studied language with exactly one "___","prompt_tg":..,"options":[3 or 4],"correctAnswer": one of options}
  * scramble:  {"kind":"scramble","prompt": Russian translation of the sentence,"prompt_tg":..,"correctAnswer": the sentence in the studied language}
  * match:     {"kind":"match","prompt": instruction,"prompt_tg":..,"pairs":[{"left":..,"right":..}, 3 to 5 pairs]}
- Options never repeat. correctAnswer must be exactly one of the options.
- "audio": a short dialogue or monologue (60-120 words) in the studied language that uses the lesson's words, plus its Russian and Tajik translation. It will be recorded later.
- "practice": how many automatic exercises to make from the lesson words: "translateCount" (5-10), "matchPairs" (one of 2, 4, 6, 8), and "blankPhraseIds" (2-5 phrase aliases for fill-the-gap, may be empty).
- "minitest": 6 to 10 final questions; each has "verifiesBlock": the 0-based index of the block it checks."""

# Always appended after the (possibly edited) rules: the parser below
# depends on exactly these keys, so this part is not editable.
OUTPUT_FORMAT_PROMPT = """OUTPUT FORMAT (exactly these keys)
{"title":"..","title_tg":"..","topic":"short topic name in Russian",
 "wordIds":["w1",..],"phraseIds":["p1",..],
 "blocks":[{"title":"..","title_tg":"..","content":"..","content_tg":"..","questions":[...]}],
 "audio":{"transcript":"..","translation_ru":"..","translation_tg":".."},
 "practice":{"translateCount":8,"matchPairs":4,"blankPhraseIds":["p3"]},
 "minitest":[{...question..., "verifiesBlock":0}]}"""


# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------


async def _course_context(db: AsyncSession, course_id: str) -> tuple[Course, Level, Language]:
    course = await db.get(Course, course_id)
    if not course:
        raise ApiError(404, "Курс не найден")
    level = await db.get(Level, course.levelId) if course.levelId else None
    if not level:
        raise ApiError(400, "Сначала выберите для курса язык и уровень")
    language = await db.get(Language, level.languageId)
    if not language:
        raise ApiError(400, "У уровня курса не найден язык")
    return course, level, language


async def _available_words(db: AsyncSession, course_id: str, language_id: str, exclude_ids: set[str]) -> list[VocabularyItem]:
    """Dictionary words of the course language not yet used anywhere in
    this course (natively or by reuse), minus the ones earlier lessons of
    the same generation run already took."""
    linked = set((await db.execute(select(LessonVocabularyLink.wordId).where(LessonVocabularyLink.courseId == course_id))).scalars().all())
    rows = (
        await db.execute(
            select(VocabularyItem)
            .where(VocabularyItem.languageId == language_id, or_(VocabularyItem.courseId != course_id, VocabularyItem.courseId.is_(None)))
            .order_by(VocabularyItem.german)
        )
    ).scalars().all()
    seen_keys: set[str] = set()
    out = []
    for w in rows:
        if w.id in linked or w.id in exclude_ids or w.germanKey in seen_keys:
            continue
        seen_keys.add(w.germanKey)
        out.append(w)
        if len(out) >= MAX_WORDS_IN_CONTEXT:
            break
    return out


async def _available_phrases(db: AsyncSession, language_id: str) -> list[Phrase]:
    return list(
        (await db.execute(select(Phrase).where(Phrase.languageId == language_id).order_by(Phrase.text).limit(MAX_PHRASES_IN_CONTEXT))).scalars().all()
    )


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


def _wire_question(q: dict) -> dict | None:
    kind = q.get("kind")
    if kind in ("choice", "cloze"):
        return {"kind": kind, "prompt": q.get("prompt") or "", "options": list(q.get("options") or []), "correctAnswer": q.get("correctAnswer") or ""}
    if kind == "truefalse":
        correct = q.get("correct")
        if isinstance(correct, str):
            correct = correct.strip().lower() in ("true", "да", "1", "верно")
        return {"kind": "truefalse", "prompt": q.get("prompt") or "", "correct": bool(correct)}
    if kind == "scramble":
        return {"kind": "scramble", "prompt": q.get("prompt") or "", "options": [], "correctAnswer": q.get("correctAnswer") or ""}
    if kind == "match":
        return {"kind": "match", "prompt": q.get("prompt") or "", "pairs": [p for p in (q.get("pairs") or []) if isinstance(p, dict)]}
    return None


def _clean_question(raw, where: str, warnings: list[str]) -> dict | None:
    """Returns {"question": <validated wire dict>, "prompt_tg": str|None}
    or None (with a warning) when the model's question is unusable."""
    if not isinstance(raw, dict):
        warnings.append(f"{where}: вопрос пропущен — неверный формат")
        return None
    if isinstance(raw.get("question"), dict):
        # An already-cleaned question coming back from the preview UI.
        raw = {**raw["question"], "prompt_tg": raw.get("prompt_tg")}
    wire = _wire_question(raw)
    if wire is None:
        warnings.append(f"{where}: вопрос пропущен — неизвестный тип «{raw.get('kind')}»")
        return None
    try:
        validated = QuestionCreateInput(question=wire).question.model_dump()
    except ValidationError as e:
        reason = e.errors()[0].get("msg", "ошибка") if e.errors() else "ошибка"
        warnings.append(f"{where}: вопрос пропущен — {reason}")
        return None
    prompt_tg = raw.get("prompt_tg")
    return {"question": validated, "prompt_tg": prompt_tg.strip() if isinstance(prompt_tg, str) and prompt_tg.strip() else None}


def _str(v) -> str:
    return v.strip() if isinstance(v, str) else ""


def normalize_lesson(raw: dict, word_alias: dict[str, str], phrase_alias: dict[str, str], number: int) -> tuple[dict, list[str]]:
    """Model output -> a clean lesson plan that only references real rows.
    `word_alias`/`phrase_alias` map the aliases we sent (w1, p1) to ids;
    real ids are accepted too, so a plan sent back by the UI for applying
    re-validates the same way."""
    warnings: list[str] = []
    label = f"Урок {number}"
    word_ids_known = set(word_alias.values())
    phrase_ids_known = set(phrase_alias.values())

    def resolve(items, alias: dict[str, str], known: set[str], what: str) -> list[str]:
        out: list[str] = []
        for item in items or []:
            key = _str(item) if not isinstance(item, int) else str(item)
            real = alias.get(key) or (key if key in known else None)
            if real is None:
                warnings.append(f"{label}: {what} «{key}» нет в базе — пропущено")
            elif real not in out:
                out.append(real)
        return out

    word_ids = resolve(raw.get("wordIds"), word_alias, word_ids_known, "слова")[:25]
    phrase_ids = resolve(raw.get("phraseIds"), phrase_alias, phrase_ids_known, "фразы")

    blocks = []
    for bi, b in enumerate(raw.get("blocks") or []):
        if not isinstance(b, dict) or not _str(b.get("title")) or not _str(b.get("content")):
            warnings.append(f"{label}: блок {bi + 1} пропущен — нет заголовка или текста")
            continue
        questions = []
        for qi, rq in enumerate(b.get("questions") or []):
            cleaned = _clean_question(rq, f"{label}, блок {len(blocks) + 1}, вопрос {qi + 1}", warnings)
            if cleaned:
                questions.append(cleaned)
        blocks.append(
            {
                "title": _str(b["title"])[:200],
                "title_tg": _str(b.get("title_tg"))[:200] or None,
                "content": _str(b["content"]),
                "content_tg": _str(b.get("content_tg")) or None,
                "questions": questions[:3],
            }
        )
    if not blocks:
        raise ApiError(502, f"{label}: ИИ не вернул ни одного блока объяснения — попробуйте ещё раз")

    audio = raw.get("audio") if isinstance(raw.get("audio"), dict) else None
    audio = (
        {"transcript": _str(audio.get("transcript")), "translation_ru": _str(audio.get("translation_ru")) or None, "translation_tg": _str(audio.get("translation_tg")) or None}
        if audio and _str(audio.get("transcript"))
        else None
    )

    practice_raw = raw.get("practice") if isinstance(raw.get("practice"), dict) else {}
    try:
        translate_count = max(0, min(int(practice_raw.get("translateCount") or 0), 20))
    except (TypeError, ValueError):
        translate_count = 0
    try:
        wanted_pairs = int(practice_raw.get("matchPairs") or 0)
    except (TypeError, ValueError):
        wanted_pairs = 0
    possible = [c for c in AUTO_MATCH_COUNTS if c <= len(word_ids)]
    match_pairs = min(possible, key=lambda c: abs(c - wanted_pairs)) if wanted_pairs and possible else 0
    if not word_ids:
        translate_count = 0
    blank_ids = resolve(practice_raw.get("blankPhraseIds"), phrase_alias, phrase_ids_known, "фразы")[:10]

    minitest = []
    for qi, q in enumerate(raw.get("minitest") or []):
        cleaned = _clean_question(q, f"{label}, мини-тест, вопрос {qi + 1}", warnings)
        if not cleaned:
            continue
        vb = q.get("verifiesBlock") if isinstance(q, dict) else None
        cleaned["verifiesBlock"] = vb if isinstance(vb, int) and 0 <= vb < len(blocks) else None
        minitest.append(cleaned)

    return (
        {
            "title": _str(raw.get("title"))[:200] or label,
            "title_tg": _str(raw.get("title_tg"))[:200] or None,
            "topic": _str(raw.get("topic"))[:100] or None,
            "wordIds": word_ids,
            "phraseIds": phrase_ids,
            "blocks": blocks,
            "audio": audio,
            "practice": {"translateCount": translate_count, "matchPairs": match_pairs, "blankPhraseIds": blank_ids},
            "minitest": minitest[:12],
        },
        warnings,
    )


async def _attach_display(db: AsyncSession, lesson: dict) -> dict:
    """Adds the words/phrases as readable text so the preview can show them
    without another request. Ignored on apply (ids are what count)."""
    words = (await db.execute(select(VocabularyItem).where(VocabularyItem.id.in_(lesson["wordIds"])))).scalars().all() if lesson["wordIds"] else []
    by_id = {w.id: w for w in words}
    ids = list(dict.fromkeys(lesson["phraseIds"] + lesson["practice"]["blankPhraseIds"]))
    phrases = {p.id: p for p in (await db.execute(select(Phrase).where(Phrase.id.in_(ids)))).scalars().all()} if ids else {}
    lesson["words"] = [{"id": i, "word": by_id[i].german, "translation": by_id[i].translation} for i in lesson["wordIds"] if i in by_id]
    lesson["phrases"] = [{"id": i, "text": phrases[i].text, "translation": phrases[i].translation} for i in ids if i in phrases]
    return lesson


# ---------------------------------------------------------------------------
# Preview (one lesson per call, nothing written)
# ---------------------------------------------------------------------------


async def preview_lesson(db: AsyncSession, course_id: str, *, instructions: str | None, previous: list[dict]) -> dict:
    api_key, model = await ai_settings.get_api_key(db)
    rules_prompt = (await ai_settings.get_ai_settings(db)).systemPrompt or DEFAULT_RULES_PROMPT
    if not api_key:
        raise ApiError(400, "API-ключ ИИ не настроен — админ может добавить его в разделе «ИИ»")
    course, level, language = await _course_context(db, course_id)

    used_word_ids = {w for p in previous for w in (p.get("wordIds") or [])}
    words = await _available_words(db, course_id, language.id, used_word_ids)
    phrases = await _available_phrases(db, language.id)
    if not words:
        raise ApiError(400, f"В Словаре нет свободных слов для языка «{language.name}» — сначала добавьте слова")
    word_alias = {f"w{i + 1}": w.id for i, w in enumerate(words)}
    phrase_alias = {f"p{i + 1}": p.id for i, p in enumerate(phrases)}

    existing_titles = (
        await db.execute(select(CourseLesson.title).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position))
    ).scalars().all()
    earlier = list(existing_titles) + [p.get("title") for p in previous if p.get("title")]
    number = len(earlier) + 1

    user_prompt = "\n".join(
        [
            f"Studied language: {language.name}",
            f"Level: {level.code} — {level.name}",
            f"Course: {course.title}",
            f"Course description: {course.description or '-'}",
            f"This is lesson number {number} of the course.",
            "Lessons that already exist (do not repeat their topics): " + ("; ".join(earlier) if earlier else "none"),
            f"Extra wishes from the admin: {instructions.strip()}" if instructions and instructions.strip() else "",
            "",
            "WORDS (alias: word — Russian translation):",
            *[f"{a}: {w.german} — {w.translation}" for a, w in zip(word_alias, words)],
            "",
            "PHRASES (alias: phrase — Russian translation):" if phrases else "PHRASES: none yet (use an empty list)",
            *[f"{a}: {p.text} — {p.translation}" for a, p in zip(phrase_alias, phrases)],
        ]
    )
    raw = await ai_client.chat_json(api_key, model, rules_prompt.rstrip() + "\n\n" + OUTPUT_FORMAT_PROMPT, user_prompt)
    lesson, warnings = normalize_lesson(raw, word_alias, phrase_alias, number)
    return {"lesson": await _attach_display(db, lesson), "warnings": warnings}


# ---------------------------------------------------------------------------
# Apply (writes ordinary graph lessons)
# ---------------------------------------------------------------------------


async def _create_question(db: AsyncSession, cleaned: dict, *, topic_id: str | None, material_block_id: str | None = None, lesson_block_id: str | None = None) -> None:
    body = QuestionCreateInput(question=cleaned["question"], topicId=topic_id, materialBlockId=material_block_id, lessonBlockId=lesson_block_id, force=True)
    question, _ = await taxonomy_svc.create_question(db, body)
    if cleaned.get("prompt_tg"):
        await taxonomy_svc.set_question_translation(db, question.id, "tg", cleaned["prompt_tg"], None, None, None)


async def _apply_one(db: AsyncSession, course_id: str, language_id: str, plan: dict, number: int) -> str:
    label = f"Урок {number} «{plan['title']}»"
    step = "создание урока"
    try:
        await courses_svc.create_lesson(db, course_id, plan["title"], None, None, notify=False)
        lesson = (
            await db.execute(select(CourseLesson).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position.desc()).limit(1))
        ).scalar_one()
        if plan.get("title_tg"):
            await courses_svc.set_lesson_translation(db, course_id, lesson.id, "tg", plan["title_tg"], "", "")

        step = "тема"
        topic_id = await topic_id_for_name(db, language_id, plan.get("topic"))
        await db.commit()

        step = "слова"
        for word_id in plan["wordIds"]:
            await courses_svc.link_existing_word_to_lesson(db, course_id, lesson.id, word_id)

        node_ids: list[str] = []
        x = 0.0

        async def add_node(node_type: str, title: str | None = None) -> dict:
            nonlocal x
            node = await lesson_graph.create_node(db, course_id, lesson.id, node_type, title, x, 0.0)
            x += 260.0
            node_ids.append(node["id"])
            return node

        if plan["wordIds"]:
            step = "шаг «Слова»"
            await add_node("vocabulary")

        step = "материал"
        material_node = await add_node("material", plan.get("topic"))
        material = await db.get(Material, material_node["refId"])
        material.title = plan.get("topic") or plan["title"]
        material.topicId = topic_id
        await db.commit()
        block_ids: list[str] = []
        for bi, block in enumerate(plan["blocks"]):
            step = f"блок {bi + 1}"
            row = await taxonomy_svc.add_material_block(db, material.id, SimpleNamespace(title=block["title"], content=block["content"]))
            block_ids.append(row.id)
            if block.get("title_tg") or block.get("content_tg"):
                await taxonomy_svc.set_material_block_translation(
                    db, row.id, "tg", block.get("title_tg") or block["title"], block.get("content_tg") or block["content"]
                )
            for q in block["questions"]:
                await _create_question(db, q, topic_id=topic_id, material_block_id=row.id)

        if plan.get("audio"):
            step = "аудио"
            audio = plan["audio"]
            node = await add_node("audio")
            translations = {k: v for k, v in (("ru", audio.get("translation_ru")), ("tg", audio.get("translation_tg"))) if v}
            await lesson_graph.update_node(db, lesson.id, node["id"], {"transcript": audio["transcript"], "transcriptTranslations": translations})

        practice = plan["practice"]
        blank_phrases = []
        if practice["blankPhraseIds"]:
            phrase_rows = {p.id: p.text for p in (await db.execute(select(Phrase).where(Phrase.id.in_(practice["blankPhraseIds"])))).scalars().all()}
            blank_phrases = [phrase_rows[i] for i in practice["blankPhraseIds"] if i in phrase_rows]
        if practice["translateCount"] or practice["matchPairs"] or blank_phrases:
            step = "практика"
            node = await add_node("practice")
            if practice["translateCount"]:
                await _create_question(db, {"question": {"kind": "auto_translate", "source": "lesson", "count": practice["translateCount"]}}, topic_id=None, lesson_block_id=node["refId"])
            if practice["matchPairs"]:
                await _create_question(db, {"question": {"kind": "auto_match", "count": practice["matchPairs"]}}, topic_id=None, lesson_block_id=node["refId"])
            if blank_phrases:
                await _create_question(db, {"question": {"kind": "auto_blank", "phrases": blank_phrases}}, topic_id=topic_id, lesson_block_id=node["refId"])

        if plan["minitest"]:
            step = "мини-тест"
            node = await add_node("minitest")
            for q in plan["minitest"]:
                vb = q.get("verifiesBlock")
                await _create_question(
                    db, q, topic_id=topic_id, lesson_block_id=node["refId"], material_block_id=block_ids[vb] if vb is not None and vb < len(block_ids) else None
                )

        step = "маршрут урока"
        for a, b in zip(node_ids, node_ids[1:]):
            await lesson_graph.add_edge(db, course_id, lesson.id, a, b)
        return lesson.id
    except ApiError as e:
        raise ApiError(e.status_code, f"{label}, шаг «{step}»: {e.message}") from e
    except Exception as e:  # noqa: BLE001 — surface where it broke; earlier lessons stay
        await db.rollback()
        raise ApiError(500, f"{label}, шаг «{step}»: {e}") from e


async def apply_plans(db: AsyncSession, course_id: str, lessons: list[dict]) -> dict:
    """Re-validates each reviewed plan (the client is not trusted) and
    creates the lessons in order. Lessons created before a failure stay —
    the error names the lesson and step so the admin can fix or delete it."""
    _, _, language = await _course_context(db, course_id)
    word_ids = set((await db.execute(select(VocabularyItem.id).where(VocabularyItem.languageId == language.id))).scalars().all())
    phrase_ids = set((await db.execute(select(Phrase.id).where(Phrase.languageId == language.id))).scalars().all())
    identity_words = {i: i for i in word_ids}
    identity_phrases = {i: i for i in phrase_ids}

    first_number = (await db.scalar(select(CourseLesson.position).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position.desc()).limit(1)))
    first_number = (first_number + 2) if first_number is not None else 1

    created: list[str] = []
    warnings: list[str] = []
    for i, raw in enumerate(lessons):
        plan, w = normalize_lesson(raw, identity_words, identity_phrases, first_number + i)
        warnings.extend(w)
        created.append(await _apply_one(db, course_id, language.id, plan, first_number + i))
    return {"lessonIds": created, "warnings": warnings}
