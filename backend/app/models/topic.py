import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.language import Language
    from app.models.material import Material
    from app.models.question import Question


class Topic(Base):
    """A knowledge/topic tag (e.g. "Präteritum") that different Materials
    across different lessons can share, so weak-spot detection can point at
    a specific piece of knowledge rather than "redo the whole lesson"."""

    __tablename__ = "Topic"
    __table_args__ = (Index("Topic_languageId_idx", "languageId"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    languageId: Mapped[str] = mapped_column(String, ForeignKey("Language.id"), nullable=False)
    name: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")

    language: Mapped["Language"] = relationship(back_populates="topics")
    materials: Mapped[list["Material"]] = relationship(back_populates="topic")
    questions: Mapped[list["Question"]] = relationship(back_populates="topic")
