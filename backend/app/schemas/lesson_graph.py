from typing import Literal

from pydantic import BaseModel, Field, field_validator

NodeType = Literal["vocabulary", "material", "video", "audio", "minitest", "practice", "review"]


class CreateNodeInput(BaseModel):
    type: NodeType
    title: str | None = Field(default=None, max_length=200)
    posX: float = 0
    posY: float = 0

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

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        return v or None


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
