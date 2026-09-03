import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.material_block import MaterialBlock


class MaterialBlockTranslation(Base):
    """One instructional-language variant of a MaterialBlock's title+content
    (§ course content language, 2026-09-04). Same locale-as-data pattern as
    CourseTranslation; see that model's docstring for why."""

    __tablename__ = "MaterialBlockTranslation"
    __table_args__ = (
        UniqueConstraint("materialBlockId", "locale", name="MaterialBlockTranslation_materialBlockId_locale_key"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    materialBlockId: Mapped[str] = mapped_column(
        String, ForeignKey("MaterialBlock.id", ondelete="CASCADE"), nullable=False
    )
    locale: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    content: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    block: Mapped["MaterialBlock"] = relationship()
