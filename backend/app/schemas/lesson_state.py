from typing import Literal

from pydantic import BaseModel, Field

StageId = Literal["vocabulary", "material", "video", "minitest", "audio", "practice", "review", "complete"]

# Every StageId except "complete" — that one isn't an activity a learner
# spends time doing, just the results screen.
ActivityType = Literal["vocabulary", "material", "video", "minitest", "audio", "practice", "review"]


class ActivityTimeInput(BaseModel):
    courseId: str | None = None
    lessonId: str = Field(min_length=1)
    activityType: ActivityType
    # Defensive ceiling, not a new rule: 120s (2 minutes) is already the
    # largest of the per-unit caps the client itself enforces (a material
    # section) before ever reporting a delta, and video/audio segments are
    # flushed at least that often while playing — so no single legitimate
    # report should exceed it (§ time tracking, 2026-08-29 — "защита от
    # искусственного накручивания времени").
    seconds: int = Field(ge=1, le=120)


# Every kind of "qualifying activity" that can complete a streak day (§
# streak mode, 2026-08-29). Only lesson_completed is ever actually sent
# today — the extra names are reserved so a future feature can start using
# one without touching this file beyond adding its own literal here.
DailyActivityType = Literal["lesson_completed"]


class DailyActivityInput(BaseModel):
    activityType: DailyActivityType


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
