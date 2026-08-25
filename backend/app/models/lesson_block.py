import uuid

from sqlalchemy import Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class LessonBlock(Base):
    """Named group of questions within one stage of a lesson. Only the model
    is defined here (needed to read legacy-lesson content in Phase 2) — full
    CRUD (create/reorder/delete blocks, block-question saving) is course
    builder business logic, ported in Phase 3."""

    __tablename__ = "LessonBlock"
    __table_args__ = (Index("LessonBlock_lessonId_stage_position_idx", "lessonId", "stage", "position"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    # Plain strings, no real FK/cascade to Course/CourseLesson — matches the
    # Prisma schema exactly (manual application-level cascade only).
    courseId: Mapped[str] = mapped_column(String, nullable=False)
    lessonId: Mapped[str] = mapped_column(String, nullable=False)
    # "minitest" | "practice" | "review" — free-text, not an enum.
    stage: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
