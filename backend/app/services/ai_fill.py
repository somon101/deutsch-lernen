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
from app.models.material_block import MaterialBlock
from app.models.phrase import Phrase
from app.models.vocabulary_item import VocabularyItem
from app.services import ai_settings, lesson_graph
from app.services import ai_client
from app.services import taxonomy as taxonomy_svc
from app.services.ai_lessons import AUTO_MATCH_COUNTS, _clean_question, _course_context, _create_question, _str
from app.services.vocabulary import get_linked_items_by_lesson

FILLABLE = ("material", "audio", "video", "minitest", "practice", "review")
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
- video:    {"transcript": the script the on-screen teacher character says, 40-120 words in the studied language, short sentences, presenting the lesson topic with examples from the lesson words, "translation_ru":..,"translation_tg":..}
- minitest / review: {"questions":[...]} — 5 to 10 questions.
- practice: {"questions":[... 3 to 8 ...], "auto":{"translateCount": 0-10, "matchPairs": 0|2|4|6|8, "blankPhraseIds":["ph1",..]}} — "auto" makes automatic exercises from the lesson words/phrases.
- a question step marked "TEST OF <step>": 4 to 5 comprehension questions ONLY about the given audio/video text (what was said, who, where, true/false).

LINKING QUESTIONS (when MATERIAL BLOCKS are listed): every question of practice/minitest/review gets "verifiesBlock": the alias (b1, b2, ...) of the ONE material block whose idea it checks, or null if it checks only vocabulary.

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
    title_of = {n.id: n.title or lesson_graph.DEFAULT_TITLES.get(n.type, n.type) for n in nodes.values()}
    lesson_topic_id = await _lesson_topic_id(db, lesson_id)

    content_steps = [n for n in fillable if n.type in CONTENT_TYPES]
    question_steps = [n for n in fillable if n.type not in CONTENT_TYPES]
    filled: list[str] = []
    ctx = dict(api_key=api_key, model=model, course=course, level=level, language=language, module=module, lesson=lesson, plan=plan,
               instructions=instructions, route=route, nodes=nodes, title_of=title_of, words=words, phrases=phrases,
               phrase_alias=phrase_alias, known=known, lesson_topic_id=lesson_topic_id, course_id=course_id)
    # Phase 1: explanations and audio/video texts. Phase 2: questions, which
    # can then point at the blocks and texts that now exist.
    if content_steps:
        filled += await _run_phase(db, ctx, content_steps, [], {}, warnings)
    if question_steps:
        block_alias, block_lines = await _blocks_for_questions(db, lesson, nodes)
        extra = []
        if block_lines:
            extra += ["", "MATERIAL BLOCKS (alias: title — text):", *block_lines]
        filled += await _run_phase(db, ctx, question_steps, extra, block_alias, warnings)
    return {"filled": len(filled), "waiting": len(pending) - len(filled), "warnings": warnings}


CONTENT_TYPES = ("material", "audio", "video")


async def _lesson_topic_id(db: AsyncSession, lesson_id: str) -> str | None:
    return await db.scalar(
        select(Material.topicId).where(Material.lessonId == lesson_id, Material.topicId.isnot(None)).order_by(Material.position).limit(1)
    )


async def _blocks_for_questions(db: AsyncSession, lesson: CourseLesson, nodes: dict) -> tuple[dict, list[str]]:
    """Material blocks a question may be tagged with: this lesson's, or —
    for a lesson without its own explanation — those of the earlier lessons
    of the same module."""
    lesson_ids = [lesson.id]
    own = await db.scalar(
        select(MaterialBlock.id).join(Material, Material.id == MaterialBlock.materialId).where(Material.lessonId == lesson.id).limit(1)
    )
    if own is None and lesson.moduleId:
        lesson_ids = list(
            (await db.execute(
                select(CourseLesson.id).where(CourseLesson.moduleId == lesson.moduleId, CourseLesson.position < lesson.position).order_by(CourseLesson.position)
            )).scalars().all()
        )
    if not lesson_ids:
        return {}, []
    rows = (
        await db.execute(
            select(MaterialBlock, Material.topicId)
            .join(Material, Material.id == MaterialBlock.materialId)
            .where(Material.lessonId.in_(lesson_ids))
            .order_by(Material.lessonId, Material.position, MaterialBlock.position)
        )
    ).all()
    rows = rows[:40]
    alias = {f"b{i + 1}": (b.id, topic_id) for i, (b, topic_id) in enumerate(rows)}
    lines = [f"b{i + 1}: {b.title} — {' '.join((b.content or '').split())[:220]}" for i, (b, _) in enumerate(rows)]
    return alias, lines


async def _run_phase(db, ctx, steps_nodes, extra_lines, block_alias, warnings) -> list[str]:
    nodes, title_of, route = ctx["nodes"], ctx["title_of"], ctx["route"]
    lesson, module, instructions = ctx["lesson"], ctx["module"], ctx["instructions"]
    words, phrases, phrase_alias, known = ctx["words"], ctx["phrases"], ctx["phrase_alias"], ctx["known"]
    step_alias = {f"s{i + 1}": n.id for i, n in enumerate(steps_nodes)}
    step_lines = []
    media_lines = []
    for a, nid in step_alias.items():
        n = nodes[nid]
        line = f"{a}: type={n.type}; title={title_of[nid]}; TASK: {n.aiTask or '(follow the plan)'}"
        target = nodes.get(n.forNodeId) if n.forNodeId else None
        if target is not None:
            line += f"; TEST OF the {target.type} step «{title_of[target.id]}»"
            if target.transcript:
                media_lines += ["", f"TEXT OF {target.type.upper()} «{title_of[target.id]}» (for {a}):", target.transcript]
        step_lines.append(line)
    course, level, language = ctx["course"], ctx["level"], ctx["language"]
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
            ctx["plan"],
            f"\nExtra wishes from the teacher: {instructions.strip()}" if instructions and instructions.strip() else "",
            "",
            "LESSON ROUTE (all steps, in order): " + " -> ".join(f"{title_of[i]} ({nodes[i].type})" for i in route if i in nodes),
            "",
            "STEPS TO FILL:",
            *step_lines,
            *media_lines,
            *extra_lines,
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
    raw = await ai_client.chat_json(ctx["api_key"], ctx["model"], FILL_PROMPT, user_prompt, max_tokens=8000)
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
            if node.forNodeId and not (nodes.get(node.forNodeId) and nodes[node.forNodeId].transcript):
                warnings.append(f"{label}: у аудио/видео ещё нет текста — тест не составлен")
                continue
            ok = await _fill_node(db, ctx["course_id"], lesson, node, data, phrase_alias, phrases, len(words), label, warnings,
                                  block_alias=block_alias, lesson_topic_id=ctx["lesson_topic_id"])
        except ApiError as e:
            await db.rollback()
            warnings.append(f"{label}: {e.message}")
            continue
        if ok:
            node.aiPending = False
            await db.commit()
            filled.append(node_id)
    return filled


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


async def _fill_node(db, course_id, lesson, node, data, phrase_alias, phrases, word_count, label, warnings, *, block_alias=None, lesson_topic_id=None) -> bool:
    block_alias = block_alias or {}
    if node.type in ("audio", "video"):
        transcript = _str(data.get("transcript"))
        if not transcript:
            warnings.append(f"{label}: нет текста")
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
                    await _create_question(db, cleaned, topic_id=material.topicId or lesson_topic_id, material_block_id=row.id)
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
        if not cleaned:
            continue
        verifies = rq.get("verifiesBlock") if isinstance(rq, dict) else None
        block_id, block_topic = block_alias.get(verifies, (None, None)) if isinstance(verifies, str) else (None, None)
        if verifies and block_id is None and block_alias:
            warnings.append(f"{label}, вопрос {qi + 1}: блок «{verifies}» не найден — вопрос без привязки к блоку")
        await _create_question(
            db, cleaned, topic_id=block_topic or lesson_topic_id, lesson_block_id=node.refId, material_block_id=block_id, media_node_id=node.forNodeId
        )
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
