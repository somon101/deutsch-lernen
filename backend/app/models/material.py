import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.material_block import MaterialBlock
    from app.models.topic import Topic


class Material(Base):
    """A lesson's teaching content as a real, addressable object — a lesson
    can have several (theory text, a video, an audio track, ...), each
    independently taggable with a Topic. Replaces the flat
    CourseLesson.materialText/videoUrl/audioUrl fields going forward; those
    old fields are kept, unused, as a safe rollback/reference (see the
    migration plan's backfill step)."""

    __tablename__ = "Material"
    __table_args__ = (Index("Material_lessonId_position_idx", "lessonId", "position"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    # Loose references, matching the existing LessonBlock/LessonQuestion
    # convention (no DB-level FK to Course/CourseLesson): "legacy" for the
    # file-based course, else a real Course.id; lessonId is CourseLesson.id
    # for builder courses, or the "lessonN" folder slug for legacy.
    courseId: Mapped[str] = mapped_column(String, nullable=False)
    lessonId: Mapped[str] = mapped_column(String, nullable=False)
    # "text" | "video" | "audio" | "grammar" | "other" — free-text, not an
    # enum, same convention as LessonBlock.stage/LessonQuestion.kind.
    materialType: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    topicId: Mapped[str | None] = mapped_column(String, ForeignKey("Topic.id", ondelete="SET NULL"), nullable=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    topic: Mapped["Topic | None"] = relationship(back_populates="materials")
    blocks: Mapped[list["MaterialBlock"]] = relationship(back_populates="material", cascade="all, delete-orphan")
