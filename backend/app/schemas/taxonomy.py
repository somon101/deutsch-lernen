from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.schemas.block import BlockQuestionInput

# ---------------------------------------------------------------------------
# Language / Level / Topic
# ---------------------------------------------------------------------------


class LanguageInput(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    # If an existing Language with the same name is found, the endpoint
    # returns it instead of creating a duplicate — unless the caller has
    # already seen that and explicitly wants a new one anyway.
    force: bool = False

    @field_validator("name")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название языка не может быть пустым")
        return v


class LevelInput(BaseModel):
    languageId: str
    code: str = Field(min_length=1, max_length=10)
    name: str = Field(min_length=1, max_length=100)
    position: int = 0

    @field_validator("code", "name")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Значение не может быть пустым")
        return v


class TopicInput(BaseModel):
    languageId: str
    name: str = Field(min_length=1, max_length=200)
    # If an existing Topic with the same name is found, the endpoint returns
    # it instead of creating a duplicate (§32) — unless the caller has
    # already seen that and explicitly wants a new one anyway.
    force: bool = False

    @field_validator("name")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название темы не может быть пустым")
        return v


# ---------------------------------------------------------------------------
# Material / MaterialBlock
# ---------------------------------------------------------------------------

MaterialType = Literal["text", "video", "audio", "grammar", "other"]


class MaterialInput(BaseModel):
    courseId: str
    lessonId: str
    materialType: MaterialType
    title: str = Field(min_length=1, max_length=200)
    topicId: str | None = None

    @field_validator("title")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название материала не может быть пустым")
        return v


class MaterialUpdateInput(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    topicId: str | None = None

    @field_validator("title")
    @classmethod
    def _trim(cls, v: str | None) -> str | None:
        if v is None:
            return v
        v = v.strip()
        if not v:
            raise ValueError("Название материала не может быть пустым")
        return v


class MaterialBlockInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    content: str = Field(default="")

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название блока не может быть пустым")
        return v


class MaterialBlockReorderInput(BaseModel):
    blockIds: list[str] = Field(min_length=1)


# ---------------------------------------------------------------------------
# Question pool / placement / duplicate check
# ---------------------------------------------------------------------------


class QuestionCreateInput(BaseModel):
    """Creates a standalone, reusable Question and (optionally) places it
    somewhere in the same request — matches how the block editor already
    creates-and-attaches a question in one action."""

    question: BlockQuestionInput
    topicId: str | None = None
    materialBlockId: str | None = None
    lessonBlockId: str | None = None
    legacyLessonId: str | None = None
    legacySetName: str | None = None
    # If true, skip the similarity check even if a strong match exists
    # (the teacher already saw the warning and chose "create anyway").
    force: bool = False


class QuestionReuseInput(BaseModel):
    """Attaches an EXISTING question by reference — no new question_id, no
    copy (§16/§17)."""

    questionId: str
    materialBlockId: str | None = None
    lessonBlockId: str | None = None
    legacyLessonId: str | None = None
    legacySetName: str | None = None


class PlacementVerifiesBlockInput(BaseModel):
    """Sets/changes/clears the "verifies this reading block" tag on an
    already-existing quiz-stage placement (§ course-builder redesign, 2026-
    09-01) — null clears it."""

    materialBlockId: str | None = None


class SimilarityCheckInput(BaseModel):
    """Dry-run duplicate check the teacher can trigger before saving, in
    addition to the automatic check `POST /questions` already does."""

    question: BlockQuestionInput
    topicId: str | None = None
    materialId: str | None = None


# ---------------------------------------------------------------------------
# Answer submission
# ---------------------------------------------------------------------------


class AnswerSubmitInput(BaseModel):
    questionId: str
    placementId: str | None = None
    answerData: dict | list
    correct: bool
