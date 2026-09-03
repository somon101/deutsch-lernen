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
from app.models.material_block import MaterialBlock
from app.models.vocabulary_item import VocabularyItem
from app.services.content import LEGACY_COURSE_ID

NODE_TYPES = ("vocabulary", "material", "video", "audio", "minitest", "practice", "review")
# Node types backed by their own content row (as opposed to vocabulary/video/
# audio, which reference no row — see LessonNode's docstring).
_BLOCK_STAGES = ("minitest", "practice", "review")

DEFAULT_TITLES = {
    "vocabulary": "Слова",
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


def node_dto(node: LessonNode, media_override: str | None = None) -> dict:
    """`media_override` (§ course content language, 2026-09-04) is the
    resolved LessonNodeMedia row's URL for the caller's requested locale,
    when one exists — omitted (every admin-builder caller), this returns
    node.mediaUrl exactly as before."""
    return {
        "id": node.id,
        "type": node.type,
        "refId": node.refId,
        "mediaUrl": media_override if media_override is not None else node.mediaUrl,
        "title": node.title or DEFAULT_TITLES.get(node.type, node.type),
        "posX": node.posX,
        "posY": node.posY,
    }


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


async def bulk_graphs_for_lessons(db: AsyncSession, lesson_ids: list[str], locale: str | None = None) -> dict[str, dict]:
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
    by_lesson: dict[str, dict] = {}
    for n in nodes:
        by_lesson.setdefault(n.lessonId, {"nodes": [], "edges": []})["nodes"].append(node_dto(n, media_by_node.get(n.id)))
    for e in edges:
        by_lesson.setdefault(e.lessonId, {"nodes": [], "edges": []})["edges"].append(edge_dto(e))
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
        return {"isLegacy": False, "nodes": [node_dto(n) for n in real_nodes], "edges": [edge_dto(e) for e in edges]}

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


async def create_node(db: AsyncSession, course_id: str, lesson_id: str, node_type: str, title: str | None, pos_x: float, pos_y: float) -> dict:
    if node_type not in NODE_TYPES:
        raise ApiError(400, "Неизвестный тип блока")
    lesson = await _owned_lesson(db, course_id, lesson_id)

    ref_id: str | None = None
    if node_type == "material":
        existing = (await db.execute(select(Material).where(Material.lessonId == lesson.id))).scalars().all()
        material = Material(courseId=course_id, lessonId=lesson.id, materialType="text", title=title or lesson.title, position=len(existing))
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

    node = LessonNode(courseId=course_id, lessonId=lesson.id, type=node_type, refId=ref_id, title=title, posX=pos_x, posY=pos_y)
    db.add(node)
    await db.commit()
    await db.refresh(node)
    return node_dto(node)


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
    await db.commit()
    await db.refresh(node)
    return node_dto(node)


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
