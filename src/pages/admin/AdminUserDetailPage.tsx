import { FormEvent, useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { api, ApiError } from "../../auth/api";
import { AdminUserSummary } from "../../auth/tokenStore";
import { useAuth } from "../../auth/AuthContext";
import { listLessonIds, loadLesson } from "../../content/loader";
import AdminTopNav from "../../components/admin/AdminTopNav";
import { formatDateTime } from "../../lib/formatDate";

interface LoginEvent {
  id: string;
  createdAt: string;
}

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

export default function AdminUserDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { user: currentUser } = useAuth();
  const isSelf = currentUser?.id === id;
  const [user, setUser] = useState<AdminUserSummary | null>(null);
  const [rows, setRows] = useState<LessonRow[] | null>(null);
  const [logins, setLogins] = useState<LoginEvent[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [newPassword, setNewPassword] = useState("");
  const [resetMessage, setResetMessage] = useState<string | null>(null);

  const load = async () => {
    if (!id) return;
    const [userData, progressData, loginsData, ids] = await Promise.all([
      api.get<{ user: AdminUserSummary }>(`/api/admin/users/${id}`),
      api.get<{ progress: LessonProgressSummary[] }>(`/api/admin/users/${id}/progress`),
      api.get<{ logins: LoginEvent[] }>(`/api/admin/users/${id}/logins`),
      Promise.resolve(listLessonIds()),
    ]);
    const lessons = await Promise.all(ids.map((lessonId) => loadLesson(lessonId)));
    setUser(userData.user);
    setLogins(loginsData.logins);
    setRows(
      lessons.map((lesson) => ({
        lessonId: lesson.id,
        title: lesson.title.replace(/^\p{Extended_Pictographic}\s*/u, ""),
        summary: progressData.progress.find((p) => p.lessonId === lesson.id) ?? null,
      })),
    );
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  if (!user) {
    return (
      <div className="app-shell">
        <main className="home-main">
          <p className="stage-subtitle">Загрузка…</p>
        </main>
      </div>
    );
  }

  const handleSave = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSaving(true);
    try {
      const data = await api.patch<{ user: AdminUserSummary }>(`/api/admin/users/${id}`, {
        firstName: user.firstName,
        lastName: user.lastName,
        email: user.email,
        phone: user.phone,
        username: user.username,
        role: user.role,
        canEditProfile: user.canEditProfile,
      });
      setUser(data.user);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Не удалось сохранить изменения");
    } finally {
      setSaving(false);
    }
  };

  const toggleStatus = async () => {
    const nextStatus = user.status === "ACTIVE" ? "BLOCKED" : "ACTIVE";
    setError(null);
    try {
      const data = await api.patch<{ user: AdminUserSummary }>(`/api/admin/users/${id}`, { status: nextStatus });
      setUser(data.user);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Не удалось изменить статус");
    }
  };

  const handleResetPassword = async (e: FormEvent) => {
    e.preventDefault();
    setResetMessage(null);
    try {
      await api.post(`/api/admin/users/${id}/reset-password`, { newPassword });
      setNewPassword("");
      setResetMessage("Пароль обновлён");
    } catch (err) {
      setResetMessage(err instanceof ApiError ? err.message : "Не удалось сбросить пароль");
    }
  };

  return (
    <div className="app-shell">
      <AdminTopNav back={{ label: "← К списку пользователей", to: "/admin" }} />
      <main className="home-main">
        <div className="admin-layout">
          <section className="profile-card">
            <h1 className="stage-title" style={{ fontSize: 22 }}>
              {user.firstName} {user.lastName}
            </h1>
            <p className="stage-subtitle">@{user.username}</p>

            <div className="user-id-row">
              <span className={`admin-status admin-status--${user.online ? "active" : "blocked"}`}>
                {user.online ? "● В сети сейчас" : "Не в сети"}
              </span>
              <span className="progress-lesson-row__stats--muted" style={{ fontSize: 12.5 }}>
                — пользовался платформой в последние 5 минут (учитывается любое действие, не только вход)
              </span>
            </div>

            <p className="stage-subtitle">
              Последний вход:{" "}
              {user.lastLoginAt ? <strong>{formatDateTime(user.lastLoginAt)}</strong> : "никогда не входил(а)"}
              <br />
              <span className="progress-lesson-row__stats--muted" style={{ fontSize: 12.5 }}>
                момент ввода пароля — не показывает, сколько потом человек оставался на сайте
              </span>
            </p>

            {user.lastActiveAt && (
              <p className="stage-subtitle">
                Последняя активность: <strong>{formatDateTime(user.lastActiveAt)}</strong>
                <br />
                <span className="progress-lesson-row__stats--muted" style={{ fontSize: 12.5 }}>
                  последний раз, когда человек что-то делал на платформе (не только вход) — по этому определяется
                  «в сети сейчас»
                </span>
              </p>
            )}

            <form className="auth-form" onSubmit={handleSave}>
              <div className="auth-form-grid">
                <label className="auth-field">
                  <span>Имя</span>
                  <input value={user.firstName} onChange={(e) => setUser({ ...user, firstName: e.target.value })} />
                </label>
                <label className="auth-field">
                  <span>Фамилия</span>
                  <input value={user.lastName} onChange={(e) => setUser({ ...user, lastName: e.target.value })} />
                </label>
                <label className="auth-field">
                  <span>Email</span>
                  <input value={user.email} onChange={(e) => setUser({ ...user, email: e.target.value })} />
                </label>
                <label className="auth-field">
                  <span>Телефон</span>
                  <input value={user.phone ?? ""} onChange={(e) => setUser({ ...user, phone: e.target.value })} />
                </label>
                <label className="auth-field">
                  <span>Логин</span>
                  <input value={user.username} onChange={(e) => setUser({ ...user, username: e.target.value })} />
                </label>
                <label className="auth-field">
                  <span>Роль</span>
                  <select
                    value={user.role}
                    disabled={isSelf}
                    onChange={(e) => setUser({ ...user, role: e.target.value as "ADMIN" | "USER" })}
                  >
                    <option value="USER">USER</option>
                    <option value="ADMIN">ADMIN</option>
                  </select>
                </label>
              </div>

              {isSelf && (
                <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
                  Это ваша учётная запись — снять с себя роль администратора или заблокировать себя нельзя.
                </p>
              )}

              <label className="admin-toggle-row">
                <input
                  type="checkbox"
                  checked={user.canEditProfile}
                  onChange={(e) => setUser({ ...user, canEditProfile: e.target.checked })}
                />
                <span>Пользователь может редактировать свой профиль</span>
              </label>

              {error && <div className="exercise-feedback incorrect">{error}</div>}

              <div className="stage-footer split">
                <button
                  type="button"
                  className={`btn ${user.status === "ACTIVE" ? "btn-secondary" : "btn-primary"}`}
                  onClick={toggleStatus}
                  disabled={isSelf}
                >
                  {user.status === "ACTIVE" ? "Заблокировать" : "Активировать"}
                </button>
                <button className="btn btn-primary" type="submit" disabled={saving}>
                  {saving ? "Сохраняем…" : "Сохранить"}
                </button>
              </div>
            </form>
          </section>

          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Сброс пароля
            </h2>
            <form className="auth-form" onSubmit={handleResetPassword}>
              <label className="auth-field">
                <span>Новый пароль</span>
                <input
                  required
                  minLength={6}
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                />
              </label>
              {resetMessage && (
                <div className={`exercise-feedback ${resetMessage === "Пароль обновлён" ? "correct" : "incorrect"}`}>
                  {resetMessage}
                </div>
              )}
              <button className="btn btn-secondary" type="submit">
                Сбросить пароль
              </button>
            </form>
          </section>

          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Прогресс по урокам
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

          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              История входов
            </h2>
            <p className="stage-subtitle" style={{ fontSize: 13 }}>
              Каждая запись — отдельный момент ввода пароля, не время нахождения на сайте.
            </p>
            {logins === null && <p className="stage-subtitle">Загрузка…</p>}
            {logins !== null && logins.length === 0 && (
              <p className="stage-subtitle progress-lesson-row__stats--muted">Ещё ни разу не входил(а).</p>
            )}
            {logins !== null && logins.length > 0 && (
              <div className="progress-lesson-list">
                {logins.map((login) => (
                  <div className="progress-lesson-row" key={login.id}>
                    <span className="progress-lesson-row__title">{formatDateTime(login.createdAt)}</span>
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
