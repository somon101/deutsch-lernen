import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.course import Course
    from app.models.language import Language


class Level(Base):
    """A CEFR-style level (e.g. "A1") scoped to one Language — the same code
    can exist once per language without conflict (see the unique
    constraint)."""

    __tablename__ = "Level"
    __table_args__ = (UniqueConstraint("languageId", "code", name="Level_languageId_code_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    languageId: Mapped[str] = mapped_column(String, ForeignKey("Language.id"), nullable=False)
    code: Mapped[str] = mapped_column(String, nullable=False)
    name: Mapped[str] = mapped_column(String, nullable=False)
    # Display/progress-aggregation order: A1 < A2 < B1 < ...
    position: Mapped[int] = mapped_column(Integer, nullable=False)

    language: Mapped["Language"] = relationship(back_populates="levels")
    courses: Mapped[list["Course"]] = relationship(back_populates="level")
