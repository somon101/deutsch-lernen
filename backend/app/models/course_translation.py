import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.course import Course


class CourseTranslation(Base):
    """One instructional-language variant of a Course's learner-facing text
    (§ course content language, 2026-09-04). Deliberately a CHILD table keyed
    by `locale` rather than a `titleRu`/`titleTg` column pair — adding a
    third language is then just new rows with a new locale value, not a
    migration and not a rewrite of every reader. `locale` is NOT the same
    dimension as Course -> Level -> Language (the language being TAUGHT,
    e.g. German): this is the language the course's OWN text is written IN
    (e.g. "ru", "tg")."""

    __tablename__ = "CourseTranslation"
    __table_args__ = (UniqueConstraint("courseId", "locale", name="CourseTranslation_courseId_locale_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    courseId: Mapped[str] = mapped_column(String, ForeignKey("Course.id", ondelete="CASCADE"), nullable=False)
    locale: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str] = mapped_column(String, nullable=False, default="")
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    course: Mapped["Course"] = relationship()
