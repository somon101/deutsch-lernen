import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class UserWordProgress(Base):
    """A user has learned this word (§ word cards, 2026-08-31) — the link
    ONLY, never a copy of the word card itself (see VocabularyItem for the
    actual word/translation/audio/etc). Same shape as Follow (id, two ids,
    one unique constraint) for the same reason: the fact of the relationship
    is all that needs to exist per user, not a duplicate of what's on the
    other side of it.

    Marked on lesson completion (§6 of the request) — see
    services/vocabulary.py's mark_lesson_words_learned, hooked into the
    existing PUT /api/me/lesson-state/{id} completion path. The unique
    constraint is what makes re-completing the same lesson a no-op instead
    of a duplicate row."""

    __tablename__ = "UserWordProgress"
    __table_args__ = (UniqueConstraint("userId", "wordId", name="UserWordProgress_userId_wordId_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    wordId: Mapped[str] = mapped_column(String, ForeignKey("VocabularyItem.id", ondelete="CASCADE"), nullable=False)
    learnedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
