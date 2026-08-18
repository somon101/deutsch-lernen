import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { QuizResult, LessonProgress, StageId, createEmptyProgress } from "./types";
import { syncAttemptIfAuthenticated } from "./attemptSync";
import { api } from "../auth/api";
import { useAuth } from "../auth/AuthContext";

type Store = Record<string, LessonProgress>;

interface ProgressContextValue {
  store: Store;
  /** False until this user's progress has been fetched from the server. */
  isLoaded: boolean;
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
  const { user } = useAuth();
  const [store, setStore] = useState<Store>({});
  const [isLoaded, setIsLoaded] = useState(false);

  // Mirrors `store` so updates can be computed outside of setState — keeps
  // the server write out of the state updater (which React StrictMode runs
  // twice) and lets recordQuizResult read the merged value synchronously.
  const storeRef = useRef<Store>({});
  // Per-lesson promise chain so rapid updates (e.g. clicking through the
  // vocabulary cards) reach the server in the order they happened.
  const saveChains = useRef<Record<string, Promise<unknown>>>({});

  // Progress is per-account: load this user's state on login, drop it on
  // logout so nothing leaks into the next session.
  useEffect(() => {
    let cancelled = false;
    storeRef.current = {};
    setStore({});
    setIsLoaded(false);

    if (!user) return;

    api
      .get<{ states: LessonProgress[] }>("/api/me/lesson-state")
      .then((data) => {
        if (cancelled) return;
        const next: Store = {};
        for (const state of data.states) next[state.lessonId] = state;
        storeRef.current = next;
        setStore(next);
        setIsLoaded(true);
      })
      .catch(() => {
        if (!cancelled) setIsLoaded(true);
      });

    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  const persist = useCallback((lessonId: string, progress: LessonProgress) => {
    const previous = saveChains.current[lessonId] ?? Promise.resolve();
    saveChains.current[lessonId] = previous
      .catch(() => {})
      .then(() => api.put(`/api/me/lesson-state/${encodeURIComponent(lessonId)}`, progress))
      .catch(() => {
        // Offline / server unavailable — in-memory state stays usable for
        // the rest of the session; nothing is written to browser storage.
      });
  }, []);

  const update = useCallback(
    (lessonId: string, updater: (progress: LessonProgress) => LessonProgress): LessonProgress => {
      const current = storeRef.current[lessonId] ?? createEmptyProgress(lessonId);
      const next = updater(current);
      storeRef.current = { ...storeRef.current, [lessonId]: next };
      setStore(storeRef.current);
      persist(lessonId, next);
      return next;
    },
    [persist],
  );

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
      const merged = update(lessonId, (progress) => ({ ...progress, [key]: result }));
      // "Закрепление" (reviewResult) is the last scored stage before the
      // lesson is considered finished — a reliable signal that a full
      // attempt just completed, including redone attempts.
      if (key === "reviewResult") {
        syncAttemptIfAuthenticated(lessonId, merged);
      }
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
      isLoaded,
      getLessonProgress,
      markStageComplete,
      setVocabIndex,
      recordQuizResult,
      completeLesson,
      resetLesson,
    }),
    [
      store,
      isLoaded,
      getLessonProgress,
      markStageComplete,
      setVocabIndex,
      recordQuizResult,
      completeLesson,
      resetLesson,
    ],
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
