import uuid
from datetime import datetime

from sqlalchemy import DateTime, Index, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class VideoLesson(Base):
    """A character video built in the course's video constructor: a speech
    source (uploaded audio, or text voiced by TTS) plus its speech timeline
    (services/speech_timeline.py), played back live with a lip-synced
    character. Lives in its own per-course list for now; placing it into
    lessons for learners is a later step."""

    __tablename__ = "VideoLesson"
    __table_args__ = (Index("VideoLesson_courseId_idx", "courseId"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    courseId: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False, default="Видеоурок")
    characterId: Mapped[str] = mapped_column(String, nullable=False, default="cloud")
    sourceType: Mapped[str] = mapped_column(String, nullable=False, default="audio")  # audio | text
    text: Mapped[str | None] = mapped_column(String, nullable=True)
    voice: Mapped[str | None] = mapped_column(String, nullable=True)
    audioUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    timeline: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    durationMs: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[str] = mapped_column(String, nullable=False, default="empty")  # empty | ready | error
    error: Mapped[str | None] = mapped_column(String, nullable=True)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)
