import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, Enum, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.models.enums import CourseStatus
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.course_lesson import CourseLesson
    from app.models.level import Level


class Course(Base):
    __tablename__ = "Course"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    title: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str] = mapped_column(String, nullable=False, default="")
    coverUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[CourseStatus] = mapped_column(
        Enum(CourseStatus, name="CourseStatus", create_type=False), nullable=False, default=CourseStatus.DRAFT
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    # Plain string, no real FK to User (matches the Prisma schema).
    createdById: Mapped[str | None] = mapped_column(String, nullable=True)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, server_default="now()")
    # No DB-level default (confirmed via information_schema) — set client-side.
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)
    # Nullable during the migration window (add nullable -> backfill -> set
    # NOT NULL, same pattern as User.publicId). The legacy file-based course
    # has no Course row at all and is deliberately exempt from this
    # dimension — see the approved migration plan.
    levelId: Mapped[str | None] = mapped_column(String, ForeignKey("Level.id"), nullable=True)

    lessons: Mapped[list["CourseLesson"]] = relationship(back_populates="course", cascade="all, delete-orphan")
    level: Mapped["Level | None"] = relationship(back_populates="courses")
