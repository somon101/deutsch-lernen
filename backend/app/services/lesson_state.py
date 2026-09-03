from app.models.lesson_state import LessonState
from app.utils import to_iso_z


def to_dto(state: LessonState) -> dict:
    """Wire shape consumed by the (future) Flutter client's progress store —
    deliberately the same LessonProgress object the old React UI worked
    with, mirroring lessonState.ts's toDTO exactly."""
    dto: dict = {
        "lessonId": state.lessonId,
        "completedStages": state.completedStages,
        "vocabIndex": state.vocabIndex,
        "startedAt": to_iso_z(state.startedAt),
    }
    if state.completedAt:
        dto["completedAt"] = to_iso_z(state.completedAt)
    if state.miniTestTotal is not None and state.miniTestCorrect is not None:
        dto["miniTestResult"] = {
            "correct": state.miniTestCorrect,
            "total": state.miniTestTotal,
            "completedAt": to_iso_z(state.miniTestAt or state.updatedAt),
        }
    if state.practiceTotal is not None and state.practiceCorrect is not None:
        dto["practiceResult"] = {
            "correct": state.practiceCorrect,
            "total": state.practiceTotal,
            "completedAt": to_iso_z(state.practiceAt or state.updatedAt),
        }
    if state.reviewTotal is not None and state.reviewCorrect is not None:
        dto["reviewResult"] = {
            "correct": state.reviewCorrect,
            "total": state.reviewTotal,
            "completedAt": to_iso_z(state.reviewAt or state.updatedAt),
        }
    if state.nodeResults is not None:
        dto["nodeResults"] = state.nodeResults
    return dto
