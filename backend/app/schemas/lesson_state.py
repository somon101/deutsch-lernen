from typing import Literal

from pydantic import BaseModel, Field

StageId = Literal["vocabulary", "material", "video", "minitest", "audio", "practice", "review", "complete"]


class QuizResult(BaseModel):
    correct: int = Field(ge=0)
    total: int = Field(ge=0)
    completedAt: str | None = None


class LessonStateRequest(BaseModel):
    completedStages: list[StageId] = Field(default_factory=list)
    vocabIndex: int = Field(ge=0, default=0)
    miniTestResult: QuizResult | None = None
    practiceResult: QuizResult | None = None
    reviewResult: QuizResult | None = None
    startedAt: str | None = None
    completedAt: str | None = None


class AttemptRequest(BaseModel):
    miniTestCorrect: int = Field(ge=0)
    miniTestTotal: int = Field(ge=0)
    practiceCorrect: int = Field(ge=0)
    practiceTotal: int = Field(ge=0)
    reviewCorrect: int = Field(ge=0)
    reviewTotal: int = Field(ge=0)
