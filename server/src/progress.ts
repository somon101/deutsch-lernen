import { prisma } from "./db.js";

export interface AttemptInput {
  miniTestCorrect: number;
  miniTestTotal: number;
  practiceCorrect: number;
  practiceTotal: number;
  reviewCorrect: number;
  reviewTotal: number;
}

/**
 * Same idea as the existing client-side per-stage percentage in
 * CompleteStage.tsx, just summed across the three scored stages instead of
 * one — not a new/arbitrary formula, a direct generalization of it.
 */
export function computeScore(input: AttemptInput): number {
  const correct = input.miniTestCorrect + input.practiceCorrect + input.reviewCorrect;
  const total = input.miniTestTotal + input.practiceTotal + input.reviewTotal;
  if (total <= 0) return 0;
  return Math.round((correct / total) * 100);
}

export interface LessonProgressSummary {
  lessonId: string;
  attempts: number;
  bestScore: number;
  lastScore: number;
  lastAttemptAt: string;
}

/** Best/last/attempt-count are always derived from the attempts log, never
 * stored redundantly — the log is the single source of truth. */
export async function getProgressSummaryForUser(userId: string): Promise<LessonProgressSummary[]> {
  const attempts = await prisma.lessonAttempt.findMany({
    where: { userId },
    orderBy: { createdAt: "asc" },
    select: { lessonId: true, score: true, createdAt: true },
  });

  const byLesson = new Map<string, LessonProgressSummary>();
  for (const a of attempts) {
    const existing = byLesson.get(a.lessonId);
    if (!existing) {
      byLesson.set(a.lessonId, {
        lessonId: a.lessonId,
        attempts: 1,
        bestScore: a.score,
        lastScore: a.score,
        lastAttemptAt: a.createdAt.toISOString(),
      });
    } else {
      existing.attempts += 1;
      existing.bestScore = Math.max(existing.bestScore, a.score);
      existing.lastScore = a.score; // attempts are ordered oldest -> newest
      existing.lastAttemptAt = a.createdAt.toISOString();
    }
  }

  return Array.from(byLesson.values());
}
