from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.models.enums import CourseStatus


class CourseInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    status: CourseStatus | None = None
    # Which Level (and, through it, Language) this course belongs to —
    # optional so existing courses/callers that never set it keep working
    # unchanged (course_builder gap analysis, 2026-08-29).
    levelId: str | None = None

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название курса не может быть пустым")
        return v

    @field_validator("description")
    @classmethod
    def _trim_description(cls, v: str | None) -> str | None:
        return v.strip() if v is not None else v


class CourseUpdateInput(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    status: CourseStatus | None = None
    levelId: str | None = None

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        if not v:
            raise ValueError("Название курса не может быть пустым")
        return v


class LessonInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    materialText: str | None = None

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название урока не может быть пустым")
        return v


class LessonUpdateInput(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    materialText: str | None = None

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        if not v:
            raise ValueError("Название урока не может быть пустым")
        return v


class ReorderInput(BaseModel):
    ids: list[str] = Field(min_length=1)

    @field_validator("ids")
    @classmethod
    def _check_ids(cls, v: list[str]) -> list[str]:
        if any(not i for i in v):
            raise ValueError("Нужен хотя бы один элемент")
        return v


MediaKind = Literal["video", "audio"]


class MediaReuseInput(BaseModel):
    kind: MediaKind
    url: str


class CourseTranslationInput(BaseModel):
    """One locale's variant of a Course's own text (§ course content
    language, 2026-09-04). A full replace of that locale's row, not a
    partial patch — a course/lesson translation is small enough that the
    admin UI always edits it as one unit, so there is no "leave title
    unchanged but clear description" case to support."""

    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=4000)

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название курса не может быть пустым")
        return v


class CourseLessonTranslationInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=4000)
    materialText: str = Field(default="")

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название урока не может быть пустым")
        return v
