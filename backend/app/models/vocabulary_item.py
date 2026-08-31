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

    # Word-card foundation (§ word cards, 2026-08-31) — this row IS the
    # universal "word card" the whole app can address by id (`wordId`);
    # these three fields extend it without touching anything above, which
    # every existing builder/legacy/import code path keeps writing exactly
    # as before.
    imageUrl: Mapped[str | None] = mapped_column(String, nullable=True)
    # Plain string, no real FK (same convention as courseId above) —
    # nullable so existing rows and words created without picking a
    # category stay valid; get_or_create_category never leaves this unset
    # once a category IS chosen.
    categoryId: Mapped[str | None] = mapped_column(String, nullable=True)
    # Direct reference, not derived through lessonId -> Course -> Level on
    # every read — legacy words (courseId="legacy") have no Course/Level
    # row to walk through at all, so this is backfilled once (legacy rows
    # get German's id, matching the same legacy-is-German convention
    # get_total_time_seconds already relies on) rather than computed live.
    languageId: Mapped[str | None] = mapped_column(String, nullable=True)
