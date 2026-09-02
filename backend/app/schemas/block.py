import re
from typing import Annotated, Literal, Union

from pydantic import BaseModel, Field, field_validator, model_validator

QuestionSet = Literal["minitest", "practice", "review"]


class BlockInput(BaseModel):
    stage: QuestionSet
    title: str = Field(min_length=1, max_length=200)

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название блока не может быть пустым")
        return v


class BlockUpdateInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)

    @field_validator("title")
    @classmethod
    def _trim_title(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Название блока не может быть пустым")
        return v


# Five question kinds an admin can author inside a block. `kind` matches the
# Exercise["kind"] values in the frontend exactly, so the learner-facing
# runner needs no translation layer. Mirrors courses.ts's blockQuestionSchema
# (5 member objects + a superRefine for cross-field rules) exactly.


class ChoiceQuestionInput(BaseModel):
    kind: Literal["choice"]
    prompt: str = Field(min_length=1)
    options: list[str] = Field(min_length=2)
    correctAnswer: str = Field(min_length=1)

    @field_validator("prompt", "correctAnswer")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Значение не может быть пустым")
        return v

    @field_validator("options")
    @classmethod
    def _trim_options(cls, v: list[str]) -> list[str]:
        trimmed = [o.strip() for o in v]
        if any(not o for o in trimmed):
            raise ValueError("Вариант ответа не может быть пустым")
        return trimmed

    @model_validator(mode="after")
    def _cross_field(self) -> "ChoiceQuestionInput":
        if self.correctAnswer not in self.options:
            raise ValueError("Правильный ответ должен быть одним из вариантов")
        if len(set(self.options)) != len(self.options):
            raise ValueError("Варианты ответа не должны повторяться")
        return self


class TrueFalseQuestionInput(BaseModel):
    kind: Literal["truefalse"]
    prompt: str = Field(min_length=1)
    correct: bool

    @field_validator("prompt")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Текст утверждения не может быть пустым")
        return v


class ClozeQuestionInput(BaseModel):
    kind: Literal["cloze"]
    prompt: str = Field(min_length=1)
    options: list[str] = Field(min_length=2)
    correctAnswer: str = Field(min_length=1)

    @field_validator("prompt", "correctAnswer")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Значение не может быть пустым")
        return v

    @field_validator("options")
    @classmethod
    def _trim_options(cls, v: list[str]) -> list[str]:
        trimmed = [o.strip() for o in v]
        if any(not o for o in trimmed):
            raise ValueError("Вариант ответа не может быть пустым")
        return trimmed

    @model_validator(mode="after")
    def _cross_field(self) -> "ClozeQuestionInput":
        if self.correctAnswer not in self.options:
            raise ValueError("Правильный ответ должен быть одним из вариантов")
        if len(set(self.options)) != len(self.options):
            raise ValueError("Варианты ответа не должны повторяться")
        if len(re.findall("___", self.prompt)) != 1:
            raise ValueError("Отметьте ровно один пропуск как ___")
        return self


class ScrambleQuestionInput(BaseModel):
    """`options` is optional (§ auto scramble, 2026-09-02): left empty, the
    draggable pieces are derived from `correctAnswer` at serve time, so the
    phrase is the only stored source of truth and nothing about the shuffle
    is persisted. It is only filled when the teacher adds extra distractor
    words, which genuinely can't be derived from the phrase — that keeps
    every hand-built exercise working unchanged."""

    kind: Literal["scramble"]
    prompt: str = Field(min_length=1)
    options: list[str] = Field(default_factory=list)
    correctAnswer: str = Field(min_length=1)

    @field_validator("prompt")
    @classmethod
    def _trim_prompt(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Укажите перевод или инструкцию")
        return v

    @field_validator("correctAnswer")
    @classmethod
    def _trim_answer(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Укажите правильную фразу")
        return v

    @field_validator("options")
    @classmethod
    def _trim_options(cls, v: list[str]) -> list[str]:
        trimmed = [o.strip() for o in v]
        if any(not o for o in trimmed):
            raise ValueError("Слово не может быть пустым")
        return trimmed


class MatchPair(BaseModel):
    left: str = Field(min_length=1)
    right: str = Field(min_length=1)

    @field_validator("left", "right")
    @classmethod
    def _trim(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Заполните обе части пары")
        return v


class MatchQuestionInput(BaseModel):
    kind: Literal["match"]
    prompt: str = ""
    pairs: list[MatchPair] = Field(min_length=2)

    @field_validator("prompt")
    @classmethod
    def _trim_prompt(cls, v: str) -> str:
        return v.strip() if v else ""


class AutoBlankQuestionInput(BaseModel):
    """Teacher saves only full sentences (§ auto blank, 2026-08-31) - no
    blank marker, no options, no correct answer. Distinct kind from "cloze"
    above (which already owns the "Пропущенное слово" label/mechanism, and
    is fully author-provided) - this one lets the system pick the blanked
    word and wrong-answer options at serve time, per learner."""

    kind: Literal["auto_blank"]
    phrases: list[str] = Field(min_length=1)

    @field_validator("phrases")
    @classmethod
    def _trim_phrases(cls, v: list[str]) -> list[str]:
        trimmed = [p.strip() for p in v]
        if any(not p for p in trimmed):
            raise ValueError("Фраза не может быть пустой")
        return trimmed


BlockQuestionInput = Annotated[
    Union[ChoiceQuestionInput, TrueFalseQuestionInput, ClozeQuestionInput, ScrambleQuestionInput, MatchQuestionInput, AutoBlankQuestionInput],
    Field(discriminator="kind"),
]


class BlockQuestionsPayload(BaseModel):
    questions: list[BlockQuestionInput]
