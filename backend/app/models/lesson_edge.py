import uuid
from datetime import datetime

from sqlalchemy import DateTime, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class LessonEdge(Base):
    """A flow connection between two LessonNode rows (§ lesson graph,
    2026-09-03) — the ONLY thing that defines the student's route through a
    graph lesson (see services/lesson_graph.py's topological flatten). Loose
    references to LessonNode.id, same manual-cascade convention as
    Material/LessonBlock's own loose refs — deleting a node deletes its
    edges in application code, not via a DB-level FK.

    A separate connection type the spec calls "theory" (which Material block
    a Question verifies) needs no table here at all — QuestionPlacement.
    materialBlockId already is that link."""

    __tablename__ = "LessonEdge"
    __table_args__ = (
        UniqueConstraint("fromNodeId", "toNodeId", name="LessonEdge_fromNodeId_toNodeId_key"),
        Index("LessonEdge_lessonId_idx", "lessonId"),
        Index("LessonEdge_fromNodeId_idx", "fromNodeId"),
        Index("LessonEdge_toNodeId_idx", "toNodeId"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    lessonId: Mapped[str] = mapped_column(String, nullable=False)
    fromNodeId: Mapped[str] = mapped_column(String, nullable=False)
    toNodeId: Mapped[str] = mapped_column(String, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
