import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { assetUrl } from "../auth/api";
import { BuilderCourseSummary, listPublishedCourses } from "../content/learnerCourses";
import ProfileNavLink from "../components/ProfileNavLink";

/** Learner-facing hub: the legacy course card, plus one card per published
 * course built in the admin constructor. Purely additive — the legacy
 * course's own page (Home.tsx, at "/") is unchanged and reachable from here. */
export default function CoursesPage() {
  const { user } = useAuth();
  const [courses, setCourses] = useState<BuilderCourseSummary[] | null>(null);

  useEffect(() => {
    listPublishedCourses().then(setCourses);
  }, []);

  return (
    <div className="app-shell">
      <nav className="top-nav">
        <Link to="/" className="brand">
          <span className="brand-flag">🇩🇪</span> Deutsch Lernen
        </Link>
        {user ? (
          <div style={{ display: "flex", gap: 10 }}>
            {(user.role === "ADMIN" || user.role === "TEACHER") && (
              <Link to="/admin/courses" className="btn btn-ghost">
                Курсы (админ)
              </Link>
            )}
            {user.role === "ADMIN" && (
              <Link to="/admin" className="btn btn-ghost">
                Admin
              </Link>
            )}
            <ProfileNavLink />
          </div>
        ) : (
          <Link to="/login" className="btn btn-ghost">
            Войти
          </Link>
        )}
      </nav>

      <main className="home-main">
        <div className="home-hero">
          <h1>Курсы</h1>
          <p>Выберите курс, чтобы продолжить обучение</p>
        </div>

        <div className="lesson-grid">
          <Link to="/" className="lesson-card">
            <span className="lesson-card__title">Немецкий с нуля</span>
            <span className="lesson-card__meta">Основной курс</span>
          </Link>

          {courses === null && <p style={{ textAlign: "center", color: "var(--color-text-muted)" }}>Загрузка курсов…</p>}

          {courses?.map((course) => (
            <Link key={course.id} to={`/courses/${course.id}`} className="lesson-card">
              {course.coverUrl && <img src={assetUrl(course.coverUrl)} alt="" className="builder-cover" />}
              <span className="lesson-card__title">{course.title}</span>
              <span className="lesson-card__meta">
                {course.description || `${course.lessonCount} уроков`}
              </span>
            </Link>
          ))}
        </div>
      </main>
    </div>
  );
}
