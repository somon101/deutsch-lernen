import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.material import Material


class MaterialTranslation(Base):
    """One instructional-language variant of a Material's title (§ course
    content language, 2026-09-04). The body text lives on MaterialBlock, not
    here — see MaterialBlockTranslation. Same locale-as-data pattern as
    CourseTranslation; see that model's docstring for why."""

    __tablename__ = "MaterialTranslation"
    __table_args__ = (UniqueConstraint("materialId", "locale", name="MaterialTranslation_materialId_locale_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    materialId: Mapped[str] = mapped_column(String, ForeignKey("Material.id", ondelete="CASCADE"), nullable=False)
    locale: Mapped[str] = mapped_column(String, nullable=False)
    title: Mapped[str] = mapped_column(String, nullable=False)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    material: Mapped["Material"] = relationship()
