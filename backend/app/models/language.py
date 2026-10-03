from typing import TYPE_CHECKING

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.level import Level
    from app.models.topic import Topic


class Language(Base):
    """Content-taxonomy root. Schema-ready for multiple languages, but only
    the "de" row is seeded/populated for now — adding a real second language
    is a deliberately separate future step."""

    __tablename__ = "Language"

    # ISO-639-1-style short code (e.g. "de") — the code IS the id, no
    # separate surrogate key, since language codes are a small, stable,
    # human-meaningful set.
    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    # DRAFT hides the language and all its courses from learners; staff
    # still see everything. Existing rows default to PUBLISHED.
    status: Mapped[str] = mapped_column(String, nullable=False, default="PUBLISHED", server_default="PUBLISHED")
    # Letters for future letter-based exercises; only stored for now.
    alphabet: Mapped[str | None] = mapped_column(String, nullable=True)

    levels: Mapped[list["Level"]] = relationship(back_populates="language")
    topics: Mapped[list["Topic"]] = relationship(back_populates="language")
