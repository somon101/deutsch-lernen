"""«Заполнить урок по плану» (§ course modules, 2026-10-05).

The methodologist builds the lesson by hand — its words, phrases, route and
empty steps marked "ждёт ИИ" (LessonNode.aiPending, with LessonNode.aiTask
saying what belongs there) — and writes the lesson plan. This fills ONLY
those waiting steps, in place: no step is added, removed or reordered, and
anything already filled stays untouched. Words and phrases the model may use
are the lesson's own (plus earlier lessons' words, so a rule can be
explained on what learners already know); every question passes the same
validation as the constructor's form (see ai_lessons._clean_question)."""

from types import SimpleNamespace

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.course_lesson import CourseLesson
from app.models.course_module import CourseModule
from app.models.lesson_node import LessonNode
from app.models.material import Material
from app.models.phrase import Phrase
from app.models.vocabulary_item import VocabularyItem
from app.services import ai_settings, lesson_graph
from app.services import ai_client
from app.services import taxonomy as taxonomy_svc
from app.services.ai_lessons import AUTO_MATCH_COUNTS, _clean_question, _course_context, _create_question, _str
from app.services.vocabulary import get_linked_items_by_lesson

FILLABLE = ("material", "audio", "minitest", "practice", "review")
MAX_EARLIER_WORDS = 200

FILL_PROMPT = """You are a methodologist filling ONE lesson of a language-learning course. The learners speak Russian and Tajik.
The lesson structure is fixed: you only write the content of the steps listed under STEPS TO FILL, following the LESSON PLAN and each step's TASK.
Answer with ONE JSON object only.

RULES
- Use the lesson's WORDS and PHRASES; you may also use KNOWN WORDS from earlier lessons. Do not introduce other vocabulary except the grammar words a rule needs (am/is/are, a/an, ...).
- Explanations are in Russian ("title", "content") AND Tajik ("title_tg", "content_tg"); examples stay in the studied language.
- Question prompts are in Russian ("prompt") with a Tajik version ("prompt_tg").
- Question kinds:
  * choice:    {"kind":"choice","prompt":..,"prompt_tg":..,"options":[3 or 4 strings],"correctAnswer": one of options}
  * truefalse: {"kind":"truefalse","prompt": a statement,"prompt_tg":..,"correct": true|false}
  * cloze:     {"kind":"cloze","prompt": a sentence in the studied language with exactly one "___","prompt_tg":..,"options":[3 or 4],"correctAnswer": one of options}
  * scramble:  {"kind":"scramble","prompt": Russian translation,"prompt_tg":..,"correctAnswer": the sentence in the studied language}
  * match:     {"kind":"match","prompt": instruction,"prompt_tg":..,"pairs":[{"left":..,"right":..}, 3 to 5 pairs]}
- Options never repeat; correctAnswer is exactly one of the options.

WHAT EACH STEP TYPE NEEDS (key = the step alias, s1, s2, ...)
- material: {"blocks":[{"title","title_tg","content","content_tg","questions":[1-3 questions checking this block]}]} — 2 to 5 short blocks, one small idea each, with examples.
- audio:    {"transcript": 40-120 words in the studied language using the lesson words, "translation_ru":..,"translation_tg":..}
- minitest / review: {"questions":[...]} — 5 to 10 questions.
- practice: {"questions":[... 3 to 8 ...], "auto":{"translateCount": 0-10, "matchPairs": 0|2|4|6|8, "blankPhraseIds":["ph1",..]}} — "auto" makes automatic exercises from the lesson words/phrases.

OUTPUT FORMAT
{"steps": {"s1": {...}, "s2": {...}}}"""


async def _lesson_words(db: AsyncSession, lesson_ids: list[str]) -> dict[str, list[VocabularyItem]]:
    if not lesson_ids:
        return {}
    native = (await db.execute(select(VocabularyItem).where(VocabularyItem.lessonId.in_(lesson_ids)).order_by(VocabularyItem.position))).scalars().all()
    out: dict[str, list[VocabularyItem]] = {}
    for w in native:
        out.setdefault(w.lessonId, []).append(w)
    for lid, items in (await get_linked_items_by_lesson(db, lesson_ids)).items():
        out.setdefault(lid, []).extend(items)
    return out


async def fill_lesson(db: AsyncSession, course_id: str, lesson_id: str, *, instructions: str | None = None) -> dict:
    api_key, model = await ai_settings.get_api_key(db)
    if not api_key:
        raise ApiError(400, "API-ключ ИИ не настроен — админ может добавить его в разделе «ИИ»")
    course, level, language = await _course_context(db, course_id)
    lesson = (await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))).scalar_one_or_none()
    if not lesson:
        raise ApiError(404, "Урок не найден")
    plan = (lesson.planEn or "").strip() or (lesson.planRu or "").strip()
    if not plan:
        raise ApiError(400, "Сначала напишите план урока — ИИ заполняет урок по нему")

    graph = await lesson_graph.get_lesson_graph(db, course_id, lesson_id)
    if graph["isLegacy"]:
        raise ApiError(400, "В уроке ещё нет шагов — постройте маршрут урока")
    nodes = {n.id: n for n in (await db.execute(select(LessonNode).where(LessonNode.lessonId == lesson_id))).scalars().all()}
    route = _route_order(graph)
    pending = [nodes[i] for i in route if i in nodes and nodes[i].aiPending]
    if not pending:
        raise ApiError(400, "В уроке нет шагов, которые ждут ИИ")
    fillable = [n for n in pending if n.type in FILLABLE]
    warnings = [f"Шаг «{n.title or lesson_graph.DEFAULT_TITLES.get(n.type, n.type)}» ИИ не заполняет — заполните его сами" for n in pending if n.type not in FILLABLE]
    if not fillable:
        raise ApiError(400, warnings[0] if warnings else "Нечего заполнять")

    # Words: this lesson's, plus earlier lessons' as "known".
    earlier_ids = (
        await db.execute(select(CourseLesson.id).where(CourseLesson.courseId == course_id, CourseLesson.position < lesson.position).order_by(CourseLesson.position))
    ).scalars().all()
    words_by_lesson = await _lesson_words(db, [lesson_id, *earlier_ids])
    words = words_by_lesson.get(lesson_id, [])
    known: list[VocabularyItem] = []
    seen = {w.germanKey for w in words}
    for lid in earlier_ids:
        for w in words_by_lesson.get(lid, []):
            if w.germanKey not in seen:
                seen.add(w.germanKey)
                known.append(w)
    known = known[-MAX_EARLIER_WORDS:]

    phrase_ids = [pid for n in nodes.values() if n.type == "phrases" for pid in (n.phraseIds or [])]
    phrases = {p.id: p for p in (await db.execute(select(Phrase).where(Phrase.id.in_(phrase_ids)))).scalars().all()} if phrase_ids else {}
    phrase_alias = {f"ph{i + 1}": pid for i, pid in enumerate(dict.fromkeys(phrase_ids)) if pid in phrases}

    module = await db.get(CourseModule, lesson.moduleId) if lesson.moduleId else None
    step_alias = {f"s{i + 1}": n.id for i, n in enumerate(fillable)}
    title_of = {n.id: n.title or lesson_graph.DEFAULT_TITLES.get(n.type, n.type) for n in nodes.values()}

    user_prompt = "\n".join(
        line
        for line in [
            f"Studied language: {language.name}",
            f"Level: {level.code} — {level.name}",
            f"Course: {course.title}",
            f"Module: {module.title}" if module else "",
            f"Lesson: {lesson.title}",
            "",
            "LESSON PLAN:",
            plan,
            f"\nExtra wishes from the teacher: {instructions.strip()}" if instructions and instructions.strip() else "",
            "",
            "LESSON ROUTE (all steps, in order): " + " -> ".join(f"{title_of[i]} ({nodes[i].type})" for i in route if i in nodes),
            "",
            "STEPS TO FILL:",
            *[f"{a}: type={nodes[nid].type}; title={title_of[nid]}; TASK: {nodes[nid].aiTask or '(follow the plan)'}" for a, nid in step_alias.items()],
            "",
            "WORDS OF THIS LESSON (word — Russian):",
            *([f"{w.german} — {w.translation}" for w in words] or ["(none)"]),
            "",
            "PHRASES OF THIS LESSON (alias: phrase — Russian):",
            *([f"{a}: {phrases[pid].text} — {phrases[pid].translation}" for a, pid in phrase_alias.items()] or ["(none)"]),
            "",
            "KNOWN WORDS FROM EARLIER LESSONS:",
            ", ".join(w.german for w in known) or "(none)",
        ]
        if line is not None
    )
    raw = await ai_client.chat_json(api_key, model, FILL_PROMPT, user_prompt, max_tokens=8000)
    steps = raw.get("steps") if isinstance(raw.get("steps"), dict) else {}

    filled: list[str] = []
    for alias, node_id in step_alias.items():
        node = nodes[node_id]
        label = f"Шаг «{title_of[node_id]}»"
        data = steps.get(alias)
        if not isinstance(data, dict):
            warnings.append(f"{label}: ИИ не вернул содержимое — шаг остался пустым")
            continue
        try:
            ok = await _fill_node(db, course_id, lesson, node, data, phrase_alias, phrases, len(words), label, warnings)
        except ApiError as e:
            await db.rollback()
            warnings.append(f"{label}: {e.message}")
            continue
        if ok:
            node.aiPending = False
            await db.commit()
            filled.append(node_id)
    return {"filled": len(filled), "waiting": len(pending) - len(filled), "warnings": warnings}


def _route_order(graph: dict) -> list[str]:
    """Node ids in learner order (chains from their roots, then strays)."""
    nxt = {e["fromNodeId"]: e["toNodeId"] for e in graph["edges"]}
    has_in = {e["toNodeId"] for e in graph["edges"]}
    order: list[str] = []
    for n in graph["nodes"]:
        if n["id"] in has_in:
            continue
        current = n["id"]
        while current and current not in order:
            order.append(current)
            current = nxt.get(current)
    order += [n["id"] for n in graph["nodes"] if n["id"] not in order]
    return order


async def _fill_node(db, course_id, lesson, node, data, phrase_alias, phrases, word_count, label, warnings) -> bool:
    if node.type == "audio":
        transcript = _str(data.get("transcript"))
        if not transcript:
            warnings.append(f"{label}: нет текста аудио")
            return False
        translations = {k: v for k, v in (("ru", _str(data.get("translation_ru"))), ("tg", _str(data.get("translation_tg")))) if v}
        await lesson_graph.update_node(db, lesson.id, node.id, {"transcript": transcript, "transcriptTranslations": translations})
        return True

    if node.type == "material":
        material = await db.get(Material, node.refId) if node.refId else None
        if not material:
            warnings.append(f"{label}: материал шага не найден")
            return False
        created = 0
        for bi, block in enumerate(data.get("blocks") or []):
            if not isinstance(block, dict) or not _str(block.get("title")) or not _str(block.get("content")):
                warnings.append(f"{label}: блок {bi + 1} пропущен — нет заголовка или текста")
                continue
            row = await taxonomy_svc.add_material_block(db, material.id, SimpleNamespace(title=_str(block["title"])[:200], content=_str(block["content"])))
            created += 1
            if _str(block.get("title_tg")) or _str(block.get("content_tg")):
                await taxonomy_svc.set_material_block_translation(
                    db, row.id, "tg", _str(block.get("title_tg")) or _str(block["title"]), _str(block.get("content_tg")) or _str(block["content"])
                )
            for qi, rq in enumerate((block.get("questions") or [])[:3]):
                cleaned = _clean_question(rq, f"{label}, блок {bi + 1}, вопрос {qi + 1}", warnings)
                if cleaned:
                    await _create_question(db, cleaned, topic_id=material.topicId, material_block_id=row.id)
        if not created:
            warnings.append(f"{label}: ИИ не вернул ни одного блока")
        return created > 0

    # minitest / practice / review — questions into the step's LessonBlock.
    if not node.refId:
        warnings.append(f"{label}: блок вопросов не найден")
        return False
    added = 0
    for qi, rq in enumerate((data.get("questions") or [])[:12]):
        cleaned = _clean_question(rq, f"{label}, вопрос {qi + 1}", warnings)
        if cleaned:
            await _create_question(db, cleaned, topic_id=None, lesson_block_id=node.refId)
            added += 1
    auto = data.get("auto") if node.type == "practice" and isinstance(data.get("auto"), dict) else {}
    try:
        translate_count = max(0, min(int(auto.get("translateCount") or 0), 20)) if word_count else 0
    except (TypeError, ValueError):
        translate_count = 0
    try:
        wanted_pairs = int(auto.get("matchPairs") or 0)
    except (TypeError, ValueError):
        wanted_pairs = 0
    possible = [c for c in AUTO_MATCH_COUNTS if c <= word_count]
    match_pairs = min(possible, key=lambda c: abs(c - wanted_pairs)) if wanted_pairs and possible else 0
    blanks = [phrases[phrase_alias[a]].text for a in (auto.get("blankPhraseIds") or []) if isinstance(a, str) and a in phrase_alias][:10]
    if translate_count:
        await _create_question(db, {"question": {"kind": "auto_translate", "source": "lesson", "count": translate_count}}, topic_id=None, lesson_block_id=node.refId)
        added += 1
    if match_pairs:
        await _create_question(db, {"question": {"kind": "auto_match", "count": match_pairs}}, topic_id=None, lesson_block_id=node.refId)
        added += 1
    if blanks:
        await _create_question(db, {"question": {"kind": "auto_blank", "phrases": blanks}}, topic_id=None, lesson_block_id=node.refId)
        added += 1
    if not added:
        warnings.append(f"{label}: ни одного годного вопроса")
    return added > 0
