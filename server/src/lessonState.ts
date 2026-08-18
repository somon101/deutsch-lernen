import type { LessonState } from "@prisma/client";

/**
 * Wire shape consumed by the frontend's ProgressContext — deliberately the
 * same LessonProgress object the UI already worked with, so no lesson/stage
 * component had to change when this moved from localStorage to the database.
 */
export interface LessonProgressDTO {
  lessonId: string;
  completedStages: string[];
  vocabIndex: number;
  miniTestResult?: { correct: number; total: number; completedAt: string };
  practiceResult?: { correct: number; total: number; completedAt: string };
  reviewResult?: { correct: number; total: number; completedAt: string };
  startedAt: string;
  completedAt?: string;
}

export function toDTO(state: LessonState): LessonProgressDTO {
  const dto: LessonProgressDTO = {
    lessonId: state.lessonId,
    completedStages: state.completedStages,
    vocabIndex: state.vocabIndex,
    startedAt: state.startedAt.toISOString(),
  };
  if (state.completedAt) dto.completedAt = state.completedAt.toISOString();
  if (state.miniTestTotal !== null && state.miniTestCorrect !== null) {
    dto.miniTestResult = {
      correct: state.miniTestCorrect,
      total: state.miniTestTotal,
      completedAt: (state.miniTestAt ?? state.updatedAt).toISOString(),
    };
  }
  if (state.practiceTotal !== null && state.practiceCorrect !== null) {
    dto.practiceResult = {
      correct: state.practiceCorrect,
      total: state.practiceTotal,
      completedAt: (state.practiceAt ?? state.updatedAt).toISOString(),
    };
  }
  if (state.reviewTotal !== null && state.reviewCorrect !== null) {
    dto.reviewResult = {
      correct: state.reviewCorrect,
      total: state.reviewTotal,
      completedAt: (state.reviewAt ?? state.updatedAt).toISOString(),
    };
  }
  return dto;
}
