import { getAuthToken } from "../auth/tokenStore";
import { LessonProgress } from "./types";

const API_URL = (import.meta.env.VITE_API_URL as string | undefined)?.replace(/\/$/, "") ?? "http://localhost:4000";

/**
 * Fire-and-forget append of a finished lesson attempt to the user's attempt
 * history (used for best score / attempt count). Never throws and never
 * blocks the UI — the lesson state itself is persisted separately by
 * ProgressContext.
 */
export function syncAttemptIfAuthenticated(lessonId: string, progress: LessonProgress): void {
  const token = getAuthToken();
  if (!token) return;
  if (!progress.miniTestResult || !progress.practiceResult || !progress.reviewResult) return;

  const body = {
    miniTestCorrect: progress.miniTestResult.correct,
    miniTestTotal: progress.miniTestResult.total,
    practiceCorrect: progress.practiceResult.correct,
    practiceTotal: progress.practiceResult.total,
    reviewCorrect: progress.reviewResult.correct,
    reviewTotal: progress.reviewResult.total,
  };

  fetch(`${API_URL}/api/me/progress/${encodeURIComponent(lessonId)}/attempts`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  }).catch(() => {
    // Offline or backend unavailable — local progress already saved, nothing more to do.
  });
}
