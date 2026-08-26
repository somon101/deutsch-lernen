import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.material_block import MaterialBlock
    from app.models.question import Question


class QuestionPlacement(Base):
    """Where a reusable Question is actually used. Exactly ONE of
    materialBlockId/lessonBlockId/(legacyLessonId+legacySetName) is set on
    any given row — a placement lives in a Material's theory block, an
    existing LessonBlock's quiz stage, or (for the legacy file-based course,
    which has neither) a bare lessonId+setName pair, mirroring
    LessonQuestion's own lessonId/setName/blockId split for that course.
    lessonBlockId/legacyLessonId/legacySetName are loose references (same
    convention as LessonQuestion.blockId), not DB-level FKs."""

    __tablename__ = "QuestionPlacement"
    __table_args__ = (
        Index("QuestionPlacement_materialBlockId_position_idx", "materialBlockId", "position"),
        Index("QuestionPlacement_lessonBlockId_position_idx", "lessonBlockId", "position"),
        Index("QuestionPlacement_legacyLessonId_legacySetName_position_idx", "legacyLessonId", "legacySetName", "position"),
        Index("QuestionPlacement_questionId_idx", "questionId"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    questionId: Mapped[str] = mapped_column(String, ForeignKey("Question.id", ondelete="CASCADE"), nullable=False)
    materialBlockId: Mapped[str | None] = mapped_column(
        String, ForeignKey("MaterialBlock.id", ondelete="CASCADE"), nullable=True
    )
    lessonBlockId: Mapped[str | None] = mapped_column(String, nullable=True)
    legacyLessonId: Mapped[str | None] = mapped_column(String, nullable=True)
    legacySetName: Mapped[str | None] = mapped_column(String, nullable=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)

    question: Mapped["Question"] = relationship(back_populates="placements")
    materialBlock: Mapped["MaterialBlock | None"] = relationship(back_populates="placements")
