# -*- coding: utf-8 -*-
"""Course modules, lesson plans, the «Фразы» step, steps waiting for the AI,
«Заполнить с ИИ» and API-key permissions (§ course modules, 2026-10-05).

Runs on a throwaway SQLite file (no Postgres needed): JSONB/ARRAY are
stored as JSON and the DeepSeek call is replaced by a fixed reply.
Run from backend/: venv/Scripts/python tests/test_course_modules.py
"""
import asyncio
import os
import sys
from datetime import timedelta

os.environ.setdefault("JWT_SECRET", "test")
os.environ["DATABASE_URL"] = "postgresql://u:p@localhost/x"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sqlalchemy  # noqa: E402


class _ListAsJson(sqlalchemy.JSON):
    """SQLite stand-in for ARRAY(String): stores the list as JSON."""

    def __init__(self, *args, **kwargs):
        super().__init__()


sqlalchemy.ARRAY = _ListAsJson
from sqlalchemy.dialects.postgresql import JSONB  # noqa: E402
from sqlalchemy.ext.compiler import compiles  # noqa: E402


@compiles(JSONB, "sqlite")
def _jsonb_sqlite(element, compiler, **kw):
    return "JSON"


from sqlalchemy import ARRAY  # noqa: E402
from sqlalchemy.dialects.postgresql import ARRAY as PG_ARRAY  # noqa: E402


@compiles(ARRAY, "sqlite")
@compiles(PG_ARRAY, "sqlite")
def _array_sqlite(element, compiler, **kw):
    return "JSON"


import httpx  # noqa: E402
from sqlalchemy import select  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine  # noqa: E402

from app import models  # noqa: E402,F401
from app.auth import deps  # noqa: E402
from app.db import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402
from app.models.api_key import ApiKey  # noqa: E402
from app.models.course_lesson import CourseLesson  # noqa: E402
from app.models.enums import Role  # noqa: E402
from app.models.language import Language  # noqa: E402
from app.models.lesson_edge import LessonEdge  # noqa: E402
from app.models.lesson_node import LessonNode  # noqa: E402
from app.models.level import Level  # noqa: E402
from app.models.material_block import MaterialBlock  # noqa: E402
from app.models.phrase import Phrase, PhraseTranslation  # noqa: E402
from app.models.question_placement import QuestionPlacement  # noqa: E402
from app.models.vocabulary_item import VocabularyItem  # noqa: E402
from app.services import ai_client, ai_settings, courses as courses_svc  # noqa: E402
from app.utils import utcnow  # noqa: E402

import tempfile  # noqa: E402

DB = os.path.join(tempfile.gettempdir(), "payroha_course_build_test.db")
if os.path.exists(DB):
    os.remove(DB)
engine = create_async_engine(f"sqlite+aiosqlite:///{DB}")
Session = async_sessionmaker(engine, expire_on_commit=False)

results = []


def check(name, cond, detail=""):
    results.append(bool(cond))
    print(("  PASS  " if cond else "  FAIL  ") + name + (f"\n           -> {detail}" if not cond and detail != "" else ""))


async def override_db():
    async with Session() as s:
        yield s


class FakeUser:
    id = "admin-1"
    role = Role.ADMIN
    contentLocale = "tg"


async def main():
    from sqlalchemy import DefaultClause, text as sql_text

    for table in Base.metadata.tables.values():
        for col in table.columns:
            if col.server_default is not None and "now()" in str(getattr(col.server_default, "arg", "")):
                col.server_default = DefaultClause(sql_text("CURRENT_TIMESTAMP"))
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with Session() as db:
        en = Language(id="en", name="English", position=0) if hasattr(Language, "position") else Language(id="en", name="English")
        de = Language(id="de", name="Deutsch", position=1) if hasattr(Language, "position") else Language(id="de", name="Deutsch")
        db.add_all([en, de])
        await db.flush()
        db.add_all([Level(id="en-a1", languageId="en", code="A1", name="Beginner", position=0), Level(id="de-a1", languageId="de", code="A1", name="Anfänger", position=0)])
        for i, (w, t) in enumerate([("I", "я"), ("you", "ты"), ("teacher", "учитель"), ("student", "студент"), ("friend", "друг"), ("name", "имя")]):
            db.add(VocabularyItem(id=f"w{i}", lessonId="dictionary-en", courseId="dictionary-en", german=w, germanKey=w.lower(), translation=t, position=i, languageId="en"))
        db.add(VocabularyItem(id="wde", lessonId="dictionary-de", courseId="dictionary-de", german="Tisch", germanKey="tisch", translation="стол", position=0, languageId="de"))
        db.add_all([
            Phrase(id="p1", languageId="en", text="Nice to meet you", translation="Приятно познакомиться"),
            Phrase(id="p2", languageId="en", text="My name is ...", translation="Меня зовут ..."),
            Phrase(id="pde", languageId="de", text="Guten Tag", translation="Добрый день"),
        ])
        await db.flush()
        db.add(PhraseTranslation(phraseId="p1", locale="tg", translation="Аз шиносоӣ хурсандам"))
        from app.models.topic import Topic
        db.add(Topic(id="t1", languageId="en", name="Приветствия", createdAt=utcnow()))
        await db.commit()

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[deps.require_staff] = lambda: FakeUser()
    app.dependency_overrides[deps.require_admin] = lambda: FakeUser()

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
        # ---------------- keys and permissions
        r = await c.post("/api/languages/en/api-keys", json={"name": "Читалка"})
        ro = r.json()["key"]
        check("new key without choice is read-only", ro["permissions"] == ["words:read", "phrases:read", "topics:read", "courses:read"], ro["permissions"])
        r = await c.post("/api/languages/en/api-keys", json={"name": "Курс", "permissions": ["courses:write", "words:read", "phrases:read", "topics:read"], "expiresInDays": 7})
        build = r.json()["key"]
        check("write implies read", "courses:read" in build["permissions"] and "courses:delete" not in build["permissions"], build["permissions"])
        check("expiry set", build["expiresAt"] is not None and not build["expired"])
        r = await c.post("/api/languages/en/api-keys", json={"name": "bad", "permissions": ["courses:publish"]})
        check("unknown permission refused", r.status_code == 400, r.text)
        H = {"X-API-Key": build["key"]}
        RO = {"X-API-Key": ro["key"]}

        # legacy key (permissions NULL) keeps word/phrase/topic rights only
        async with Session() as db:
            from app.services.api_keys import _hash
            db.add(ApiKey(id="legacy", languageId="en", name="old", keyHash=_hash("pk_legacy"), prefix="pk_legacy", createdAt=utcnow()))
            db.add(ApiKey(id="exp", languageId="en", name="exp", keyHash=_hash("pk_expired"), prefix="pk_expire", createdAt=utcnow(), permissions=["words:read"], expiresAt=utcnow() - timedelta(days=1)))
            await db.commit()
        r = await c.delete("/api/v1/words/w2", headers={"X-API-Key": "pk_legacy"})
        check("legacy key: delete words still allowed (409 = reached handler, word unused -> 200)", r.status_code in (200, 409), r.text)
        r = await c.get("/api/v1/courses", headers={"X-API-Key": "pk_legacy"})
        check("legacy key: no course access (403)", r.status_code == 403, r.text)
        r = await c.get("/api/v1/words", headers={"X-API-Key": "pk_expired"})
        check("expired key -> 401", r.status_code == 401 and "истёк" in r.json().get("error", ""), r.text)
        r = await c.post("/api/v1/courses", headers=RO, json={"title": "X", "levelId": "en-a1"})
        check("read-only key cannot create course (403)", r.status_code == 403, r.text)
        r = await c.post("/api/v1/words", headers=H, json={"word": "x", "translation": "y", "translation_tg": "z"})
        check("build key cannot write words (403)", r.status_code == 403, r.text)
        r = await c.get("/api/v1/language", headers=H)
        check("/language shows permissions", "courses:write" in r.json().get("permissions", []), r.text)

        # ---------------- build a course
        r = await c.get("/api/v1/levels", headers=H)
        check("levels of own language only", [l["id"] for l in r.json()["levels"]] == ["en-a1"], r.text)
        r = await c.post("/api/v1/courses", headers=H, json={"title": "English A1", "levelId": "de-a1"})
        check("foreign level -> 404", r.status_code == 404, r.text)
        r = await c.post("/api/v1/courses", headers=H, json={"title": "English A1", "title_tg": "Англисӣ A1", "description": "d", "levelId": "en-a1"})
        check("course created", r.status_code == 201, r.text)
        course = r.json()["course"]
        cid = course["id"]
        check("course is a draft", course["status"] == "DRAFT" and course["title_tg"] == "Англисӣ A1", course)

        m1 = (await c.post(f"/api/v1/courses/{cid}/modules", headers=H, json={"title": "Знакомство", "title_tg": "Шиносоӣ"})).json()["module"]
        m2 = (await c.post(f"/api/v1/courses/{cid}/modules", headers=H, json={"title": "Семья"})).json()["module"]
        lb = (await c.post(f"/api/v1/courses/{cid}/lessons", headers=H, json={"title": "Семья 1", "moduleId": m2["id"]})).json()["lesson"]
        la = (await c.post(f"/api/v1/courses/{cid}/lessons", headers=H, json={"title": "Привет", "title_tg": "Салом", "moduleId": m1["id"], "planEn": "Teach greetings.", "planRu": "Учим приветствия."})).json()["lesson"]
        lc = (await c.post(f"/api/v1/courses/{cid}/lessons", headers=H, json={"title": "to be", "moduleId": m1["id"]})).json()["lesson"]
        full = (await c.get(f"/api/v1/courses/{cid}", headers=H)).json()["course"]
        order = [l["title"] for l in full["lessons"]]
        check("lessons ordered module by module", order == ["Привет", "to be", "Семья 1"], order)
        check("plan + tg title stored", full["lessons"][0]["planEn"] == "Teach greetings." and full["lessons"][0]["title_tg"] == "Салом", full["lessons"][0])

        r = await c.post(f"/api/v1/lessons/{la['id']}/words", headers=H, json={"wordIds": ["w0", "w1", "wde"]})
        check("foreign-language word refused", r.status_code == 404, r.text)
        r = await c.post(f"/api/v1/lessons/{la['id']}/words", headers=H, json={"wordIds": ["w0", "w1", "w4", "w5"]})
        check("words attached", r.status_code == 200 and r.json()["added"] == 4, r.text)
        r = await c.post(f"/api/v1/lessons/{la['id']}/words", headers=H, json={"wordIds": ["w0"]})
        check("re-attach is a no-op", r.json()["added"] == 0, r.text)

        async def step(body):
            r = await c.post(f"/api/v1/lessons/{la['id']}/steps", headers=H, json=body)
            assert r.status_code == 201, r.text
            return r.json()["step"]

        r = await c.post(f"/api/v1/lessons/{la['id']}/steps", headers=H, json={"type": "phrases", "phraseIds": ["p1", "pde"]})
        check("foreign phrase refused", r.status_code == 400, r.text)
        r = await c.post(f"/api/v1/lessons/{la['id']}/steps", headers=H, json={"type": "practice", "phraseIds": ["p1"]})
        check("phrases only on a phrases step", r.status_code == 400, r.text)
        s_voc = await step({"type": "vocabulary"})
        s_phr = await step({"type": "phrases", "phraseIds": ["p1", "p2"]})
        s_mat = await step({"type": "material", "title": "Как здороваться", "aiTask": "Explain hello/hi", "aiPending": True})
        s_aud = await step({"type": "audio", "aiTask": "Short dialogue", "aiPending": True})
        s_pra = await step({"type": "practice", "aiTask": "Translate + match", "aiPending": True})
        s_min = await step({"type": "minitest", "aiTask": "6 questions", "aiPending": True})
        r = await c.post(f"/api/v1/lessons/{la['id']}/steps", headers=H, json={"type": "practice", "forStepId": s_pra["id"]})
        check("test can only point at audio/video", r.status_code == 400, r.text)
        s_atest = await step({"type": "practice", "title": "Тест по аудио", "forStepId": s_aud["id"], "aiTask": "Comprehension", "aiTaskRu": "Понимание аудио", "aiPending": True})
        check("audio test step linked + RU task", s_atest["forStepId"] == s_aud["id"] and s_atest["aiTaskRu"] == "Понимание аудио", s_atest)
        r = await c.patch(f"/api/v1/steps/{s_mat['id']}", headers=H, json={"topic": "Нет такой темы"})
        check("unknown topic refused", r.status_code == 404, r.text)
        r = await c.patch(f"/api/v1/steps/{s_mat['id']}", headers=H, json={"topic": "приветствия"})
        check("topic set on material", r.status_code == 200, r.text)
        r = await c.patch(f"/api/v1/steps/{s_pra['id']}", headers=H, json={"topic": "Приветствия"})
        check("topic only on material", r.status_code == 400, r.text)
        check("phrases step keeps order", [p["id"] for p in s_phr["phrases"]] == ["p1", "p2"], s_phr)
        route = [s_voc["id"], s_phr["id"], s_mat["id"], s_aud["id"], s_atest["id"], s_pra["id"], s_min["id"]]
        r = await c.put(f"/api/v1/lessons/{la['id']}/route", headers=H, json={"stepIds": route})
        check("route set", r.status_code == 200 and r.json()["lesson"]["route"] == route, r.text)
        r = await c.put(f"/api/v1/lessons/{la['id']}/route", headers=H, json={"stepIds": [s_voc["id"], s_voc["id"]]})
        check("duplicate in route refused", r.status_code == 400, r.text)
        r = await c.delete(f"/api/v1/steps/{s_voc['id']}", headers=H)
        check("build key cannot delete steps (403)", r.status_code == 403, r.text)
        r = await c.get(f"/api/v1/courses/{cid}", headers={"X-API-Key": "pk_legacy"})
        check("other key without courses:read -> 403", r.status_code == 403)

        # mark audio as already done by hand to test rewiring around pending
        r = await c.patch(f"/api/v1/steps/{s_aud['id']}", headers=H, json={"aiPending": False})
        check("step updated", r.status_code == 200 and r.json()["step"]["aiPending"] is False, r.text)

        # ---------------- learner view hides pending steps
        async with Session() as db:
            learner = await courses_svc.get_course(db, cid, locale="tg")
            admin = await courses_svc.get_course(db, cid)
            version = await courses_svc.get_course_version(db, cid)
        lg = next(l for l in learner["lessons"] if l["id"] == la["id"])["graph"]
        types = [n["type"] for n in lg["nodes"]]
        check("learner sees only ready steps", sorted(types) == ["audio", "phrases", "vocabulary"], types)
        ids = {n["id"]: n["type"] for n in lg["nodes"]}
        edges = sorted((ids[e["fromNodeId"]], ids[e["toNodeId"]]) for e in lg["edges"])
        check("route rewired around pending steps", edges == [("phrases", "audio"), ("vocabulary", "phrases")], edges)
        ph = next(n for n in lg["nodes"] if n["type"] == "phrases")["phrases"]
        check("phrase shown in learner locale (tg) with ru fallback", ph[0]["translation"] == "Аз шиносоӣ хурсандам" and ph[1]["translation"] == "Меня зовут ...", ph)
        check("learner gets no plan", "planEn" not in next(l for l in learner["lessons"] if l["id"] == la["id"]))
        check("learner module title in tg", learner["modules"][0]["title"] == "Шиносоӣ", learner["modules"])
        check("admin sees all 7 steps + plan", len(next(l for l in admin["lessons"] if l["id"] == la["id"])["graph"]["nodes"]) == 7 and admin["lessons"][0]["planRu"] == "Учим приветствия.")
        check("version fingerprint computes", bool(version))

        # ---------------- builder routes: modules
        r = await c.post(f"/api/builder/courses/{cid}/modules/reorder", json={"ids": [m2["id"], m1["id"]]})
        order = [l["title"] for l in r.json()["course"]["lessons"]]
        check("module reorder moves lessons", order == ["Семья 1", "Привет", "to be"], order)
        r = await c.put(f"/api/builder/courses/{cid}/lessons/{lc['id']}/module", json={"moduleId": m2["id"]})
        order = [(l["title"], l["moduleId"] == m2["id"]) for l in r.json()["course"]["lessons"]]
        check("move lesson to other module (goes to its end)", order == [("Семья 1", True), ("to be", True), ("Привет", False)], order)
        r = await c.delete(f"/api/builder/courses/{cid}/modules/{m2['id']}")
        order = [(l["title"], l["moduleId"]) for l in r.json()["course"]["lessons"]]
        check("deleting module keeps lessons, ungrouped go last", order == [("Привет", m1["id"]), ("Семья 1", None), ("to be", None)], order)
        r = await c.patch(f"/api/builder/courses/{cid}/lessons/{la['id']}", json={"planEn": "  Greetings v2 "})
        check("plan edited via builder", next(l for l in r.json()["course"]["lessons"] if l["id"] == la["id"])["planEn"] == "Greetings v2")

        # ---------------- AI fill (two passes: content, then linked questions)
        async def fake_key(db):
            return "k", "deepseek-chat"

        captured = []

        async def fake_chat(api_key, model, system, user, **kw):
            captured.append(user)
            if "MATERIAL BLOCKS" not in user:
                return {"steps": {"s1": {"blocks": [
                    {"title": "Hello", "title_tg": "Салом", "content": "Hello = привет", "content_tg": "Hello = салом",
                     "questions": [{"kind": "choice", "prompt": "Привет?", "options": ["Hello", "Bye", "Thanks"], "correctAnswer": "Hello"},
                                   {"kind": "choice", "prompt": "bad", "options": ["A", "B"], "correctAnswer": "C"}]},
                    {"title": "I am", "content": "I am Ali.", "questions": []},
                ]}}}
            return {"steps": {
                "s1": {"questions": [{"kind": "truefalse", "prompt": "Ali said hello", "correct": True},
                                     {"kind": "choice", "prompt": "Кто говорит?", "options": ["Ali", "Tom", "Bob"], "correctAnswer": "Ali"}]},
                "s2": {"questions": [{"kind": "cloze", "prompt": "I ___ Ali.", "options": ["am", "is", "are"], "correctAnswer": "am", "verifiesBlock": "b2"},
                                     {"kind": "truefalse", "prompt": "x", "correct": False, "verifiesBlock": "b9"}],
                       "auto": {"translateCount": 4, "matchPairs": 4, "blankPhraseIds": ["ph1", "ph9"]}},
                "s3": {"questions": [{"kind": "truefalse", "prompt": "Hi = привет", "correct": True, "verifiesBlock": "b1"}]},
            }}

        ai_settings.get_api_key = fake_key
        ai_client.chat_json = fake_chat
        r = await c.patch(f"/api/builder/courses/{cid}/lessons/{la['id']}/graph/nodes/{s_aud['id']}", json={"transcript": "Ali: Hello! Maryam: Hi!"})
        check("audio text set", r.status_code == 200, r.text)
        async with Session() as db:
            nodes_before = len((await db.execute(select(LessonNode).where(LessonNode.lessonId == la["id"]))).scalars().all())
            edges_before = sorted((e.fromNodeId, e.toNodeId) for e in (await db.execute(select(LessonEdge).where(LessonEdge.lessonId == la["id"]))).scalars().all())
        r = await c.post(f"/api/builder/courses/{cid}/lessons/{lc['id']}/ai/fill", json={})
        check("fill without plan/steps refused", r.status_code == 400, r.text)
        r = await c.post(f"/api/builder/courses/{cid}/lessons/{la['id']}/ai/fill", json={"instructions": "simple"})
        body = r.json()
        check("fill ok (4 steps, 2 AI calls)", r.status_code == 200 and body["filled"] == 4 and body["waiting"] == 0 and len(captured) == 2, (r.text, len(captured)))
        check("bad question + unknown block reported", any("bad" in w or "вопрос 2" in w for w in body.get("warnings", [])) and any("b9" in w for w in body.get("warnings", [])), body)
        p1, p2 = (captured + ["", ""])[:2]
        check("pass 1 has plan, words, phrases, task", all(x in p1 for x in ("Greetings v2", "friend — друг", "ph1: Nice to meet you", "TASK: Explain hello/hi", "Module: Знакомство")), p1[:600])
        check("pass 2 lists blocks and the audio text", "b1: Hello" in p2 and "b2: I am" in p2 and "Ali: Hello! Maryam: Hi!" in p2 and "TEST OF the audio step" in p2, p2[-800:])
        async with Session() as db:
            from app.models.question import Question
            nodes = (await db.execute(select(LessonNode).where(LessonNode.lessonId == la["id"]))).scalars().all()
            edges_after = sorted((e.fromNodeId, e.toNodeId) for e in (await db.execute(select(LessonEdge).where(LessonEdge.lessonId == la["id"]))).scalars().all())
            mat = next(n for n in nodes if n.type == "material")
            blocks = {b.title: b for b in (await db.execute(select(MaterialBlock).where(MaterialBlock.materialId == mat.refId))).scalars().all()}
            pra = next(n for n in nodes if n.type == "practice" and not n.forNodeId)
            atest = next(n for n in nodes if n.forNodeId)
            mini = next(n for n in nodes if n.type == "minitest")

            async def placements(block_id):
                rows = (await db.execute(select(QuestionPlacement, Question).join(Question, Question.id == QuestionPlacement.questionId).where(QuestionPlacement.lessonBlockId == block_id))).all()
                return rows

            pra_q = await placements(pra.refId)
            at_q = await placements(atest.refId)
            mini_q = await placements(mini.refId)
            in_block = (await db.execute(select(Question).join(QuestionPlacement, QuestionPlacement.questionId == Question.id).where(QuestionPlacement.materialBlockId == blocks["Hello"].id, QuestionPlacement.lessonBlockId.is_(None)))).scalars().all()
        check("structure unchanged", len(nodes) == nodes_before and edges_after == edges_before)
        check("no step waits any more", not any(n.aiPending for n in nodes), [(n.type, n.aiPending) for n in nodes])
        check("2 material blocks written", set(blocks) == {"Hello", "I am"}, list(blocks))
        cloze = next(q for p, q in pra_q if q.kind == "cloze")
        cloze_p = next(p for p, q in pra_q if q.kind == "cloze")
        check("practice question -> block b2 + topic", cloze_p.materialBlockId == blocks["I am"].id and cloze.topicId == "t1", (cloze_p.materialBlockId, cloze.topicId))
        bad = next(p for p, q in pra_q if q.kind == "truefalse")
        check("unknown block -> no block link, topic kept", bad.materialBlockId is None and next(q for p, q in pra_q if q.kind == "truefalse").topicId == "t1")
        check("practice: 2 questions + 3 auto", len(pra_q) == 5, len(pra_q))
        check("audio test questions -> linked to the audio", len(at_q) == 2 and all(p.mediaNodeId == s_aud["id"] and p.materialBlockId is None for p, q in at_q), [(p.mediaNodeId) for p, q in at_q])
        check("minitest question -> block b1", len(mini_q) == 1 and mini_q[0][0].materialBlockId == blocks["Hello"].id)
        check("material block question has topic", len(in_block) == 1 and in_block[0].topicId == "t1", [q.topicId for q in in_block])
        r = await c.post(f"/api/builder/courses/{cid}/lessons/{la['id']}/ai/fill", json={})
        check("second fill: nothing waits -> 400", r.status_code == 400, r.text)

        # ---------------- «Сбросить заполнение ИИ»
        r = await c.post(f"/api/builder/courses/{cid}/lessons/{la['id']}/ai/reset", json={"nodeId": pra.id})
        check("reset one step", r.status_code == 200 and r.json()["reset"] == 1, r.text)
        async with Session() as db:
            left_pra = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.lessonBlockId == pra.refId))).scalars().all()
            left_blocks = (await db.execute(select(MaterialBlock).where(MaterialBlock.materialId == mat.refId))).scalars().all()
            pra_now = await db.get(LessonNode, pra.id)
            cloze_gone = await db.get(Question, cloze.id)
        check("step emptied, waits again, other steps kept", not left_pra and pra_now.aiPending and len(left_blocks) == 2 and cloze_gone is None)
        r = await c.post(f"/api/builder/courses/{cid}/lessons/{la['id']}/ai/reset", json={})
        check("reset whole lesson (5 AI steps)", r.status_code == 200 and r.json()["reset"] == 5, r.text)
        async with Session() as db:
            nodes = (await db.execute(select(LessonNode).where(LessonNode.lessonId == la["id"]))).scalars().all()
            left_blocks = (await db.execute(select(MaterialBlock).where(MaterialBlock.materialId == mat.refId))).scalars().all()
            left_q = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.lessonBlockId.in_([atest.refId, mini.refId])))).scalars().all()
            aud = await db.get(LessonNode, s_aud["id"])
            edges_now = sorted((e.fromNodeId, e.toNodeId) for e in (await db.execute(select(LessonEdge).where(LessonEdge.lessonId == la["id"]))).scalars().all())
        check("everything AI wrote is gone", not left_blocks and not left_q and aud.transcript is None, (len(left_blocks), len(left_q), aud.transcript))
        check("AI steps wait again, words/phrases steps untouched", all(n.aiPending == bool(n.aiTask) for n in nodes), [(n.type, n.aiPending) for n in nodes])
        check("structure kept after reset", len(nodes) == nodes_before and edges_now == edges_before)

        # ---------------- key management
        r = await c.patch(f"/api/languages/en/api-keys/{build['id']}", json={"permissions": ["courses:delete"], "expiresInDays": 0})
        k = r.json()["key"]
        check("permissions edited, expiry removed", k["permissions"] == ["courses:read", "courses:delete"] and k["expiresAt"] is None, k)
        r = await c.delete(f"/api/v1/steps/{s_voc['id']}", headers=H)
        check("after edit, delete step allowed", r.status_code == 200, r.text)
        r = await c.post(f"/api/v1/courses/{cid}/modules", headers=H, json={"title": "x"})
        check("after edit, write no longer allowed", r.status_code == 403, r.text)
        r = await c.delete(f"/api/languages/en/api-keys/{build['id']}")
        r = await c.get("/api/v1/courses", headers=H)
        check("revoked key -> 401", r.status_code == 401)

    print(f"\n{sum(results)}/{len(results)} passed")


asyncio.run(main())
sys.exit(0 if results and all(results) else 1)
