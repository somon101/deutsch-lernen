import { Achievement, ProfileLevel, ProfileRanking, WeeklyActivityDay } from "./types";

/**
 * TEMPORARY DEMO DATA — for visually reviewing the profile page layout only.
 * None of this is computed from anything real (no follower/streak/rating/
 * study-time/achievement system exists yet — see types.ts). Delete this
 * file and switch ProfilePage.tsx back to the null placeholders (or real
 * values, once each system exists) once the design review is done.
 */

export const DEMO_SOCIAL = { followers: 128, mutualFollowers: 42, following: 67 };

export const DEMO_STREAK_DAYS = 17;

export const DEMO_STUDY_MINUTES = 24 * 60 + 30;

export const DEMO_LEVEL: ProfileLevel = { label: "B1 – Intermediate", progressPercent: 78 };

export const DEMO_RANKING: ProfileRanking = { rank: 48, percentile: 12, totalStudents: 8452 };

export const DEMO_WEEKLY_ACTIVITY: WeeklyActivityDay[] = [
  { label: "Пн", active: true },
  { label: "Вт", active: true },
  { label: "Ср", active: true },
  { label: "Чт", active: true },
  { label: "Пт", active: true },
  { label: "Сб", active: true },
  { label: "Вс", active: false },
];

export const DEMO_AVG_MINUTES_PER_DAY = 252;

/** Deliberately shows all three visual states (unlocked / in-progress /
 * locked) so the block's design can be reviewed at once — see
 * AchievementsSection.tsx for how each status renders. */
export const DEMO_ACHIEVEMENTS: Achievement[] = [
  { id: "1", icon: "🎤", title: "Первый урок", subtitle: "Пройден", status: "unlocked" },
  { id: "2", icon: "🔥", title: "Неделя 7 дней", subtitle: "Пройден", status: "unlocked" },
  { id: "3", icon: "🎯", title: "Цель 10 уроков", subtitle: "7 / 10", status: "in-progress" },
  { id: "4", icon: "🏆", title: "Активный ученик", subtitle: "10 уроков", status: "unlocked" },
  { id: "5", icon: "📘", title: "Мастер слов", subtitle: "Заблокировано", status: "locked" },
];
