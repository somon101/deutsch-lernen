import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.vocabulary_item import VocabularyItem


class VocabularyTranslation(Base):
    """One instructional-language variant of a VocabularyItem's translation
    (§ course content language, 2026-09-04). Only `translation` varies by
    locale — `german` (the word being taught) and `pronunciation` (its IPA,
    which describes the taught word, not the explaining language) stay on
    VocabularyItem itself and are shared across every locale. Same
    locale-as-data pattern as CourseTranslation; see that model's docstring
    for why."""

    __tablename__ = "VocabularyTranslation"
    __table_args__ = (
        UniqueConstraint("vocabularyItemId", "locale", name="VocabularyTranslation_vocabularyItemId_locale_key"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    vocabularyItemId: Mapped[str] = mapped_column(
        String, ForeignKey("VocabularyItem.id", ondelete="CASCADE"), nullable=False
    )
    locale: Mapped[str] = mapped_column(String, nullable=False)
    translation: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    word: Mapped["VocabularyItem"] = relationship()
