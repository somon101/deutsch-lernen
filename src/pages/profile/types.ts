/**
 * Visual data model for the profile page's stat blocks. None of these are
 * computed from real tracking yet (no follower/streak/rating/study-time
 * system exists in the schema) — this shape exists so the UI can be built
 * now and wired to real numbers later, one field at a time, without
 * reshaping the components. `overallProgressPercent` is the one field
 * that's already real (derived from actual lesson attempts).
 */
export interface ProfileStats {
  followers: number | null;
  mutualFollowers: number | null;
  following: number | null;
  streakDays: number | null;
  overallProgressPercent: number | null;
  studyMinutes: number | null;
}

/** CEFR-style level tracking doesn't exist yet — both fields stay null
 * until lessons/vocabulary are tagged with a level and a real calculation
 * is built. */
export interface ProfileLevel {
  label: string | null;
  progressPercent: number | null;
}

export interface Achievement {
  id: string;
  icon: string;
  title: string;
  subtitle: string;
  status: "unlocked" | "in-progress" | "locked";
}

/** Placeholder shape for the future rating system — a user's rank among
 * all students, and what percentile that puts them in. */
export interface ProfileRanking {
  rank: number | null;
  percentile: number | null;
  totalStudents: number | null;
}

/** One entry per weekday; `active` stays null (no per-day study data
 * exists) until daily activity is actually tracked server-side. */
export interface WeeklyActivityDay {
  label: string;
  active: boolean | null;
}
