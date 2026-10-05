from typing import Literal

from pydantic import BaseModel, Field, field_validator

NodeType = Literal["vocabulary", "phrases", "material", "video", "audio", "minitest", "practice", "review"]


class CreateNodeInput(BaseModel):
    type: NodeType
    title: str | None = Field(default=None, max_length=200)
    posX: float = 0
    posY: float = 0
    # § course modules, 2026-10-05.
    aiTask: str | None = Field(default=None, max_length=4000)
    aiPending: bool = False
    phraseIds: list[str] | None = Field(default=None, max_length=100)

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        return v or None


class UpdateNodeInput(BaseModel):
    posX: float | None = None
    posY: float | None = None
    title: str | None = Field(default=None, max_length=200)
    # Audio nodes only (§ AI lesson generator, 2026-10-03).
    transcript: str | None = Field(default=None, max_length=20000)
    transcriptTranslations: dict[str, str] | None = None
    # § course modules, 2026-10-05.
    phraseIds: list[str] | None = Field(default=None, max_length=100)
    aiTask: str | None = Field(default=None, max_length=4000)
    aiPending: bool | None = None

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        return v or None


class RouteInput(BaseModel):
    """The whole learner route at once: step ids in walking order."""

    nodeIds: list[str] = Field(max_length=100)


class CreateEdgeInput(BaseModel):
    fromNodeId: str = Field(min_length=1)
    toNodeId: str = Field(min_length=1)


class NodeMediaReuseInput(BaseModel):
    """Points a video/audio node at a file already used elsewhere (the same
    cross-lesson media library GET /api/builder/media/library already
    lists) instead of uploading a new one — mirrors MediaReuseInput
    (schemas/course.py), minus `kind`, since a node's own type already says
    video or audio."""

    url: str = Field(min_length=1)
