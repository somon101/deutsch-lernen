# -*- coding: utf-8 -*-
"""AI lesson generator, phrase base and AI settings (§ AI lesson generator,
2026-10-03).

Runs against a real, throwaway PostgreSQL database (TEST_DATABASE_URL), with
the DeepSeek call replaced by a fixed reply, so it checks exactly what ends
up in the database: which nodes, edges, blocks, questions and placements a
generated lesson consists of.
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

from app import models  # noqa: E402,F401
from app.db import Base, async_session, engine  # noqa: E402
from app.errors import ApiError  # noqa: E402
from app.models.ai_settings import AiSettings  # noqa: E402
from app.models.course import Course  # noqa: E402
from app.models.course_lesson import CourseLesson  # noqa: E402
from app.models.language import Language  # noqa: E402
from app.models.lesson_edge import LessonEdge  # noqa: E402
from app.models.lesson_node import LessonNode  # noqa: E402
from app.models.lesson_vocabulary_link import LessonVocabularyLink  # noqa: E402
from app.models.level import Level  # noqa: E402
from app.models.material import Material  # noqa: E402
from app.models.material_block import MaterialBlock  # noqa: E402
from app.models.material_block_translation import MaterialBlockTranslation  # noqa: E402
from app.models.question import Question  # noqa: E402
from app.models.question_placement import QuestionPlacement  # noqa: E402
from app.models.question_translation import QuestionTranslation  # noqa: E402
from app.models.vocabulary_item import VocabularyItem  # noqa: E402
from app.services import ai_client, ai_lessons, ai_settings, phrases  # noqa: E402

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("  PASS  " if cond else "  FAIL  ") + name + (f"\n           -> {detail}" if detail and not cond else ""))


def fake_reply(captured):
    async def chat_json(api_key, model, system, user, **kw):
        captured.append({"key": api_key, "user": user})
        return {
            "title": "Hello!",
            "title_tg": "Салом!",
            "topic": "Приветствия",
            "wordIds": ["w1", "w2", "w3", "w4", "w99", "not-an-id"],
            "phraseIds": ["p1"],
            "blocks": [
                {
                    "title": "Приветствия",
                    "title_tg": "Саломҳо",
                    "content": "Hello и Hi — привет.",
                    "content_tg": "Hello ва Hi — салом.",
                    "questions": [
                        {"kind": "choice", "prompt": "Как сказать «привет»?", "prompt_tg": "Салом чӣ тавр?", "options": ["Hello", "Bye", "Thanks"], "correctAnswer": "Hello"},
                        {"kind": "choice", "prompt": "Плохой вопрос", "options": ["A", "B"], "correctAnswer": "C"},
                    ],
                },
                {
                    "title": "Глагол to be",
                    "content": "I am, you are.",
                    "questions": [
                        {"kind": "cloze", "prompt": "I ___ Ali.", "options": ["am", "is", "are"], "correctAnswer": "am"},
                        {"kind": "truefalse", "prompt": "«Hi» — официальное приветствие.", "correct": False},
                        {"kind": "scramble", "prompt": "Ты мой друг", "correctAnswer": "You are my friend"},
                    ],
                },
                {"title": "", "content": "без заголовка"},
            ],
            "audio": {"transcript": "Hello. My name is Ali.", "translation_ru": "Привет. Меня зовут Али.", "translation_tg": "Салом. Номи ман Алӣ."},
            "practice": {"translateCount": 8, "matchPairs": 5, "blankPhraseIds": ["p1", "p2"]},
            "minitest": [
                {"kind": "choice", "prompt": "Привет?", "options": ["Hello", "Bye"], "correctAnswer": "Hello", "verifiesBlock": 0},
                {"kind": "match", "prompt": "Сопоставьте", "pairs": [{"left": "hello", "right": "привет"}, {"left": "bye", "right": "пока"}], "verifiesBlock": 7},
                {"kind": "nonsense", "prompt": "?"},
            ],
        }

    return chat_json


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
        print("=== AI settings: key stored encrypted, never echoed ===")
        dto = ai_settings.settings_dto(await ai_settings.get_ai_settings(db))
        check("no key initially", dto["hasKey"] is False)
        row = await ai_settings.update_ai_settings(db, api_key="sk-test-1234567890abcd")
        check("ciphertext in DB, not plaintext", row.apiKeyEncrypted and "sk-test" not in row.apiKeyEncrypted)
        key, model = await ai_settings.get_api_key(db)
        check("key round-trips", key == "sk-test-1234567890abcd" and model == "deepseek-chat")
        dto = ai_settings.settings_dto(row)
        check("dto shows only hint", dto["hasKey"] and dto["keyHint"] == "abcd" and "sk-test" not in str(dto))

        print("\n=== Setup: language, level, course, dictionary, phrases ===")
        lang = Language(id=str(uuid.uuid4()), name="Английский")
        db.add(lang)
        await db.flush()
        level = Level(id=str(uuid.uuid4()), languageId=lang.id, code="A0", name="С нуля", position=0)
        db.add(level)
        await db.flush()
        other = Course(id=str(uuid.uuid4()), title="Другой курс", description="", position=0)
        db.add(other)
        await db.flush()
        other_lesson = CourseLesson(id=str(uuid.uuid4()), courseId=other.id, title="x", description="", position=0)
        db.add(other_lesson)
        await db.flush()
        for i, (en, ru) in enumerate([("hello", "привет"), ("hi", "привет"), ("bye", "пока"), ("thanks", "спасибо"), ("please", "пожалуйста")]):
            db.add(VocabularyItem(courseId=other.id, lessonId=other_lesson.id, german=en, germanKey=en, translation=ru, pronunciation="", position=i, languageId=lang.id))
        course = Course(id=str(uuid.uuid4()), title="English A0", description="С нуля", position=1, levelId=level.id)
        db.add(course)
        await db.commit()
        imported = await phrases.import_phrases(
            db, lang.id, [{"text": "Nice to meet you", "translation": "Приятно познакомиться", "translation_tg": "Аз шиносоӣ шодам", "topic": "Знакомство"},
                          {"text": "How are you?", "translation": "Как дела?"}, {"text": "nice to meet you", "translation": "дубль"}]
        )
        check("phrase import skips duplicates", imported == {"added": 2, "skipped": 1}, imported)
        listed = await phrases.list_phrases(db, language_id=lang.id, query="meet")
        check("phrase search + tg translation + topic", listed["total"] == 1 and listed["phrases"][0]["translations"].get("tg") == "Аз шиносоӣ шодам" and listed["phrases"][0]["topicName"] == "Знакомство", listed)

        print("\n=== Preview: nothing written, invalid parts dropped with warnings ===")
        captured = []
        ai_client.chat_json = fake_reply(captured)
        preview = await ai_lessons.preview_lesson(db, course.id, instructions="Тема: приветствия", previous=[])
        lesson = preview["lesson"]
        check("prompt carries words under aliases", "w1: bye — пока" in captured[0]["user"] and "Тема: приветствия" in captured[0]["user"], captured[0]["user"][:400])
        check("decrypted key sent to provider", captured[0]["key"] == "sk-test-1234567890abcd")
        check("unknown word aliases dropped", len(lesson["wordIds"]) == 4 and len(lesson["words"]) == 4, lesson["wordIds"])
        check("block without title dropped", len(lesson["blocks"]) == 2)
        check("invalid choice dropped, valid kept", len(lesson["blocks"][0]["questions"]) == 1 and len(lesson["blocks"][1]["questions"]) == 3)
        check("unknown kind dropped, bad verifiesBlock -> None", len(lesson["minitest"]) == 2 and lesson["minitest"][1]["verifiesBlock"] is None)
        check("matchPairs snapped to an allowed count", lesson["practice"]["matchPairs"] == 4, lesson["practice"])
        check("warnings explain drops", len(preview["warnings"]) >= 4, preview["warnings"])
        check("preview wrote no lesson", (await db.scalar(select(CourseLesson.id).where(CourseLesson.courseId == course.id))) is None)

        print("\n=== Apply: an ordinary graph lesson ===")
        result = await ai_lessons.apply_plans(db, course.id, [lesson])
        lesson_id = result["lessonIds"][0]
        nodes = (await db.execute(select(LessonNode).where(LessonNode.lessonId == lesson_id).order_by(LessonNode.createdAt))).scalars().all()
        check("route vocabulary→material→audio→practice→minitest", [n.type for n in nodes] == ["vocabulary", "material", "audio", "practice", "minitest"], [n.type for n in nodes])
        edges = (await db.execute(select(LessonEdge).where(LessonEdge.lessonId == lesson_id))).scalars().all()
        chain = {e.fromNodeId: e.toNodeId for e in edges}
        check("nodes chained by edges", all(chain.get(a.id) == b.id for a, b in zip(nodes, nodes[1:])) and len(edges) == 4)
        links = (await db.execute(select(LessonVocabularyLink).where(LessonVocabularyLink.lessonId == lesson_id))).scalars().all()
        check("4 dictionary words linked (not copied)", len(links) == 4)
        material = await db.get(Material, nodes[1].refId)
        blocks = (await db.execute(select(MaterialBlock).where(MaterialBlock.materialId == material.id).order_by(MaterialBlock.position))).scalars().all()
        check("material titled by topic with Topic set", material.title == "Приветствия" and material.topicId is not None)
        check("2 material blocks", [b.title for b in blocks] == ["Приветствия", "Глагол to be"])
        tg = (await db.execute(select(MaterialBlockTranslation).where(MaterialBlockTranslation.materialBlockId == blocks[0].id))).scalar_one_or_none()
        check("block tg translation", tg and tg.content == "Hello ва Hi — салом.")
        on_block = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.materialBlockId == blocks[1].id, QuestionPlacement.lessonBlockId.is_(None)))).scalars().all()
        check("block questions placed on the block", len(on_block) == 3)
        q_tg = (await db.execute(select(QuestionTranslation).where(QuestionTranslation.locale == "tg"))).scalars().all()
        check("question tg prompt stored", any(t.prompt == "Салом чӣ тавр?" for t in q_tg))
        check("audio transcript + translations, no file", nodes[2].transcript == "Hello. My name is Ali." and nodes[2].transcriptTranslations.get("tg") and nodes[2].mediaUrl is None)
        practice_q = (
            await db.execute(select(Question).join(QuestionPlacement, QuestionPlacement.questionId == Question.id).where(QuestionPlacement.lessonBlockId == nodes[3].refId))
        ).scalars().all()
        kinds = sorted(q.kind for q in practice_q)
        check("practice = auto_blank + auto_match + auto_translate", kinds == ["auto_blank", "auto_match", "auto_translate"], kinds)
        blank = next(q for q in practice_q if q.kind == "auto_blank")
        check("auto_blank uses phrase texts", sorted(blank.data["phrases"]) == ["How are you?", "Nice to meet you"], blank.data)
        mt = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.lessonBlockId == nodes[4].refId))).scalars().all()
        check("minitest question verifies block 1", sorted([p.materialBlockId == blocks[0].id for p in mt]) == [False, True], [p.materialBlockId for p in mt])
        lesson_row = await db.get(CourseLesson, lesson_id)
        check("lesson title", lesson_row.title == "Hello!")

        print("\n=== Next preview excludes words already in the course ===")
        await ai_lessons.preview_lesson(db, course.id, instructions=None, previous=[])
        check("only the unused word is offered", captured[-1]["user"].count(" — ") - captured[-1]["user"].count("PHRASES") >= 1 and "hello — привет" not in captured[-1]["user"], captured[-1]["user"][-500:])

        print("\n=== Guards ===")
        await ai_settings.update_ai_settings(db, api_key="")
        try:
            await ai_lessons.preview_lesson(db, course.id, instructions=None, previous=[])
            check("no key -> refused", False)
        except ApiError as e:
            check("no key -> refused", e.status_code == 400)
        check("key removed", (await db.get(AiSettings, "singleton")).apiKeyEncrypted is None)

    async with engine.begin() as conn:
        await conn.execute(text("DROP SCHEMA public CASCADE"))
        await conn.execute(text("CREATE SCHEMA public"))
    await engine.dispose()

    failed = [n for n, ok in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed")
    sys.exit(1 if failed else 0)


asyncio.run(main())
