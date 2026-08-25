import uuid

from sqlalchemy import Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class VocabularyItem(Base):
    __tablename__ = "VocabularyItem"
    __table_args__ = (
        UniqueConstraint("courseId", "germanKey", name="VocabularyItem_courseId_germanKey_key"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    lessonId: Mapped[str] = mapped_column(String, nullable=False)
    german: Mapped[str] = mapped_column(String, nullable=False)
    translation: Mapped[str] = mapped_column(String, nullable=False)
    pronunciation: Mapped[str | None] = mapped_column(String, nullable=True)
    audioUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    # Case/punctuation-insensitive form of `german` — the course-wide
    # uniqueness key (see services/content.py's normalize_word).
    germanKey: Mapped[str] = mapped_column(String, nullable=False)
    # "legacy" = the original file-based course; else a Course.id. Plain
    # string, no real FK — words from any course share this one table.
    courseId: Mapped[str] = mapped_column(String, nullable=False, default="legacy")
