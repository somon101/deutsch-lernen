export type StageId =
  | "vocabulary"
  | "material"
  | "video"
  | "minitest"
  | "audio"
  | "practice"
  | "review"
  | "complete";

export const STAGE_ORDER: StageId[] = [
  "vocabulary",
  "material",
  "video",
  "minitest",
  "audio",
  "practice",
  "review",
  "complete",
];

export const STAGE_LABELS: Record<StageId, string> = {
  vocabulary: "Слова",
  material: "Материал",
  video: "Видео",
  minitest: "Мини-тест",
  audio: "Аудио",
  practice: "Практика",
  review: "Закрепление",
  complete: "Итог",
};

export interface QuizResult {
  total: number;
  correct: number;
  completedAt: string;
}

export interface LessonProgress {
  lessonId: string;
  completedStages: StageId[];
  vocabIndex: number;
  miniTestResult?: QuizResult;
  practiceResult?: QuizResult;
  reviewResult?: QuizResult;
  startedAt: string;
  completedAt?: string;
}

export function createEmptyProgress(lessonId: string): LessonProgress {
  return {
    lessonId,
    completedStages: [],
    vocabIndex: 0,
    startedAt: new Date().toISOString(),
  };
}

export function isStageUnlocked(progress: LessonProgress, stage: StageId): boolean {
  const idx = STAGE_ORDER.indexOf(stage);
  if (idx <= 0) return true;
  const previous = STAGE_ORDER[idx - 1];
  return progress.completedStages.includes(previous);
}

export function isStageComplete(progress: LessonProgress, stage: StageId): boolean {
  return progress.completedStages.includes(stage);
}

export function nextIncompleteStage(progress: LessonProgress): StageId {
  for (const stage of STAGE_ORDER) {
    if (!progress.completedStages.includes(stage)) return stage;
  }
  return "complete";
}

export function courseProgressRatio(progress: LessonProgress | undefined): number {
  if (!progress) return 0;
  const total = STAGE_ORDER.length - 1; // "complete" itself isn't a learning stage
  const done = progress.completedStages.filter((s) => s !== "complete").length;
  return total === 0 ? 0 : done / total;
}
