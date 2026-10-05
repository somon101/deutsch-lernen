import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, Index, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class LessonNode(Base):
    """One block placed on a lesson's graph canvas (§ lesson graph,
    2026-09-03). Wraps an existing content row by reference — refId is a
    Material.id for type 'material', a LessonBlock.id for
    minitest/practice/review; null for vocabulary (still one shared
    lesson-wide word list) and for video/audio (which own their file
    directly via mediaUrl instead, since making them repeatable needed
    somewhere for more than one file per lesson to live). A lesson with no
    LessonNode rows is unconverted and keeps using the old fixed 8-stage
    chain untouched."""

    __tablename__ = "LessonNode"
    __table_args__ = (Index("LessonNode_lessonId_idx", "lessonId"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    courseId: Mapped[str] = mapped_column(String, nullable=False)
    lessonId: Mapped[str] = mapped_column(String, nullable=False)
    # "vocabulary" | "phrases" | "material" | "video" | "audio" | "minitest" | "practice" | "review"
    type: Mapped[str] = mapped_column(String, nullable=False)
    refId: Mapped[str | None] = mapped_column(String, nullable=True)
    mediaUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    title: Mapped[str | None] = mapped_column(String, nullable=True)
    # Audio nodes only (§ AI lesson generator, 2026-10-03): the text of the
    # recording in the studied language, and its translations by content
    # locale ({"ru": ..., "tg": ...}). The AI writes the text before any
    # file exists; the admin records and uploads the audio from it.
    transcript: Mapped[str | None] = mapped_column(String, nullable=True)
    transcriptTranslations: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    # "phrases" nodes only (§ course modules, 2026-10-05): ids of Phrase
    # rows from the language's phrase base, in display order.
    phraseIds: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    # An empty step waiting for the AI (§ course modules, 2026-10-05):
    # `aiTask` says what belongs here, `aiPending` hides the step from
    # learners until the AI (or the teacher) has filled it.
    aiTask: Mapped[str | None] = mapped_column(String, nullable=True)
    aiPending: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    posX: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    posY: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)
