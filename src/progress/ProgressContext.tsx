import React, { createContext, useCallback, useContext, useMemo, useState } from "react";
import { readStore, writeStore } from "./storage";
import { QuizResult, LessonProgress, StageId, createEmptyProgress } from "./types";

type Store = Record<string, LessonProgress>;

interface ProgressContextValue {
  store: Store;
  getLessonProgress: (lessonId: string) => LessonProgress;
  markStageComplete: (lessonId: string, stage: StageId) => void;
  setVocabIndex: (lessonId: string, index: number) => void;
  recordQuizResult: (
    lessonId: string,
    key: "miniTestResult" | "practiceResult" | "reviewResult",
    result: QuizResult,
  ) => void;
  completeLesson: (lessonId: string) => void;
  resetLesson: (lessonId: string) => void;
}

const ProgressContext = createContext<ProgressContextValue | null>(null);

export function ProgressProvider({ children }: { children: React.ReactNode }) {
  const [store, setStore] = useState<Store>(() => readStore());

  const update = useCallback((lessonId: string, updater: (progress: LessonProgress) => LessonProgress) => {
    setStore((prev) => {
      const current = prev[lessonId] ?? createEmptyProgress(lessonId);
      const next = { ...prev, [lessonId]: updater(current) };
      writeStore(next);
      return next;
    });
  }, []);

  const getLessonProgress = useCallback(
    (lessonId: string) => store[lessonId] ?? createEmptyProgress(lessonId),
    [store],
  );

  const markStageComplete = useCallback(
    (lessonId: string, stage: StageId) => {
      update(lessonId, (progress) =>
        progress.completedStages.includes(stage)
          ? progress
          : { ...progress, completedStages: [...progress.completedStages, stage] },
      );
    },
    [update],
  );

  const setVocabIndex = useCallback(
    (lessonId: string, index: number) => {
      update(lessonId, (progress) => ({ ...progress, vocabIndex: index }));
    },
    [update],
  );

  const recordQuizResult = useCallback(
    (lessonId: string, key: "miniTestResult" | "practiceResult" | "reviewResult", result: QuizResult) => {
      update(lessonId, (progress) => ({ ...progress, [key]: result }));
    },
    [update],
  );

  const completeLesson = useCallback(
    (lessonId: string) => {
      update(lessonId, (progress) => ({
        ...progress,
        completedStages: progress.completedStages.includes("complete")
          ? progress.completedStages
          : [...progress.completedStages, "complete"],
        completedAt: new Date().toISOString(),
      }));
    },
    [update],
  );

  const resetLesson = useCallback(
    (lessonId: string) => {
      update(lessonId, () => createEmptyProgress(lessonId));
    },
    [update],
  );

  const value = useMemo(
    () => ({
      store,
      getLessonProgress,
      markStageComplete,
      setVocabIndex,
      recordQuizResult,
      completeLesson,
      resetLesson,
    }),
    [store, getLessonProgress, markStageComplete, setVocabIndex, recordQuizResult, completeLesson, resetLesson],
  );

  return <ProgressContext.Provider value={value}>{children}</ProgressContext.Provider>;
}

export function useProgressStore(): ProgressContextValue {
  const ctx = useContext(ProgressContext);
  if (!ctx) throw new Error("useProgressStore must be used within ProgressProvider");
  return ctx;
}

export function useLessonProgress(lessonId: string): LessonProgress {
  const { getLessonProgress } = useProgressStore();
  return getLessonProgress(lessonId);
}
