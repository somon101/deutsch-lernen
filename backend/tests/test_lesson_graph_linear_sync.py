# -*- coding: utf-8 -*-
"""Linear rail edits on a converted lesson keep its graph complete (§ linear
view editable after conversion, 2026-10-03).

Runs against a real, throwaway PostgreSQL database (TEST_DATABASE_URL, e.g.
postgresql://postgres@localhost:5433/t) because the behavior under test is
exactly which LessonNode/LessonEdge rows exist afterwards. Creates every
table from the models, then drops them again.
"""
import asyncio
import os
import sys
import uuid

os.environ.setdefault("JWT_SECRET", "test")
os.environ.setdefault("DATABASE_URL", os.environ.get("TEST_DATABASE_URL", ""))

if not os.environ.get("TEST_DATABASE_URL"):
    print("SKIP: set TEST_DATABASE_URL to a throwaway PostgreSQL database")
    sys.exit(0)

from sqlalchemy import select, text  # noqa: E402

from app import models  # noqa: E402,F401  (registers every table)
from app.db import Base, async_session, engine  # noqa: E402
from app.models.course import Course  # noqa: E402
from app.models.course_lesson import CourseLesson  # noqa: E402
from app.models.lesson_block import LessonBlock  # noqa: E402
from app.models.lesson_edge import LessonEdge  # noqa: E402
from app.models.lesson_node import LessonNode  # noqa: E402
from app.models.material import Material  # noqa: E402
from app.models.material_block import MaterialBlock  # noqa: E402
from app.models.vocabulary_item import VocabularyItem  # noqa: E402
from app.services import courses, lesson_graph  # noqa: E402

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("  PASS  " if cond else "  FAIL  ") + name + (f"\n           -> {detail}" if detail and not cond else ""))


async def make_lesson(db, *, with_block=True, video=None):
    course = Course(id=str(uuid.uuid4()), title="C", description="", position=0)
    db.add(course)
    await db.flush()
    lesson = CourseLesson(id=str(uuid.uuid4()), courseId=course.id, title="L", description="", position=0, videoUrl=video)
    db.add(lesson)
    await db.flush()
    if with_block:
        db.add(LessonBlock(id=str(uuid.uuid4()), courseId=course.id, lessonId=lesson.id, stage="minitest", title="T1", position=0))
    await db.commit()
    return course, lesson


async def route(db, lesson_id):
    """Node types in learner order (follows the single-successor chain)."""
    nodes = {n.id: n for n in (await db.execute(select(LessonNode).where(LessonNode.lessonId == lesson_id))).scalars()}
    edges = (await db.execute(select(LessonEdge).where(LessonEdge.lessonId == lesson_id))).scalars().all()
    nxt = {e.fromNodeId: e.toNodeId for e in edges}
    starts = [nid for nid in nodes if nid not in {e.toNodeId for e in edges}]
    out = []
    for s in sorted(starts, key=lambda i: nodes[i].createdAt):
        cur = s
        while cur:
            out.append(nodes[cur].type)
            cur = nxt.get(cur)
    return out


async def main():
    async with engine.begin() as conn:
        await conn.execute(text("DROP SCHEMA public CASCADE"))
        await conn.execute(text("CREATE SCHEMA public"))
        for enum_sql in (
            "CREATE TYPE \"Role\" AS ENUM ('ADMIN','TEACHER','USER')",
            "CREATE TYPE \"UserStatus\" AS ENUM ('ACTIVE','BLOCKED')",
            "CREATE TYPE \"CourseStatus\" AS ENUM ('DRAFT','PUBLISHED')",
        ):
            await conn.execute(text(enum_sql))
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as db:
        print("=== Unconverted lesson: everything is a no-op ===")
        course, lesson = await make_lesson(db, video="old.mp4")
        await lesson_graph.sync_graph_with_content(db, lesson.id)
        check("no nodes created", await route(db, lesson.id) == [])
        await courses.set_lesson_media(db, course.id, lesson.id, "video", "new.mp4")
        await db.refresh(lesson)
        check("video still written to the lesson column", lesson.videoUrl == "new.mp4", lesson.videoUrl)

        print("\n=== Converted lesson: new content joins the end of the route ===")
        course, lesson = await make_lesson(db)
        await lesson_graph.materialize_lesson_graph(db, course.id, lesson.id)
        check("conversion: one minitest node", await route(db, lesson.id) == ["minitest"], await route(db, lesson.id))

        db.add(VocabularyItem(courseId=course.id, lessonId=lesson.id, german="sprechen", germanKey="sprechen", translation="говорить", pronunciation="", position=0))
        await db.commit()
        await lesson_graph.sync_graph_with_content(db, lesson.id)
        check("unrelated sync does not add a words node", await route(db, lesson.id) == ["minitest"], await route(db, lesson.id))
        await lesson_graph.sync_graph_with_content(db, lesson.id, words_changed=True)
        check("first word -> vocabulary node at the end", await route(db, lesson.id) == ["minitest", "vocabulary"], await route(db, lesson.id))

        material = Material(courseId=course.id, lessonId=lesson.id, materialType="text", title="M", position=0)
        db.add(material)
        await db.commit()
        await lesson_graph.sync_graph_with_content(db, lesson.id)
        check("empty material (tab just opened) stays off the route", "material" not in await route(db, lesson.id))
        db.add(MaterialBlock(materialId=material.id, title="B", content="text", position=0))
        await db.commit()
        await lesson_graph.sync_graph_with_content(db, lesson.id)
        check("material with content -> material node", await route(db, lesson.id) == ["minitest", "vocabulary", "material"], await route(db, lesson.id))

        await courses.create_block(db, course.id, lesson.id, "practice", "P1")
        await lesson_graph.sync_graph_with_content(db, lesson.id)
        check("new practice block -> node", await route(db, lesson.id) == ["minitest", "vocabulary", "material", "practice"], await route(db, lesson.id))

        await lesson_graph.sync_graph_with_content(db, lesson.id)
        count = len((await db.execute(select(LessonNode).where(LessonNode.lessonId == lesson.id))).scalars().all())
        check("sync is idempotent", count == 4, count)

        print("\n=== Deleting through the rail removes the node, route stays whole ===")
        vocab_block = (await db.execute(select(LessonBlock).where(LessonBlock.lessonId == lesson.id, LessonBlock.stage == "minitest"))).scalar_one()
        await courses.delete_block(db, course.id, lesson.id, vocab_block.id)
        await lesson_graph.sync_graph_with_content(db, lesson.id)
        check("first node removed, rest still chained", await route(db, lesson.id) == ["vocabulary", "material", "practice"], await route(db, lesson.id))
        mid = (await db.execute(select(Material).where(Material.id == material.id))).scalar_one()
        await db.delete(mid)
        await db.commit()
        await lesson_graph.sync_graph_with_content(db, lesson.id)
        check("middle node removed, neighbors reconnected", await route(db, lesson.id) == ["vocabulary", "practice"], await route(db, lesson.id))

        print("\n=== Video/audio: the rail edits the first graph node ===")
        course_dto = await courses.set_lesson_media(db, course.id, lesson.id, "video", "v1.mp4")
        check("no video node yet -> one is appended", await route(db, lesson.id) == ["vocabulary", "practice", "video"], await route(db, lesson.id))
        await db.refresh(lesson)
        check("lesson column untouched", lesson.videoUrl is None, lesson.videoUrl)
        dto = next(l for l in course_dto["lessons"] if l["id"] == lesson.id)
        check("lesson dto shows the node's video", dto["videoUrl"] == "v1.mp4", dto["videoUrl"])
        await courses.set_lesson_media(db, course.id, lesson.id, "video", "v2.mp4")
        nodes = (await db.execute(select(LessonNode).where(LessonNode.lessonId == lesson.id, LessonNode.type == "video"))).scalars().all()
        check("replacing updates the same node", len(nodes) == 1 and nodes[0].mediaUrl == "v2.mp4", [n.mediaUrl for n in nodes])
        check("node media counts as in use", await courses.media_url_still_in_use(db, "v2.mp4", course_lesson_id=lesson.id))
        check("replaced file is no longer in use", not await courses.media_url_still_in_use(db, "v1.mp4", course_lesson_id=lesson.id))
        await courses.set_lesson_media(db, course.id, lesson.id, "video", None)
        await db.refresh(nodes[0])
        check("removing clears the node's file, keeps the node", nodes[0].mediaUrl is None and "video" in await route(db, lesson.id))

    async with engine.begin() as conn:
        await conn.execute(text("DROP SCHEMA public CASCADE"))
        await conn.execute(text("CREATE SCHEMA public"))
    await engine.dispose()

    failed = [n for n, ok in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed")
    sys.exit(1 if failed else 0)


asyncio.run(main())
