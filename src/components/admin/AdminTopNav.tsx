import { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../../auth/AuthContext";
import ProfileNavLink from "../ProfileNavLink";

/**
 * Shared top bar for every admin/profile page, so "Курсы" / "Пользователи" /
 * "Профиль" are always one click away instead of only appearing on whichever
 * page happened to hand-roll a link to them. `back` adds an optional
 * page-specific "← Назад к …" link before those three; `extra` adds
 * page-specific controls (e.g. a logout button) after them. "Пользователи"
 * only renders for ADMIN — a TEACHER has no access to that section (see
 * ProtectedRoute's adminOnly), so linking to it would just dead-end at /403.
 */
export default function AdminTopNav({ back, extra }: { back?: { label: string; to: string }; extra?: ReactNode }) {
  const { user } = useAuth();

  return (
    <nav className="top-nav">
      <Link to="/" className="brand">
        <span className="brand-flag">🇩🇪</span> Deutsch Lernen
      </Link>
      <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
        {back && (
          <Link to={back.to} className="btn btn-ghost">
            {back.label}
          </Link>
        )}
        <Link to="/admin/courses" className="btn btn-ghost">
          Курсы
        </Link>
        {user?.role === "ADMIN" && (
          <Link to="/admin" className="btn btn-ghost">
            Пользователи
          </Link>
        )}
        <ProfileNavLink label="Профиль" />
        {extra}
      </div>
    </nav>
  );
}
