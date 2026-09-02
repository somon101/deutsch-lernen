"""Parses a lesson's raw materialText into the structured {blocks, phrases}
shape every client renders — reuses the same bit-exact-verified parser from
app/legacy_parser (see that package's docstring for how it was validated
against the real TypeScript parser). Promoted here from "one-time import
script helper" to a real request-time service: any client (the existing
React app already parses client-side; Flutter has no such parser and
shouldn't need one — see the migration plan's Phase 5 notes) can now get
pre-parsed content instead of raw text, without a second parser
implementation existing anywhere.
"""

import re

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.legacy_parser.parse_lesson_text import parse_lesson_text
from app.legacy_parser.text_utils import normalize_answer
from app.models.material import Material
from app.models.material_block import MaterialBlock
from app.models.question import Question
from app.models.question_placement import QuestionPlacement

_WHITESPACE_RE = re.compile(r"\s+")


def scramble_tokens(correct_answer: str) -> list[str]:
    """The draggable pieces of a "Собери фразу" exercise, derived from the
    correct phrase itself (§ auto scramble, 2026-09-02).

    Split on whitespace only, so punctuation stays attached to its own word
    ("müde." is one token) — the learner reassembles the phrase exactly as
    written, and the grader joins the placed tokens back with single spaces
    before comparing, so this split is the exact inverse of that join.
    Repeated words are kept as separate entries on purpose: the phrase needs
    as many copies of "ich" as it actually contains, and the runner keys
    tokens by position rather than text, so duplicates never collapse."""
    return [t for t in _WHITESPACE_RE.split(correct_answer.strip()) if t]


def to_question_dto(kind: str, prompt: str, options: list[str] | None, correct_answer: str, data) -> dict:
    """Renders one stored question row (LessonQuestion or Question — same 5
    kinds, same field shapes) into the wire dict every client's Exercise
    parser expects. Lives here rather than in content.py so material.py's
    own get_new_material_blocks can embed a MaterialBlock's attached
    questions without a circular import."""
    if kind == "truefalse":
        return {"kind": "truefalse", "prompt": prompt, "correct": correct_answer == "true"}
    if kind == "cloze":
        return {"kind": "cloze", "prompt": prompt, "options": options or [], "correctAnswer": correct_answer}
    if kind == "scramble":
        # No stored options means the auto mode (§ auto scramble,
        # 2026-09-02): the teacher saved only a translation and the correct
        # phrase, so the pieces are derived from that phrase here, at serve
        # time. Nothing about the shuffle is stored — the phrase stays the
        # single source of truth, and the runner reshuffles on every pass.
        # A question WITH stored options is a hand-built one (its extra
        # distractor words aren't derivable from the phrase) and is passed
        # through untouched, so existing exercises keep working exactly as
        # before.
        return {"kind": "scramble", "prompt": prompt, "options": options or scramble_tokens(correct_answer), "correctAnswer": correct_answer}
    if kind == "match":
        return {"kind": "match", "prompt": prompt, "pairs": data or []}
    if kind == "auto_blank":
        # Admin-facing single-row view only (question_dto/list_block_questions/
        # similarity check) — the teacher sees every phrase they entered, not
        # a blanked/generated version (nothing is generated at authoring
        # time). The learner-facing expansion is to_question_dtos below.
        return {"kind": "auto_blank", "phrases": (data or {}).get("phrases", [])}
    if kind == "auto_translate":
        # Admin-facing view (§ auto translate, 2026-09-02) — the teacher sees
        # their own configuration back, not generated questions, since
        # nothing is generated at authoring time.
        return {"kind": "auto_translate", "source": (data or {}).get("source", "lesson"), "count": (data or {}).get("count", 0)}
    return {"kind": "choice", "prompt": prompt, "options": options or [], "correctAnswer": correct_answer}


def to_question_dtos(question: Question, placement_id: str) -> list[dict]:
    """Same shape to_question_dto returns, wrapped with id/placementId —
    except an "auto_blank" question (§ auto blank, 2026-08-31) expands into
    one lightweight placeholder entry PER PHRASE instead of one entry for
    the whole question: the learner should see one exercise slot per phrase
    the teacher entered (always in the same phrase order — §10/clarified in
    conversation: phrase selection per slot is sequential, not random),
    each resolved into an actual blanked question + options only when the
    learner reaches it (GET /api/questions/{id}/blank/{phraseIndex}) —
    nothing about the blank/options exists yet at content-fetch time."""
    # "source": "pool" (§ course-builder redesign bugfix, 2026-09-01) — every
    # entry this function returns comes from a real Question+QuestionPlacement
    # row, never a legacy LessonQuestion. courses.py's lesson_dto merges
    # these into the SAME block.questions array as real LessonQuestion rows
    # (§ approved rule 4, 2026-08-27, for the student-facing quiz to see a
    # complete list either way) — without this marker the admin builder
    # can't tell them apart, and its "Сохранить вопросы" wholesale-replace
    # (save_block_questions) would silently duplicate a pool question into
    # a brand new LessonQuestion row alongside the untouched original.
    if question.kind == "auto_blank":
        phrases = (question.data or {}).get("phrases", [])
        return [
            {"id": f"{question.id}::{i}", "placementId": placement_id, "kind": "auto_blank", "questionId": question.id, "phraseIndex": i, "source": "pool"}
            for i in range(len(phrases))
        ]
    if question.kind == "auto_translate":
        # One slot per requested question (§ auto translate, 2026-09-02).
        # The count is NOT capped to the pool here: the pool depends on the
        # learner (their learned words) and this function has neither the
        # user nor the database. A slot the pool can't fill is resolved as
        # "can't generate" at serve time and skipped by the runner, which is
        # the same path auto_blank already uses when a slot is unsafe.
        count = (question.data or {}).get("count") or 0
        return [
            {"id": f"{question.id}::{i}", "placementId": placement_id, "kind": "auto_translate", "questionId": question.id, "slotIndex": i, "source": "pool"}
            for i in range(int(count))
        ]
    return [
        {
            "id": question.id,
            "placementId": placement_id,
            "source": "pool",
            **to_question_dto(question.kind, question.prompt, question.options, question.correctAnswer, question.data),
        }
    ]


def parse_material(material_text: str, vocabulary: list[dict]) -> dict:
    """Mirrors loader.ts's post-parse step exactly: blocks/phrases come from
    parse_lesson_text, then any phrase missing a pronunciation gets one
    backfilled from the lesson's own vocabulary list (matched by lowercased
    german word) — the parser alone only catches inline [bracket] hints."""
    if not material_text:
        return {"blocks": [], "phrases": []}

    parsed = parse_lesson_text(material_text)
    pronunciation_by_word = {v["german"].lower(): v.get("pronunciation") for v in vocabulary if v.get("pronunciation")}

    def with_pronunciation(item: dict) -> dict:
        if item.get("pronunciation"):
            return item
        fallback = pronunciation_by_word.get(item["german"].lower())
        return {**item, "pronunciation": fallback} if fallback else item

    blocks = [with_pronunciation(b) if b["type"] == "phrase" else b for b in parsed["blocks"]]
    phrases = [with_pronunciation(p) for p in parsed["phrases"]]
    return {"blocks": blocks, "phrases": phrases}


async def get_new_material_blocks(db: AsyncSession, course_id: str, lesson_ids: list[str]) -> dict[str, list[dict]]:
    """Renders the new block-based editor's Material/MaterialBlock rows
    (content-taxonomy plan, 2026-08-26) into the same {type, ...} shape
    MaterialStage already renders. Keyed by lessonId; a lesson present here
    (even with an empty list, meaning the admin opened the new editor but
    hasn't added a block yet) has been migrated and should use these blocks
    instead of parsing materialText — a lesson absent from the dict has no
    "text" Material yet and the caller should fall back to parse_material,
    so pre-migration lessons keep working exactly as before."""
    if not lesson_ids:
        return {}
    materials = (
        await db.execute(
            select(Material)
            .where(Material.courseId == course_id, Material.lessonId.in_(lesson_ids), Material.materialType == "text")
            .order_by(Material.lessonId, Material.position)
        )
    ).scalars().all()
    if not materials:
        return {}

    material_ids = [m.id for m in materials]
    lesson_by_material = {m.id: m.lessonId for m in materials}
    rows = (
        await db.execute(
            select(MaterialBlock).where(MaterialBlock.materialId.in_(material_ids)).order_by(MaterialBlock.materialId, MaterialBlock.position)
        )
    ).scalars().all()

    # A reusable Question attached to one of these blocks is rendered inline
    # right after the block's text (§ where-pool-questions-appear, 2026-08-26
    # decision: "внутри чтения материала") — the learner answers it as a
    # checkpoint before moving on, and the answer is logged the same way any
    # other question's is.
    block_ids = [b.id for b in rows]
    questions_by_block: dict[str, list[dict]] = {}
    if block_ids:
        placement_rows = (
            await db.execute(
                select(QuestionPlacement, Question)
                .join(Question, Question.id == QuestionPlacement.questionId)
                # lessonBlockId IS NULL excludes a placement that's actually
                # shown in a quiz stage but merely tagged as "verifying" this
                # reading block (§4 of the approved rule, 2026-08-27) — that
                # tag must never make the question ALSO appear inline here.
                .where(QuestionPlacement.materialBlockId.in_(block_ids), QuestionPlacement.lessonBlockId.is_(None))
                .order_by(QuestionPlacement.materialBlockId, QuestionPlacement.position)
            )
        ).all()
        for placement, question in placement_rows:
            questions_by_block.setdefault(placement.materialBlockId, []).extend(to_question_dtos(question, placement.id))

    result: dict[str, list[dict]] = {m.lessonId: [] for m in materials}
    for b in rows:
        result[lesson_by_material[b.materialId]].append(
            {"type": "block", "id": b.id, "title": b.title, "content": b.content, "questions": questions_by_block.get(b.id, [])}
        )
    return result


async def get_pool_questions_for_lesson_blocks(db: AsyncSession, lesson_block_ids: list[str]) -> dict[str, list[dict]]:
    """Reusable-pool Questions placed in a quiz LessonBlock (minitest/
    practice/review), keyed by lessonBlockId — mirrors
    get_new_material_blocks's placement lookup exactly, just scoped to
    lessonBlockId instead of materialBlockId (§ approved rule 4, 2026-08-27:
    the learner must actually receive these, not just the admin UI). Merged
    into a block's existing LessonQuestion-sourced questions by the caller,
    never replacing them — the old full-replace quiz-question path keeps
    working exactly as before."""
    if not lesson_block_ids:
        return {}
    placement_rows = (
        await db.execute(
            select(QuestionPlacement, Question)
            .join(Question, Question.id == QuestionPlacement.questionId)
            .where(QuestionPlacement.lessonBlockId.in_(lesson_block_ids))
            .order_by(QuestionPlacement.lessonBlockId, QuestionPlacement.position)
        )
    ).all()
    result: dict[str, list[dict]] = {}
    for placement, question in placement_rows:
        result.setdefault(placement.lessonBlockId, []).extend(to_question_dtos(question, placement.id))
    return result


def filter_new_vocabulary(vocabulary: list[dict], taught_before_keys: set[str]) -> list[dict]:
    """Same list minus any word already taught as a new word in an earlier
    lesson of the same course (compared case/punctuation-insensitively) —
    mirrors loader.ts's newVocabulary filter exactly."""
    return [v for v in vocabulary if normalize_answer(v["german"]) not in taught_before_keys]
