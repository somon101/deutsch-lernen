import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class LessonVocabularyLink(Base):
    """Reuses an EXISTING VocabularyItem in a second (third, ...) lesson
    without copying its row (§ shared dictionary, 2026-09-14).

    VocabularyItem.lessonId already existed as the word's "home" — where it
    was first created, and where its own edit/delete/audio/image endpoints
    still operate, byte-for-byte unchanged. That column stays exactly as it
    was; nothing here alters it or the uniqueness rule built on it
    (courseId, germanKey). This table only ADDS extra lesson placements on
    top: one row per (lessonId, wordId) says "this lesson also teaches this
    word," and every consumer that needs "the words in lesson X" now reads
    its native VocabularyItem rows plus its rows here (see
    services/vocabulary.py's get_linked_word_ids_for_lessons) — a lesson
    with no rows here behaves exactly as before this table existed.

    UNIQUE (lessonId, wordId) is the whole "don't double-attach" guarantee,
    same idempotency shape as DailyGoalAward/LessonReminderLog's own
    per-day uniques elsewhere in this codebase.
    """

    __tablename__ = "LessonVocabularyLink"
    __table_args__ = (UniqueConstraint("lessonId", "wordId", name="LessonVocabularyLink_lessonId_wordId_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    # Plain string, no real FK — same convention VocabularyItem.lessonId
    # itself already uses, since a legacy lessonId has no CourseLesson row
    # to reference at all.
    lessonId: Mapped[str] = mapped_column(String, nullable=False)
    # Denormalized copy of the LESSON's own course (not necessarily the
    # word's native courseId — a word can, by design, now be reused across
    # courses) so a course-scoped query never has to join through the word
    # to know which course a link belongs to.
    courseId: Mapped[str] = mapped_column(String, nullable=False)
    wordId: Mapped[str] = mapped_column(String, ForeignKey("VocabularyItem.id", ondelete="CASCADE"), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow)
