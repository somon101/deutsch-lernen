import { ChangeEvent, FormEvent, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { api, ApiError, assetUrl } from "../auth/api";
import { StoredAuthUser } from "../auth/tokenStore";
import { listLessonIds, loadLesson } from "../content/loader";

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

export default function ProfilePage() {
  const { user, logout, updateLocalUser } = useAuth();
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
    <div className="app-shell">
      <nav className="top-nav">
        <Link to="/" className="brand">
          <span className="brand-flag">🇩🇪</span> Deutsch Lernen
        </Link>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          <Link to="/" className="btn btn-secondary">
            ← К урокам
          </Link>
          {user.role === "ADMIN" && (
            <Link to="/admin" className="btn btn-ghost">
              Admin
            </Link>
          )}
          <button className="btn btn-ghost" onClick={logout}>
            Выйти
          </button>
        </div>
      </nav>
      <main className="home-main">
        <div className="profile-layout">
          <section className="profile-card">
            <div className="profile-avatar-row">
              {user.avatarUrl ? (
                <img className="profile-avatar" src={assetUrl(user.avatarUrl)} alt="" />
              ) : (
                <div className="profile-avatar profile-avatar--placeholder">
                  {user.firstName[0]}
                  {user.lastName[0]}
                </div>
              )}
              <div className="profile-avatar-actions">
                <button className="btn btn-secondary" disabled={avatarBusy} onClick={() => fileInputRef.current?.click()}>
                  {user.avatarUrl ? "Заменить фото" : "Загрузить фото"}
                </button>
                {user.avatarUrl && (
                  <button className="btn btn-ghost" disabled={avatarBusy} onClick={handleAvatarDelete}>
                    Удалить фото
                  </button>
                )}
                <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={handleAvatarChange} />
              </div>
            </div>

            <h1 className="stage-title">
              {user.firstName} {user.lastName}
            </h1>
            <p className="stage-subtitle">@{user.username}</p>

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

          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Мой прогресс
            </h2>
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
        </div>
      </main>
    </div>
  );
}
