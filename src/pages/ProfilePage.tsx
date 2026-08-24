import { ChangeEvent, FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { api, ApiError } from "../auth/api";
import { StoredAuthUser } from "../auth/tokenStore";
import { listLessonIds, loadLesson } from "../content/loader";
import { useTheme } from "../theme/ThemeContext";
import ProfileHeader from "./profile/ProfileHeader";
import StatsGrid from "./profile/StatsGrid";
import LevelProgress from "./profile/LevelProgress";
import AchievementsSection from "./profile/AchievementsSection";
import RankingCard from "./profile/RankingCard";
import WeeklyActivity from "./profile/WeeklyActivity";
import ProfileNavList from "./profile/ProfileNavList";
import BottomNav from "./profile/BottomNav";
import { ProfileStats } from "./profile/types";
import {
  DEMO_ACHIEVEMENTS,
  DEMO_AVG_MINUTES_PER_DAY,
  DEMO_LEVEL,
  DEMO_RANKING,
  DEMO_SOCIAL,
  DEMO_STREAK_DAYS,
  DEMO_STUDY_MINUTES,
  DEMO_WEEKLY_ACTIVITY,
} from "./profile/demoData";

interface LessonProgressSummary {
  lessonId: string;
  attempts: number;
  bestScore: number;
  lastScore: number;
  lastAttemptAt: string;
}

interface LessonRow {
  lessonId: string;
  title: string;
  summary: LessonProgressSummary | null;
}

// TEMPORARY: filled with src/pages/profile/demoData.ts for a visual design
// review. None of this is computed from anything real yet — no follower/
// streak/rating/study-time/achievement system exists (see
// pages/profile/types.ts). Swap these back to null placeholders (or real
// values, once each system exists) once the review is done.
const DEMO_BIO = "Изучаю немецкий с целью свободного общения и путешествий ✈️";

export default function ProfilePage() {
  const { user, logout, updateLocalUser } = useAuth();
  const { theme, toggleTheme } = useTheme();
  const [form, setForm] = useState({
    firstName: user?.firstName ?? "",
    lastName: user?.lastName ?? "",
    email: user?.email ?? "",
    phone: user?.phone ?? "",
  });
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [avatarBusy, setAvatarBusy] = useState(false);
  const [idCopied, setIdCopied] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [rows, setRows] = useState<LessonRow[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [ids, progressData] = await Promise.all([
        Promise.resolve(listLessonIds()),
        api.get<{ progress: LessonProgressSummary[] }>("/api/me/progress").catch(() => ({ progress: [] })),
      ]);
      const lessons = await Promise.all(ids.map((id) => loadLesson(id)));
      if (cancelled) return;
      setRows(
        lessons.map((lesson) => ({
          lessonId: lesson.id,
          title: lesson.title.replace(/^\p{Extended_Pictographic}\s*/u, ""),
          summary: progressData.progress.find((p) => p.lessonId === lesson.id) ?? null,
        })),
      );
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // The one real, already-computable number in the stats grid: how far the
  // learner has gotten weighted by score, treating an unattempted lesson as
  // 0% rather than leaving it out of the average.
  const overallProgressPercent = useMemo(() => {
    if (!rows || rows.length === 0) return null;
    const earned = rows.reduce((sum, r) => sum + (r.summary?.bestScore ?? 0), 0);
    return Math.round(earned / rows.length);
  }, [rows]);

  const stats: ProfileStats = {
    followers: DEMO_SOCIAL.followers,
    mutualFollowers: DEMO_SOCIAL.mutualFollowers,
    following: DEMO_SOCIAL.following,
    streakDays: DEMO_STREAK_DAYS,
    overallProgressPercent,
    studyMinutes: DEMO_STUDY_MINUTES,
  };

  if (!user) return null;

  const copyUserId = async () => {
    if (!user) return;
    try {
      await navigator.clipboard.writeText(user.id);
    } catch {
      // Clipboard API is unavailable outside a secure context (e.g. plain
      // http on a phone) — fall back to a temporary selection copy.
      const field = document.createElement("textarea");
      field.value = user.id;
      field.style.position = "fixed";
      field.style.opacity = "0";
      document.body.appendChild(field);
      field.select();
      document.execCommand("copy");
      document.body.removeChild(field);
    }
    setIdCopied(true);
    setTimeout(() => setIdCopied(false), 2000);
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setSaveError(null);
    setSaved(false);
    setSaving(true);
    try {
      const data = await api.patch<{ user: StoredAuthUser }>("/api/me", form);
      updateLocalUser(data.user);
      setSaved(true);
    } catch (err) {
      setSaveError(err instanceof ApiError ? err.message : "Не удалось сохранить профиль");
    } finally {
      setSaving(false);
    }
  };

  const handleAvatarChange = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setAvatarBusy(true);
    try {
      const formData = new FormData();
      formData.append("avatar", file);
      const data = await api.post<{ user: StoredAuthUser }>("/api/me/avatar", formData);
      updateLocalUser(data.user);
    } catch {
      // avatar upload failing is non-critical to the rest of the page
    } finally {
      setAvatarBusy(false);
    }
  };

  const handleAvatarDelete = async () => {
    setAvatarBusy(true);
    try {
      const data = await api.delete<{ user: StoredAuthUser }>("/api/me/avatar");
      updateLocalUser(data.user);
    } finally {
      setAvatarBusy(false);
    }
  };

  return (
    <div className="app-shell profile-app-shell">
      <header className="profile-topbar">
        <Link to="/courses" className="profile-topbar__back" aria-label="Назад к курсам">
          ←
        </Link>
        <span className="profile-topbar__title">Профиль</span>
        <button
          type="button"
          className="profile-topbar__theme"
          onClick={toggleTheme}
          aria-label={theme === "light" ? "Включить тёмную тему" : "Включить светлую тему"}
          title={theme === "light" ? "Тёмная тема" : "Светлая тема"}
        >
          {theme === "light" ? "🌙" : "☀️"}
        </button>
      </header>

      <main className="home-main profile-main">
        <div className="profile-layout">
          <ProfileHeader
            user={user}
            bio={DEMO_BIO}
            stats={stats}
            avatarBusy={avatarBusy}
            fileInputRef={fileInputRef}
            onAvatarChange={handleAvatarChange}
            onAvatarDelete={handleAvatarDelete}
          />

          <StatsGrid stats={stats} level={DEMO_LEVEL} />

          <LevelProgress level={DEMO_LEVEL} />

          <AchievementsSection achievements={DEMO_ACHIEVEMENTS} />

          <RankingCard ranking={DEMO_RANKING} />

          <WeeklyActivity days={DEMO_WEEKLY_ACTIVITY} avgMinutesPerDay={DEMO_AVG_MINUTES_PER_DAY} />

          <ProfileNavList />

          <section className="profile-card" id="history">
            <div className="profile-section-head">
              <h2 className="profile-section-head__title">История занятий</h2>
            </div>
            {rows === null && <p className="stage-subtitle">Загрузка…</p>}
            {rows !== null && (
              <div className="progress-lesson-list">
                {rows.map((row, i) => (
                  <div className="progress-lesson-row" key={row.lessonId}>
                    <span className="progress-lesson-row__title">
                      Урок {i + 1}. {row.title}
                    </span>
                    {row.summary ? (
                      <span className="progress-lesson-row__stats">
                        Лучший результат: <strong>{row.summary.bestScore}%</strong> · попыток: {row.summary.attempts} ·
                        последняя: {row.summary.lastScore}%
                      </span>
                    ) : (
                      <span className="progress-lesson-row__stats progress-lesson-row__stats--muted">Не начат</span>
                    )}
                  </div>
                ))}
              </div>
            )}
          </section>

          <section className="profile-card" id="settings">
            <div className="profile-section-head">
              <h2 className="profile-section-head__title">Настройки</h2>
            </div>

            <div className="profile-quick-links">
              {(user.role === "ADMIN" || user.role === "TEACHER") && (
                <Link to="/admin/courses" className="btn btn-secondary">
                  Курсы (админ)
                </Link>
              )}
              {user.role === "ADMIN" && (
                <Link to="/admin" className="btn btn-secondary">
                  Пользователи
                </Link>
              )}
              <button type="button" className="btn btn-ghost" onClick={logout}>
                Выйти
              </button>
            </div>

            <div className="user-id-row">
              <span className="user-id-row__label">ID пользователя</span>
              <code className="user-id-row__value">{user.id}</code>
              <button type="button" className="btn btn-secondary" onClick={copyUserId}>
                {idCopied ? "Скопировано" : "Скопировать"}
              </button>
            </div>

            {!user.canEditProfile && (
              <div className="empty-state">
                <p>Редактирование профиля отключено администратором — данные доступны только для просмотра.</p>
              </div>
            )}

            <form className="auth-form" onSubmit={handleSubmit}>
              <label className="auth-field">
                <span>Имя</span>
                <input
                  value={form.firstName}
                  disabled={!user.canEditProfile}
                  onChange={(e) => setForm((f) => ({ ...f, firstName: e.target.value }))}
                />
              </label>
              <label className="auth-field">
                <span>Фамилия</span>
                <input
                  value={form.lastName}
                  disabled={!user.canEditProfile}
                  onChange={(e) => setForm((f) => ({ ...f, lastName: e.target.value }))}
                />
              </label>
              <label className="auth-field">
                <span>Email</span>
                <input
                  type="email"
                  value={form.email}
                  disabled={!user.canEditProfile}
                  onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
                />
              </label>
              <label className="auth-field">
                <span>Телефон</span>
                <input
                  value={form.phone}
                  disabled={!user.canEditProfile}
                  onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
                />
              </label>

              {saveError && <div className="exercise-feedback incorrect">{saveError}</div>}
              {saved && <div className="exercise-feedback correct">Профиль сохранён</div>}

              {user.canEditProfile && (
                <button className="btn btn-primary" type="submit" disabled={saving}>
                  {saving ? "Сохраняем…" : "Сохранить"}
                </button>
              )}
            </form>
          </section>
        </div>
      </main>

      <BottomNav />
    </div>
  );
}
