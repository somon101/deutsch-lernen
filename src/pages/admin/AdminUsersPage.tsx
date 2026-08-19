import { FormEvent, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../../auth/AuthContext";
import { api, ApiError } from "../../auth/api";
import { StoredAuthUser } from "../../auth/tokenStore";
import AdminTopNav from "../../components/admin/AdminTopNav";

const emptyForm = {
  firstName: "",
  lastName: "",
  email: "",
  phone: "",
  username: "",
  password: "",
  canEditProfile: true,
};

export default function AdminUsersPage() {
  const { logout } = useAuth();
  const [users, setUsers] = useState<StoredAuthUser[] | null>(null);
  const [form, setForm] = useState(emptyForm);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    const data = await api.get<{ users: StoredAuthUser[] }>("/api/admin/users");
    setUsers(data.users);
  };

  useEffect(() => {
    load();
  }, []);

  const handleCreate = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setCreating(true);
    try {
      await api.post("/api/admin/users", form);
      setForm(emptyForm);
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Не удалось создать пользователя");
    } finally {
      setCreating(false);
    }
  };

  return (
    <div className="app-shell">
      <AdminTopNav
        extra={
          <button className="btn btn-ghost" onClick={logout}>
            Выйти
          </button>
        }
      />
      <main className="home-main">
        <div className="admin-layout">
          <section className="profile-card">
            <h1 className="stage-title" style={{ fontSize: 22 }}>
              Пользователи
            </h1>
            {users === null && <p className="stage-subtitle">Загрузка…</p>}
            {users !== null && (
              <div className="admin-table-wrap">
                <table className="admin-table">
                  <thead>
                    <tr>
                      <th>Имя</th>
                      <th>Логин</th>
                      <th>Email</th>
                      <th>Роль</th>
                      <th>Статус</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {users.map((u) => (
                      <tr key={u.id}>
                        <td>
                          {u.firstName} {u.lastName}
                        </td>
                        <td>{u.username}</td>
                        <td>{u.email}</td>
                        <td>{u.role}</td>
                        <td>
                          <span className={`admin-status admin-status--${u.status === "ACTIVE" ? "active" : "blocked"}`}>
                            {u.status === "ACTIVE" ? "Активен" : "Заблокирован"}
                          </span>
                        </td>
                        <td>
                          <Link className="btn btn-secondary" to={`/admin/users/${u.id}`}>
                            Открыть
                          </Link>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Создать пользователя
            </h2>
            <form className="auth-form" onSubmit={handleCreate}>
              <div className="auth-form-grid">
                <label className="auth-field">
                  <span>Имя</span>
                  <input required value={form.firstName} onChange={(e) => setForm((f) => ({ ...f, firstName: e.target.value }))} />
                </label>
                <label className="auth-field">
                  <span>Фамилия</span>
                  <input required value={form.lastName} onChange={(e) => setForm((f) => ({ ...f, lastName: e.target.value }))} />
                </label>
                <label className="auth-field">
                  <span>Email</span>
                  <input required type="email" value={form.email} onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))} />
                </label>
                <label className="auth-field">
                  <span>Телефон</span>
                  <input value={form.phone} onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
                </label>
                <label className="auth-field">
                  <span>Логин</span>
                  <input
                    required
                    minLength={3}
                    maxLength={32}
                    pattern="[A-Za-z]+"
                    title="Только латинские буквы (A-Z, a-z), без цифр, пробелов и знаков"
                    value={form.username}
                    onChange={(e) => setForm((f) => ({ ...f, username: e.target.value }))}
                  />
                  <small className="auth-field__hint">
                    Только латинские буквы. Регистр не важен: Ivan и ivan — один и тот же логин.
                  </small>
                </label>
                <label className="auth-field">
                  <span>Первоначальный пароль</span>
                  <input
                    required
                    type="text"
                    minLength={6}
                    value={form.password}
                    onChange={(e) => setForm((f) => ({ ...f, password: e.target.value }))}
                  />
                </label>
              </div>

              <label className="admin-toggle-row">
                <input
                  type="checkbox"
                  checked={form.canEditProfile}
                  onChange={(e) => setForm((f) => ({ ...f, canEditProfile: e.target.checked }))}
                />
                <span>Пользователь может редактировать свой профиль</span>
              </label>

              {error && <div className="exercise-feedback incorrect">{error}</div>}

              <button className="btn btn-primary" type="submit" disabled={creating}>
                {creating ? "Создаём…" : "Создать пользователя"}
              </button>
            </form>
          </section>
        </div>
      </main>
    </div>
  );
}
