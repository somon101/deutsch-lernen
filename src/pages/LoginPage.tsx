import { FormEvent, useState } from "react";
import { Navigate, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { ApiError } from "../auth/api";

export default function LoginPage() {
  const { user, login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [loginValue, setLoginValue] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Lands in the learning platform itself, or back at whatever protected
  // page the user originally asked for.
  const from = (location.state as { from?: string } | null)?.from ?? "/";

  // An existing session shouldn't have to log in again on every reload.
  if (user) return <Navigate to={from} replace />;

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await login(loginValue, password);
      navigate(from, { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Не удалось выполнить вход. Проверьте подключение к серверу.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="app-shell">
      <nav className="top-nav">
        <span className="brand">
          <span className="brand-flag">🇩🇪</span> Deutsch Lernen
        </span>
      </nav>
      <main className="home-main">
        <div className="auth-card">
          <h1 className="stage-title">Вход</h1>
          <p className="stage-subtitle">Войдите, чтобы начать обучение — ваш прогресс сохраняется в вашем аккаунте.</p>

          <form className="auth-form" onSubmit={handleSubmit}>
            <label className="auth-field">
              <span>Логин или email</span>
              <input value={loginValue} onChange={(e) => setLoginValue(e.target.value)} autoComplete="username" required />
            </label>
            <label className="auth-field">
              <span>Пароль</span>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
                required
              />
            </label>

            {error && <div className="exercise-feedback incorrect">{error}</div>}

            <button className="btn btn-primary btn-block" type="submit" disabled={submitting}>
              {submitting ? "Входим…" : "Войти"}
            </button>
          </form>
        </div>
      </main>
    </div>
  );
}
