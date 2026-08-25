import uuid
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.course import Course


class CourseLesson(Base):
    __tablename__ = "CourseLesson"
    __table_args__ = (Index("CourseLesson_courseId_position_idx", "courseId", "position"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    courseId: Mapped[str] = mapped_column(String, ForeignKey("Course.id", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str] = mapped_column(String, nullable=False, default="")
    materialText: Mapped[str] = mapped_column(String, nullable=False, default="")
    videoUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    audioUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)

    course: Mapped["Course"] = relationship(back_populates="lessons")
