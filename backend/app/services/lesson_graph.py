"""Lesson graph (§ lesson graph, 2026-09-03) — replaces the fixed 8-stage
Words->Material->Video->Minitest->Audio->Practice->Review->Complete sequence
with a free-form graph the teacher builds. A lesson with no LessonNode rows
is "legacy" (unconverted) — every function here either leaves it alone or,
for get_lesson_graph, returns a computed PREVIEW of what converting it would
produce, without writing anything. Nothing is read from this module by the
old fixed-chain builder/runner code paths, so an unconverted lesson is
completely unaffected by this feature existing.

LessonNode wraps existing content by reference (Material.id for "material",
LessonBlock.id for minitest/practice/review) — content itself is still
created/edited/deleted through the existing Material/LessonBlock machinery
in services/courses.py and services/taxonomy.py, reused here rather than
reimplemented. The graph's own job is topology only: which nodes exist,
where they sit on the canvas, and how LessonEdge rows chain them — student
routing is a topological flatten of that chain, computed client-side (same
"server persists, client decides sequencing" contract lesson_state.py
already has)."""

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.course_lesson import CourseLesson
from app.models.lesson_block import LessonBlock
from app.models.lesson_edge import LessonEdge
from app.models.lesson_node import LessonNode
from app.models.lesson_node_media import LessonNodeMedia
from app.models.lesson_question import LessonQuestion
from app.models.material import Material
from app.models.course import Course
from app.models.level import Level
from app.models.material_block import MaterialBlock
from app.models.phrase import Phrase, PhraseTranslation
from app.models.vocabulary_item import VocabularyItem
from app.services.content import LEGACY_COURSE_ID
from app.services.vocabulary import get_linked_items_by_lesson

NODE_TYPES = ("vocabulary", "phrases", "material", "video", "audio", "minitest", "practice", "review")
# Node types backed by their own content row (as opposed to vocabulary/video/
# audio, which reference no row — see LessonNode's docstring).
_BLOCK_STAGES = ("minitest", "practice", "review")

DEFAULT_TITLES = {
    "vocabulary": "Слова",
    "phrases": "Фразы",
    "material": "Материал",
    "video": "Видео",
    "audio": "Аудио",
    "minitest": "Мини-тест",
    "practice": "Практика",
    "review": "Закрепление",
}


async def _owned_lesson(db: AsyncSession, course_id: str, lesson_id: str) -> CourseLesson:
    if course_id == LEGACY_COURSE_ID:
        raise ApiError(400, "Граф недоступен для устаревшего курса")
    result = await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        raise ApiError(404, "Урок не найден")
    return lesson


def node_dto(node: LessonNode, media_override: str | None = None, phrases: list[dict] | None = None) -> dict:
    """`media_override` (§ course content language, 2026-09-04) is the
    resolved LessonNodeMedia row's URL for the caller's requested locale,
    when one exists — omitted (every admin-builder caller), this returns
    node.mediaUrl exactly as before. `phrases` is a "phrases" node's phrase
    list already resolved to text (see _phrases_by_node)."""
    return {
        "id": node.id,
        "type": node.type,
        "refId": node.refId,
        "mediaUrl": media_override if media_override is not None else node.mediaUrl,
        "title": node.title or DEFAULT_TITLES.get(node.type, node.type),
        "posX": node.posX,
        "posY": node.posY,
        # Audio nodes only (§ AI lesson generator, 2026-10-03): the
        # recording's text and its per-locale translations.
        "transcript": node.transcript,
        "transcriptTranslations": node.transcriptTranslations or {},
        # § course modules, 2026-10-05.
        "phraseIds": list(node.phraseIds or []),
        "phrases": phrases if phrases is not None else [],
        "aiTask": node.aiTask,
        "aiTaskRu": node.aiTaskRu,
        "aiPending": bool(node.aiPending),
        "forNodeId": node.forNodeId,
    }


async def _phrases_by_node(db: AsyncSession, nodes: list[LessonNode], locale: str | None = None) -> dict[str, list[dict]]:
    """Every "phrases" node's phrases as {id, text, translation, translations},
    in the node's own order. `translation` is the requested locale's text
    when one exists (base column = Russian), like words. A phrase deleted
    from the base simply drops out."""
    wanted = {pid for n in nodes if n.type == "phrases" for pid in (n.phraseIds or [])}
    if not wanted:
        return {}
    rows = {p.id: p for p in (await db.execute(select(Phrase).where(Phrase.id.in_(wanted)))).scalars().all()}
    translations: dict[str, dict[str, str]] = {}
    for t in (await db.execute(select(PhraseTranslation).where(PhraseTranslation.phraseId.in_(wanted)))).scalars().all():
        translations.setdefault(t.phraseId, {})[t.locale] = t.translation
    out: dict[str, list[dict]] = {}
    for n in nodes:
        if n.type != "phrases":
            continue
        items = []
        for pid in n.phraseIds or []:
            p = rows.get(pid)
            if not p:
                continue
            t = translations.get(pid, {})
            items.append(
                {
                    "id": p.id,
                    "text": p.text,
                    "translation": t.get(locale) if locale and t.get(locale) else p.translation,
                    "translations": {"ru": p.translation, **t},
                }
            )
        out[n.id] = items
    return out


def _without_pending(nodes: list[dict], edges: list[dict]) -> tuple[list[dict], list[dict]]:
    """Drops steps still waiting for the AI and joins the route around them
    (A -> pending -> B becomes A -> B), so a learner walks only real steps."""
    # A video step with only its script (no file yet) is not watchable either.
    pending = {n["id"] for n in nodes if n.get("aiPending") or (n.get("type") == "video" and not n.get("mediaUrl"))}
    if not pending:
        return nodes, edges
    nxt = {e["fromNodeId"]: e for e in edges}
    kept_edges: list[dict] = []
    for n in nodes:
        if n["id"] in pending:
            continue
        edge = nxt.get(n["id"])
        seen: set[str] = set()
        while edge is not None and edge["toNodeId"] in pending and edge["toNodeId"] not in seen:
            seen.add(edge["toNodeId"])
            edge = nxt.get(edge["toNodeId"])
        if edge is not None and edge["toNodeId"] not in pending:
            kept_edges.append(edge if edge["fromNodeId"] == n["id"] else {**edge, "fromNodeId": n["id"]})
    return [n for n in nodes if n["id"] not in pending], kept_edges


def edge_dto(edge: LessonEdge) -> dict:
    return {"id": edge.id, "fromNodeId": edge.fromNodeId, "toNodeId": edge.toNodeId, "position": edge.position}


async def _real_nodes(db: AsyncSession, lesson_id: str) -> list[LessonNode]:
    # Ordered by creation time so the client's "which node came first" tie-
    # break (numbering unconnected/root nodes on the canvas, § lesson graph
    # follow-up) is deterministic across reloads, not query-plan-dependent.
    return (
        await db.execute(select(LessonNode).where(LessonNode.lessonId == lesson_id).order_by(LessonNode.createdAt))
    ).scalars().all()


async def _real_edges(db: AsyncSession, lesson_id: str) -> list[LessonEdge]:
    # Ordered so a node with several outgoing edges always comes back the
    # same way — the client's topological flatten (student route) breaks
    # ties by this exact order, so it must be deterministic.
    return (
        await db.execute(select(LessonEdge).where(LessonEdge.lessonId == lesson_id).order_by(LessonEdge.fromNodeId, LessonEdge.position))
    ).scalars().all()


async def bulk_graphs_for_lessons(db: AsyncSession, lesson_ids: list[str], locale: str | None = None, *, hide_pending: bool = False) -> dict[str, dict]:
    """For services/courses.py's get_course(): every REAL (already
    converted) graph among the given lessons, keyed by lessonId — a lesson
    absent from the result has no graph (still legacy). Never synthesizes a
    preview; that's a builder-only concept for the "Перевести в граф" flow,
    not something the shared course-read path should compute for every
    unconverted lesson on every request.

    `locale` (§ course content language, 2026-09-04) resolves each
    video/audio node's LessonNodeMedia row for that locale, when one
    exists — see node_dto's media_override param. No row for the requested
    locale falls back to the node's own base mediaUrl (the same "base
    column IS the ru text" convention as everywhere else in this feature)."""
    if not lesson_ids:
        return {}
    nodes = (
        await db.execute(select(LessonNode).where(LessonNode.lessonId.in_(lesson_ids)).order_by(LessonNode.lessonId, LessonNode.createdAt))
    ).scalars().all()
    if not nodes:
        return {}
    edges = (await db.execute(select(LessonEdge).where(LessonEdge.lessonId.in_(lesson_ids)))).scalars().all()
    media_by_node: dict[str, str] = {}
    if locale:
        node_ids = [n.id for n in nodes]
        media_rows = (
            await db.execute(select(LessonNodeMedia).where(LessonNodeMedia.lessonNodeId.in_(node_ids), LessonNodeMedia.locale == locale))
        ).scalars().all()
        media_by_node = {m.lessonNodeId: m.mediaUrl for m in media_rows}
    phrases_by_node = await _phrases_by_node(db, list(nodes), locale)
    by_lesson: dict[str, dict] = {}
    for n in nodes:
        by_lesson.setdefault(n.lessonId, {"nodes": [], "edges": []})["nodes"].append(node_dto(n, media_by_node.get(n.id), phrases_by_node.get(n.id)))
    for e in edges:
        by_lesson.setdefault(e.lessonId, {"nodes": [], "edges": []})["edges"].append(edge_dto(e))
    if hide_pending:
        # § course modules, 2026-10-05 — a learner never meets an empty
        # step that is still waiting for the AI.
        for graph in by_lesson.values():
            graph["nodes"], graph["edges"] = _without_pending(graph["nodes"], graph["edges"])
    return by_lesson


# ---------------------------------------------------------------------------
# Legacy -> graph synthesis (preview, and the one-time real conversion)
# ---------------------------------------------------------------------------


async def _synthesize_legacy_chain(db: AsyncSession, course_id: str, lesson: CourseLesson) -> list[dict]:
    """The lesson's CURRENT content, walked in the old fixed LESSON_CHAIN
    order, as a plain list of {type, refId, mediaUrl, title} — one entry per
    stage that actually has content, exactly mirroring what the old rail
    builder/runner show today (an empty stage is skipped here, since this
    only ever feeds a graph — see the module docstring on why an absent node
    is correct, not a regression, for a stage the teacher never filled in).
    Chaining these entries with LessonEdge rows in order is materialize()'s
    job; this function only decides WHAT the entries are."""
    chain: list[dict] = []

    has_words = await db.scalar(select(VocabularyItem.id).where(VocabularyItem.lessonId == lesson.id).limit(1))
    if not has_words:
        # § shared dictionary, 2026-09-14 — a lesson can teach vocabulary
        # purely by reuse (no native VocabularyItem row of its own), and
        # still needs its "Слова" node when converting to a graph.
        has_words = bool((await get_linked_items_by_lesson(db, [lesson.id])).get(lesson.id))
    if has_words:
        chain.append({"type": "vocabulary", "refId": None, "mediaUrl": None, "title": None})

    existing_material = (
        await db.execute(select(Material).where(Material.lessonId == lesson.id, Material.materialType == "text").limit(1))
    ).scalar_one_or_none()
    if existing_material:
        chain.append({"type": "material", "refId": existing_material.id, "mediaUrl": None, "title": None})
    elif lesson.materialText and lesson.materialText.strip():
        # No real Material row yet (the "Материал" step was never opened in
        # the old builder) but there IS flat legacy text — represented with
        # refId=None here; materialize() is what actually creates the
        # Material+MaterialBlock row to hold it, a preview never writes.
        chain.append({"type": "material", "refId": None, "mediaUrl": None, "title": None})

    if lesson.videoUrl:
        chain.append({"type": "video", "refId": None, "mediaUrl": lesson.videoUrl, "title": None})

    blocks = (
        await db.execute(select(LessonBlock).where(LessonBlock.lessonId == lesson.id).order_by(LessonBlock.stage, LessonBlock.position))
    ).scalars().all()
    by_stage: dict[str, list[LessonBlock]] = {}
    for b in blocks:
        by_stage.setdefault(b.stage, []).append(b)

    for b in by_stage.get("minitest", []):
        chain.append({"type": "minitest", "refId": b.id, "mediaUrl": None, "title": b.title})

    if lesson.audioUrl:
        chain.append({"type": "audio", "refId": None, "mediaUrl": lesson.audioUrl, "title": None})

    for b in by_stage.get("practice", []):
        chain.append({"type": "practice", "refId": b.id, "mediaUrl": None, "title": b.title})
    for b in by_stage.get("review", []):
        chain.append({"type": "review", "refId": b.id, "mediaUrl": None, "title": b.title})

    return chain


async def get_lesson_graph(db: AsyncSession, course_id: str, lesson_id: str) -> dict:
    lesson = await _owned_lesson(db, course_id, lesson_id)
    real_nodes = await _real_nodes(db, lesson_id)
    if real_nodes:
        edges = await _real_edges(db, lesson_id)
        phrases = await _phrases_by_node(db, real_nodes)
        return {"isLegacy": False, "nodes": [node_dto(n, None, phrases.get(n.id)) for n in real_nodes], "edges": [edge_dto(e) for e in edges]}

    chain = await _synthesize_legacy_chain(db, course_id, lesson)
    preview_nodes = [
        {"id": f"legacy:{i}:{entry['type']}", "type": entry["type"], "refId": entry["refId"], "mediaUrl": entry["mediaUrl"], "title": entry["title"] or DEFAULT_TITLES[entry["type"]], "posX": i * 260.0, "posY": 0.0}
        for i, entry in enumerate(chain)
    ]
    preview_edges = [
        {"id": f"legacy-edge:{i}", "fromNodeId": preview_nodes[i]["id"], "toNodeId": preview_nodes[i + 1]["id"], "position": 0}
        for i in range(len(preview_nodes) - 1)
    ]
    return {"isLegacy": True, "nodes": preview_nodes, "edges": preview_edges}


async def materialize_lesson_graph(db: AsyncSession, course_id: str, lesson_id: str) -> dict:
    """One-time "Перевести в граф" conversion. Persists real LessonNode/
    LessonEdge rows reproducing the lesson's current fixed-chain order
    exactly, referencing its EXISTING Material/LessonBlock rows (never
    duplicating them) — the only new content ever created here is a single
    Material+MaterialBlock pair, and only when the lesson has flat legacy
    materialText with no Material row yet (migrating its format, not
    duplicating a still-editable source — see Material's own docstring on
    why the flat field is designed to become inert once superseded).
    Raises 409 if this lesson already has a real graph."""
    lesson = await _owned_lesson(db, course_id, lesson_id)
    if await _real_nodes(db, lesson_id):
        raise ApiError(409, "Урок уже переведён в граф")

    chain = await _synthesize_legacy_chain(db, course_id, lesson)

    for entry in chain:
        if entry["type"] == "material" and entry["refId"] is None and lesson.materialText and lesson.materialText.strip():
            material = Material(courseId=course_id, lessonId=lesson.id, materialType="text", title=lesson.title, position=0)
            db.add(material)
            await db.flush()
            db.add(MaterialBlock(materialId=material.id, title="Материал", content=lesson.materialText, position=0))
            entry["refId"] = material.id

    nodes: list[LessonNode] = []
    for i, entry in enumerate(chain):
        node = LessonNode(
            courseId=course_id,
            lessonId=lesson.id,
            type=entry["type"],
            refId=entry["refId"],
            mediaUrl=entry["mediaUrl"],
            title=entry["title"],
            posX=i * 260.0,
            posY=0.0,
        )
        db.add(node)
        nodes.append(node)
    await db.flush()

    for i in range(len(nodes) - 1):
        db.add(LessonEdge(lessonId=lesson.id, fromNodeId=nodes[i].id, toNodeId=nodes[i + 1].id, position=0))

    await db.commit()
    return await get_lesson_graph(db, course_id, lesson_id)


# ---------------------------------------------------------------------------
# Node CRUD
# ---------------------------------------------------------------------------


async def create_node(
    db: AsyncSession,
    course_id: str,
    lesson_id: str,
    node_type: str,
    title: str | None,
    pos_x: float,
    pos_y: float,
    *,
    ai_task: str | None = None,
    ai_pending: bool = False,
    phrase_ids: list[str] | None = None,
    ai_task_ru: str | None = None,
    for_node_id: str | None = None,
    topic: str | None = None,
) -> dict:
    if node_type not in NODE_TYPES:
        raise ApiError(400, "Неизвестный тип блока")
    lesson = await _owned_lesson(db, course_id, lesson_id)
    if phrase_ids and node_type != "phrases":
        raise ApiError(400, "Фразы можно добавить только в блок «Фразы»")
    clean_phrase_ids = await _checked_phrase_ids(db, course_id, phrase_ids) if phrase_ids else None
    if for_node_id:
        await _check_for_node(db, lesson_id, node_type, for_node_id)
    topic_id = await _topic_id(db, course_id, topic) if topic else None
    if topic and node_type != "material":
        raise ApiError(400, "Тему можно указать только у шага «Материал»")

    ref_id: str | None = None
    if node_type == "material":
        existing = (await db.execute(select(Material).where(Material.lessonId == lesson.id))).scalars().all()
        material = Material(courseId=course_id, lessonId=lesson.id, materialType="text", title=title or lesson.title, position=len(existing), topicId=topic_id)
        db.add(material)
        await db.flush()
        ref_id = material.id
    elif node_type in _BLOCK_STAGES:
        existing = (
            await db.execute(select(LessonBlock).where(LessonBlock.lessonId == lesson.id, LessonBlock.stage == node_type))
        ).scalars().all()
        block = LessonBlock(
            id=str(uuid.uuid4()),
            courseId=course_id,
            lessonId=lesson.id,
            stage=node_type,
            title=title or f"{DEFAULT_TITLES[node_type]} {len(existing) + 1}",
            position=len(existing),
        )
        db.add(block)
        await db.flush()
        ref_id = block.id

    node = LessonNode(
        courseId=course_id,
        lessonId=lesson.id,
        type=node_type,
        refId=ref_id,
        title=title,
        posX=pos_x,
        posY=pos_y,
        phraseIds=clean_phrase_ids,
        aiTask=(ai_task or "").strip()[:4000] or None,
        aiTaskRu=(ai_task_ru or "").strip()[:4000] or None,
        aiPending=bool(ai_pending),
        forNodeId=for_node_id or None,
    )
    db.add(node)
    await db.commit()
    await db.refresh(node)
    return node_dto(node, None, (await _phrases_by_node(db, [node])).get(node.id))


TEST_STEP_TYPES = ("practice", "minitest", "review")


async def _check_for_node(db: AsyncSession, lesson_id: str, node_type: str, for_node_id: str) -> None:
    if node_type not in TEST_STEP_TYPES:
        raise ApiError(400, "Тест по аудио/видео может быть только шагом с вопросами")
    target = await db.get(LessonNode, for_node_id)
    if not target or target.lessonId != lesson_id or target.type not in ("audio", "video"):
        raise ApiError(400, "Тест можно привязать только к шагу «Аудио» или «Видео» этого урока")


async def _topic_id(db: AsyncSession, course_id: str, name: str) -> str:
    """An EXISTING topic of the course's language, by exact name (case-
    insensitive) — never creates one."""
    from app.models.topic import Topic

    language_id = await _course_language_id(db, course_id)
    rows = (await db.execute(select(Topic).where(Topic.languageId == language_id))).scalars().all()
    wanted = name.strip().lower()
    match = next((t for t in rows if t.name.strip().lower() == wanted), None)
    if not match:
        raise ApiError(404, f"Темы «{name}» нет в «Темах» этого языка")
    return match.id


async def _course_language_id(db: AsyncSession, course_id: str) -> str | None:
    course = await db.get(Course, course_id)
    level = await db.get(Level, course.levelId) if course and course.levelId else None
    return level.languageId if level else None


async def _checked_phrase_ids(db: AsyncSession, course_id: str, phrase_ids: list[str]) -> list[str]:
    """Keeps order, drops duplicates; every id must be a phrase of the
    course's own language."""
    ids = list(dict.fromkeys(i for i in phrase_ids if isinstance(i, str) and i))
    if not ids:
        return []
    language_id = await _course_language_id(db, course_id)
    if not language_id:
        raise ApiError(400, "Сначала выберите для курса язык и уровень")
    found = set((await db.execute(select(Phrase.id).where(Phrase.id.in_(ids), Phrase.languageId == language_id))).scalars().all())
    missing = [i for i in ids if i not in found]
    if missing:
        raise ApiError(400, f"Фразы не найдены в базе этого языка: {', '.join(missing[:5])}")
    return ids


async def _get_owned_node(db: AsyncSession, lesson_id: str, node_id: str) -> LessonNode:
    node = await db.get(LessonNode, node_id)
    if not node or node.lessonId != lesson_id:
        raise ApiError(404, "Блок не найден")
    return node


async def get_node(db: AsyncSession, lesson_id: str, node_id: str) -> LessonNode:
    """Public accessor for callers (e.g. the media-reuse endpoint) that only
    need to read the node, not mutate it."""
    return await _get_owned_node(db, lesson_id, node_id)


async def update_node(db: AsyncSession, lesson_id: str, node_id: str, changes: dict) -> dict:
    node = await _get_owned_node(db, lesson_id, node_id)
    for field in ("posX", "posY", "title"):
        if field in changes:
            setattr(node, field, changes[field])
    if "phraseIds" in changes:
        if node.type != "phrases":
            raise ApiError(400, "Фразы можно добавить только в блок «Фразы»")
        node.phraseIds = await _checked_phrase_ids(db, node.courseId, changes["phraseIds"] or [])
    if "aiTask" in changes:
        node.aiTask = (changes["aiTask"] or "").strip()[:4000] or None
    if "aiPending" in changes and changes["aiPending"] is not None:
        node.aiPending = bool(changes["aiPending"])
    if "aiTaskRu" in changes:
        node.aiTaskRu = (changes["aiTaskRu"] or "").strip()[:4000] or None
    if "forNodeId" in changes:
        if changes["forNodeId"]:
            await _check_for_node(db, lesson_id, node.type, changes["forNodeId"])
        node.forNodeId = changes["forNodeId"] or None
    if "topic" in changes:
        if node.type != "material" or not node.refId:
            raise ApiError(400, "Тему можно указать только у шага «Материал»")
        material = await db.get(Material, node.refId)
        material.topicId = await _topic_id(db, node.courseId, changes["topic"]) if changes["topic"] else None
    if "transcript" in changes or "transcriptTranslations" in changes:
        if node.type not in ("audio", "video"):
            raise ApiError(400, "Текст есть только у блоков «Аудио» и «Видео»")
        if "transcript" in changes:
            node.transcript = (changes["transcript"] or "").strip() or None
        if "transcriptTranslations" in changes:
            cleaned = {k: v.strip() for k, v in (changes["transcriptTranslations"] or {}).items() if isinstance(v, str) and v.strip()}
            node.transcriptTranslations = cleaned or None
    await db.commit()
    await db.refresh(node)
    return node_dto(node, None, (await _phrases_by_node(db, [node])).get(node.id))


async def set_node_media(db: AsyncSession, lesson_id: str, node_id: str, media_url: str | None) -> dict:
    node = await _get_owned_node(db, lesson_id, node_id)
    if node.type not in ("video", "audio"):
        raise ApiError(400, "У этого типа блока нет своего файла")
    previous = node.mediaUrl
    node.mediaUrl = media_url
    await db.commit()
    await db.refresh(node)
    return {"node": node_dto(node), "previousMediaUrl": previous}


async def set_node_media_translation(db: AsyncSession, lesson_id: str, node_id: str, locale: str, media_url: str | None) -> dict:
    """One locale's variant of a video/audio node's file (§ course content
    language, 2026-09-04) — writes LessonNodeMedia, never node.mediaUrl
    itself (that stays the pre-migration/default value — see
    LessonNodeMedia's docstring). `media_url=None` deletes that locale's
    row (the caller is responsible for cleaning up the underlying file, same
    as set_node_media)."""
    node = await _get_owned_node(db, lesson_id, node_id)
    if node.type not in ("video", "audio"):
        raise ApiError(400, "У этого типа блока нет своего файла")
    existing = (
        await db.execute(select(LessonNodeMedia).where(LessonNodeMedia.lessonNodeId == node_id, LessonNodeMedia.locale == locale))
    ).scalar_one_or_none()
    previous = existing.mediaUrl if existing else None
    if media_url is None:
        if existing:
            await db.delete(existing)
    elif existing:
        existing.mediaUrl = media_url
    else:
        db.add(LessonNodeMedia(lessonNodeId=node_id, locale=locale, mediaUrl=media_url))
    await db.commit()
    return {"node": node_dto(node, media_url), "previousMediaUrl": previous}


async def delete_node(db: AsyncSession, course_id: str, lesson_id: str, node_id: str) -> str | None:
    """Deletes the node, its edges, and its underlying content (a Material or
    LessonBlock the node was the only owner of) — reuses the same deletion
    shape services/courses.py's delete_block already applies to a LessonBlock
    (delete its LessonQuestion rows, then the block itself), just inlined
    here since that function commits and returns a whole-course dto that
    isn't useful for a node-scoped delete. Vocabulary/video/audio nodes own
    no content row, only the node itself and, for video/audio, its own
    mediaUrl string. Returns the removed mediaUrl (for the caller to clean up
    the uploaded file), or None if the node had none."""
    node = await _get_owned_node(db, lesson_id, node_id)

    edges = (
        await db.execute(select(LessonEdge).where(LessonEdge.lessonId == lesson_id, (LessonEdge.fromNodeId == node_id) | (LessonEdge.toNodeId == node_id)))
    ).scalars().all()
    for e in edges:
        await db.delete(e)

    if node.type == "material" and node.refId:
        material = await db.get(Material, node.refId)
        if material:
            await db.delete(material)  # cascades to MaterialBlock (ORM) -> QuestionPlacement (DB FK)
    elif node.type in _BLOCK_STAGES and node.refId:
        block = await db.get(LessonBlock, node.refId)
        if block:
            await db.execute(LessonQuestion.__table__.delete().where(LessonQuestion.blockId == block.id))
            await db.delete(block)

    removed_media_url = node.mediaUrl
    await db.delete(node)
    await db.commit()
    return removed_media_url


# ---------------------------------------------------------------------------
# Edge CRUD
# ---------------------------------------------------------------------------


async def _reachable(edges: list[LessonEdge], start: str) -> set[str]:
    by_from: dict[str, list[str]] = {}
    for e in edges:
        by_from.setdefault(e.fromNodeId, []).append(e.toNodeId)
    seen = {start}
    stack = [start]
    while stack:
        current = stack.pop()
        for nxt in by_from.get(current, []):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    return seen


async def add_edge(db: AsyncSession, course_id: str, lesson_id: str, from_node_id: str, to_node_id: str) -> dict:
    await _owned_lesson(db, course_id, lesson_id)
    if from_node_id == to_node_id:
        raise ApiError(400, "Нельзя соединить блок сам с собой")
    await _get_owned_node(db, lesson_id, from_node_id)
    await _get_owned_node(db, lesson_id, to_node_id)

    existing = (
        await db.execute(select(LessonEdge).where(LessonEdge.fromNodeId == from_node_id, LessonEdge.toNodeId == to_node_id))
    ).scalar_one_or_none()
    if existing:
        raise ApiError(409, "Такая связь уже есть")

    edges = await _real_edges(db, lesson_id)

    # Every node has at most one outgoing and one incoming flow edge (§
    # lesson graph follow-up, 2026-09-03 — a teacher-reported point of
    # confusion: several blocks feeding into one, or one block branching
    # into several, made the walk-through order hard to predict). This
    # keeps the graph a set of simple chains, so the student route is
    # always an unambiguous, fully numbered sequence — delete the existing
    # edge first to rewire either end.
    if any(e.fromNodeId == from_node_id for e in edges):
        raise ApiError(400, "У этого блока уже есть исходящая связь — сначала удалите её")
    if any(e.toNodeId == to_node_id for e in edges):
        raise ApiError(400, "У этого блока уже есть входящая связь — сначала удалите её")

    # Adding from -> to would close a cycle iff `to` can already reach `from`.
    if from_node_id in await _reachable(edges, to_node_id):
        raise ApiError(400, "Эта связь создала бы цикл в маршруте")

    last_position = max((e.position for e in edges if e.fromNodeId == from_node_id), default=-1)
    edge = LessonEdge(lessonId=lesson_id, fromNodeId=from_node_id, toNodeId=to_node_id, position=last_position + 1)
    db.add(edge)
    await db.commit()
    await db.refresh(edge)
    return edge_dto(edge)


async def delete_edge(db: AsyncSession, lesson_id: str, edge_id: str) -> bool:
    edge = await db.get(LessonEdge, edge_id)
    if not edge or edge.lessonId != lesson_id:
        return False
    await db.delete(edge)
    await db.commit()
    return True


async def set_route(db: AsyncSession, course_id: str, lesson_id: str, node_ids: list[str]) -> dict:
    """Replaces the whole route with one chain in the given order (§ course
    modules, 2026-10-05) and lays the steps out left to right. Every id must
    be a step of this lesson, each at most once; steps left out stay on the
    canvas, unconnected."""
    await _owned_lesson(db, course_id, lesson_id)
    nodes = {n.id: n for n in await _real_nodes(db, lesson_id)}
    if len(set(node_ids)) != len(node_ids):
        raise ApiError(400, "Шаг указан в маршруте дважды")
    unknown = [i for i in node_ids if i not in nodes]
    if unknown:
        raise ApiError(404, f"Шаг не найден в этом уроке: {unknown[0]}")
    for e in await _real_edges(db, lesson_id):
        await db.delete(e)
    await db.flush()
    for i, node_id in enumerate(node_ids):
        nodes[node_id].posX = i * 260.0
        nodes[node_id].posY = 0.0
    for a, b in zip(node_ids, node_ids[1:]):
        db.add(LessonEdge(lessonId=lesson_id, fromNodeId=a, toNodeId=b, position=0))
    await db.commit()
    return await get_lesson_graph(db, course_id, lesson_id)


# ---------------------------------------------------------------------------
# Keeping a converted lesson's graph in step with the linear editor
# ---------------------------------------------------------------------------
#
# A converted lesson can still be edited through the old linear rail (§
# linear view editable after conversion, 2026-10-03). Both views edit the
# SAME content rows — the graph only references them — so the only things
# that can fall out of step are the graph's own topology rows: a word list,
# Material or LessonBlock created through the rail has no node yet (so a
# learner walking the graph would never reach it), and a row deleted
# through the rail leaves a node pointing at nothing. The helpers below
# repair exactly that, and are a no-op for an unconverted lesson.


async def is_converted(db: AsyncSession, lesson_id: str) -> bool:
    return (await db.scalar(select(LessonNode.id).where(LessonNode.lessonId == lesson_id).limit(1))) is not None


async def first_node_of_type(db: AsyncSession, lesson_id: str, node_type: str) -> LessonNode | None:
    """The node the rail's single slot for this type maps to — the earliest
    one, in the same createdAt order the canvas numbers nodes by."""
    return (
        await db.execute(
            select(LessonNode).where(LessonNode.lessonId == lesson_id, LessonNode.type == node_type).order_by(LessonNode.createdAt).limit(1)
        )
    ).scalar_one_or_none()


async def _append_node(db: AsyncSession, course_id: str, lesson_id: str, node_type: str, ref_id: str | None = None, media_url: str | None = None) -> LessonNode:
    """Adds a node at the end of the learner route: to the right of every
    existing node, chained after the current tail. Flushes, never commits."""
    nodes = await _real_nodes(db, lesson_id)
    edges = await _real_edges(db, lesson_id)
    has_out = {e.fromNodeId for e in edges}
    has_in = {e.toNodeId for e in edges}
    # Prefer the end of a real chain over a stray unconnected node, latest
    # first, so the new node lands after what the learner actually walks.
    candidates = [n for n in nodes if n.id not in has_out]
    chained = [n for n in candidates if n.id in has_in]
    tail = (chained or candidates or [None])[-1]

    node = LessonNode(
        courseId=course_id,
        lessonId=lesson_id,
        type=node_type,
        refId=ref_id,
        mediaUrl=media_url,
        posX=max((n.posX for n in nodes), default=-260.0) + 260.0,
        posY=0.0,
    )
    db.add(node)
    await db.flush()
    if tail is not None:
        db.add(LessonEdge(lessonId=lesson_id, fromNodeId=tail.id, toNodeId=node.id, position=0))
        await db.flush()
    return node


async def _remove_node_keeping_route(db: AsyncSession, lesson_id: str, node: LessonNode) -> None:
    """Deletes one node and its edges, reconnecting its predecessor to its
    successor so the route stays one piece. Never touches content rows."""
    edges = await _real_edges(db, lesson_id)
    incoming = [e for e in edges if e.toNodeId == node.id]
    outgoing = [e for e in edges if e.fromNodeId == node.id]
    for e in incoming + outgoing:
        await db.delete(e)
    await db.flush()
    for i in incoming:
        for o in outgoing:
            if i.fromNodeId != o.toNodeId:
                db.add(LessonEdge(lessonId=lesson_id, fromNodeId=i.fromNodeId, toNodeId=o.toNodeId, position=0))
    await db.delete(node)
    await db.flush()


async def sync_graph_with_content(db: AsyncSession, lesson_id: str, *, words_changed: bool = False) -> None:
    """Makes a converted lesson's graph reference all of its content again
    after an edit through the linear rail: adds a node (at the end of the
    route) for a Material or LessonBlock that has none, and removes a node
    whose Material/LessonBlock no longer exists. A no-op for an unconverted
    lesson. Commits only when something changed.

    The word list is only considered when `words_changed` (a word was just
    added through the rail): deleting the "Слова" node in the graph leaves
    the words themselves in place, and an unrelated edit must not quietly
    put back a node the teacher removed on purpose."""
    nodes = await _real_nodes(db, lesson_id)
    if not nodes:
        return
    lesson = await db.get(CourseLesson, lesson_id)
    if not lesson:
        return
    changed = False

    material_ids = set((await db.execute(select(Material.id).where(Material.lessonId == lesson_id))).scalars().all())
    blocks = (
        await db.execute(select(LessonBlock).where(LessonBlock.lessonId == lesson_id).order_by(LessonBlock.stage, LessonBlock.position))
    ).scalars().all()
    block_ids = {b.id for b in blocks}

    for node in nodes:
        if (node.type == "material" and node.refId and node.refId not in material_ids) or (
            node.type in _BLOCK_STAGES and node.refId and node.refId not in block_ids
        ):
            await _remove_node_keeping_route(db, lesson_id, node)
            changed = True

    referenced = {n.refId for n in await _real_nodes(db, lesson_id) if n.refId}
    has_vocab_node = any(n.type == "vocabulary" for n in nodes)
    if words_changed and not has_vocab_node:
        has_words = await db.scalar(select(VocabularyItem.id).where(VocabularyItem.lessonId == lesson_id).limit(1))
        if not has_words:
            has_words = bool((await get_linked_items_by_lesson(db, [lesson_id])).get(lesson_id))
        if has_words:
            await _append_node(db, lesson.courseId, lesson_id, "vocabulary")
            changed = True

    # Only the rail's own material — the first "text" one, the same row its
    # "Материал" tab opens — and only when the graph has no material node
    # at all. Older non-text Material rows a lesson may carry were never
    # part of its route, and conversion deliberately left them out.
    if not any(n.type == "material" for n in await _real_nodes(db, lesson_id)):
        rail_material = (
            await db.execute(
                select(Material).where(Material.lessonId == lesson_id, Material.materialType == "text").order_by(Material.position).limit(1)
            )
        ).scalar_one_or_none()
        # The rail creates this row as soon as its tab is merely opened, so
        # wait for real content before putting it on the learner's route.
        has_content = rail_material is not None and (
            await db.scalar(select(MaterialBlock.id).where(MaterialBlock.materialId == rail_material.id).limit(1))
        ) is not None
        if has_content and rail_material.id not in referenced:
            await _append_node(db, lesson.courseId, lesson_id, "material", ref_id=rail_material.id)
            changed = True

    for block in blocks:
        if block.id not in referenced and block.stage in _BLOCK_STAGES:
            await _append_node(db, lesson.courseId, lesson_id, block.stage, ref_id=block.id)
            changed = True

    if changed:
        await db.commit()


async def set_first_node_media(db: AsyncSession, lesson: CourseLesson, kind: str, url: str | None) -> None:
    """The rail's single video/audio slot for a converted lesson: writes the
    first node of that type (creating one at the end of the route when
    there is none and a file is being set). Commits."""
    node = await first_node_of_type(db, lesson.id, kind)
    if node is None:
        if url is None:
            return
        await _append_node(db, lesson.courseId, lesson.id, kind, media_url=url)
    else:
        node.mediaUrl = url
    await db.commit()


async def set_first_node_media_translation(db: AsyncSession, lesson: CourseLesson, kind: str, locale: str, url: str | None) -> None:
    node = await first_node_of_type(db, lesson.id, kind)
    if node is None:
        if url is None:
            return
        node = await _append_node(db, lesson.courseId, lesson.id, kind)
        await db.commit()
    await set_node_media_translation(db, lesson.id, node.id, locale, url)


# ---------------------------------------------------------------------------
# «Сбросить заполнение ИИ» (§ AI reset, 2026-10-05)
# ---------------------------------------------------------------------------


async def _delete_questions(db: AsyncSession, placements: list) -> None:
    """Deletes these placements, and each question left with no placement."""
    from app.models.question import Question
    from app.models.question_placement import QuestionPlacement

    question_ids = {p.questionId for p in placements}
    for p in placements:
        await db.delete(p)
    await db.flush()
    for qid in question_ids:
        still = await db.scalar(select(QuestionPlacement.id).where(QuestionPlacement.questionId == qid).limit(1))
        if still is None:
            q = await db.get(Question, qid)
            if q:
                await db.delete(q)
    await db.flush()


async def reset_ai_steps(db: AsyncSession, course_id: str, lesson_id: str, node_id: str | None = None) -> dict:
    """Empties steps back to «ждёт ИИ»: one step, or every step of the lesson
    that has an AI task. Material blocks and their questions, the questions of
    question steps and the text of audio/video steps are deleted; the lesson's
    structure, words, phrases, uploaded files and plan stay. Questions in
    other steps that only *checked* a deleted material block keep their place
    and lose just that tag."""
    from app.models.question_placement import QuestionPlacement

    await _owned_lesson(db, course_id, lesson_id)
    nodes = await _real_nodes(db, lesson_id)
    if node_id:
        targets = [n for n in nodes if n.id == node_id]
        if not targets:
            raise ApiError(404, "Блок не найден")
    else:
        targets = [n for n in nodes if n.aiTask]
    if not targets:
        raise ApiError(400, "В уроке нет шагов с заданием для ИИ")
    reset = 0
    for node in targets:
        if node.type in ("vocabulary", "phrases"):
            continue
        if node.type == "material" and node.refId:
            block_ids = list((await db.execute(select(MaterialBlock.id).where(MaterialBlock.materialId == node.refId))).scalars().all())
            if block_ids:
                own = (
                    await db.execute(
                        select(QuestionPlacement).where(QuestionPlacement.materialBlockId.in_(block_ids), QuestionPlacement.lessonBlockId.is_(None))
                    )
                ).scalars().all()
                await _delete_questions(db, list(own))
                tagged = (
                    await db.execute(
                        select(QuestionPlacement).where(QuestionPlacement.materialBlockId.in_(block_ids), QuestionPlacement.lessonBlockId.isnot(None))
                    )
                ).scalars().all()
                for p in tagged:
                    p.materialBlockId = None
                await db.flush()
                for bid in block_ids:
                    block = await db.get(MaterialBlock, bid)
                    if block:
                        await db.delete(block)
        elif node.type in _BLOCK_STAGES and node.refId:
            placements = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.lessonBlockId == node.refId))).scalars().all()
            await _delete_questions(db, list(placements))
            await db.execute(LessonQuestion.__table__.delete().where(LessonQuestion.blockId == node.refId))
        elif node.type in ("audio", "video"):
            node.transcript = None
            node.transcriptTranslations = None
        node.aiPending = True
        reset += 1
    await db.commit()
    return {"reset": reset}
