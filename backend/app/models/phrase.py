import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class Phrase(Base):
    """A reusable phrase in the studied language (§ phrase base,
    2026-10-03) — the phrase counterpart of the shared word dictionary.
    Not owned by any lesson: lessons and the AI lesson generator draw from
    it by id. `translation` is the base (ru) text, the same "base column IS
    the ru text" convention VocabularyItem uses; other locales live in
    PhraseTranslation."""

    __tablename__ = "Phrase"
    __table_args__ = (Index("Phrase_languageId_idx", "languageId"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    languageId: Mapped[str] = mapped_column(String, ForeignKey("Language.id", ondelete="CASCADE"), nullable=False)
    text: Mapped[str] = mapped_column(String, nullable=False)
    translation: Mapped[str] = mapped_column(String, nullable=False, default="")
    topicId: Mapped[str | None] = mapped_column(String, ForeignKey("Topic.id", ondelete="SET NULL"), nullable=True)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)


class PhraseTranslation(Base):
    __tablename__ = "PhraseTranslation"
    __table_args__ = (UniqueConstraint("phraseId", "locale", name="PhraseTranslation_phraseId_locale_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    phraseId: Mapped[str] = mapped_column(String, ForeignKey("Phrase.id", ondelete="CASCADE"), nullable=False)
    locale: Mapped[str] = mapped_column(String, nullable=False)
    translation: Mapped[str] = mapped_column(String, nullable=False)
