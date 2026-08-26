import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.material import Material
    from app.models.question_placement import QuestionPlacement


class MaterialBlock(Base):
    """One teacher-authored, named chunk of a Material's theory content
    ("Что такое Präteritum?"). Deliberately a SEPARATE model from
    LessonBlock, which groups QUESTIONS inside a minitest/practice/review
    quiz stage and means something different despite the similar name."""

    __tablename__ = "MaterialBlock"
    __table_args__ = (Index("MaterialBlock_materialId_position_idx", "materialId", "position"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    materialId: Mapped[str] = mapped_column(String, ForeignKey("Material.id", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    content: Mapped[str] = mapped_column(String, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)

    material: Mapped["Material"] = relationship(back_populates="blocks")
    placements: Mapped[list["QuestionPlacement"]] = relationship(back_populates="materialBlock")
