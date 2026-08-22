import { Link } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";

/** Shown when ProtectedRoute refuses a route the signed-in user's role
 * doesn't allow (e.g. a TEACHER opening /admin/users). */
export default function ForbiddenPage() {
  const { user } = useAuth();

  return (
    <div className="app-shell">
      <main className="home-main">
        <div className="stage-panel" style={{ maxWidth: 520, margin: "60px auto" }}>
          <div className="stage-eyebrow">Ошибка 403</div>
          <h1 className="stage-title">Доступ запрещён</h1>
          <div className="empty-state">
            <h3>Недостаточно прав</h3>
            <p>
              {user?.role === "TEACHER"
                ? "Этот раздел доступен только администраторам."
                : "У вашей учётной записи нет доступа к этой странице."}
            </p>
          </div>
          <div className="stage-footer">
            <Link className="btn btn-primary" to="/">
              На главную
            </Link>
          </div>
        </div>
      </main>
    </div>
  );
}
