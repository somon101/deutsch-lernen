from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

QuestionSet = Literal["minitest", "practice", "review"]


class VocabularyItemInput(BaseModel):
    german: str = Field(min_length=1)
    translation: str = Field(min_length=1)
    pronunciation: str | None = None
    audioUrl: str | None = None

    @field_validator("german", "translation")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Значение не может быть пустым")
        return v


class QuestionInput(BaseModel):
    """Mirrors content.ts's questionSchema — the flat, un-blocked shape used
    by the legacy PUT /content/:lessonId endpoint."""

    setName: QuestionSet
    prompt: str = Field(min_length=1)
    options: list[str] = Field(min_length=2)
    correctAnswer: str = Field(min_length=1)

    @field_validator("prompt", "correctAnswer")
    @classmethod
    def _trim_one(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Текст не может быть пустым")
        return v

    @field_validator("options")
    @classmethod
    def _trim_options(cls, v: list[str]) -> list[str]:
        trimmed = [o.strip() for o in v]
        if any(not o for o in trimmed):
            raise ValueError("Вариант ответа не может быть пустым")
        return trimmed

    @model_validator(mode="after")
    def _check_answer_and_uniqueness(self) -> "QuestionInput":
        # Correctness is stored by value, so the marked answer must actually
        # be one of the options — otherwise the question would be unanswerable.
        if self.correctAnswer not in self.options:
            raise ValueError("Правильный ответ должен быть одним из вариантов")
        if len(set(self.options)) != len(self.options):
            raise ValueError("Варианты ответа не должны повторяться")
        return self


class ContentPayload(BaseModel):
    materialText: str | None = None
    vocabulary: list[VocabularyItemInput] | None = None
    questions: list[QuestionInput] | None = None
