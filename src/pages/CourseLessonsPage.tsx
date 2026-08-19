import { useEffect, useState } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { BuilderCourse, loadBuilderCourse } from "../content/learnerCourses";
import { useProgressStore } from "../progress/ProgressContext";
import { courseProgressRatio, nextIncompleteStage } from "../progress/types";
import Breadcrumbs from "../components/admin/Breadcrumbs";

/** Lesson list for one published builder course — the same card-grid pattern
 * as Home.tsx, sourced from the builder API instead of the on-disk lessons. */
export default function CourseLessonsPage() {
  const { courseId = "" } = useParams();
  const { user } = useAuth();
  const [course, setCourse] = useState<BuilderCourse | null>(null);
  const [notFound, setNotFound] = useState(false);
  const { store, isLoaded: progressLoaded } = useProgressStore();

  useEffect(() => {
    let cancelled = false;
    loadBuilderCourse(courseId)
      .then((c) => {
        if (!cancelled) setCourse(c);
      })
      .catch(() => {
        if (!cancelled) setNotFound(true);
      });
    return () => {
      cancelled = true;
    };
  }, [courseId]);

  if (notFound) return <Navigate to="/courses" replace />;

  return (
    <div className="app-shell">
      <nav className="top-nav">
        <Link to="/" className="brand">
          <span className="brand-flag">🇩🇪</span> Deutsch Lernen
        </Link>
        <div style={{ display: "flex", gap: 10 }}>
          <Link to="/courses" className="btn btn-ghost">
            ← Все курсы
          </Link>
          {user?.role === "ADMIN" && (
            <Link to="/admin" className="btn btn-ghost">
              Admin
            </Link>
          )}
          <Link to="/profile" className="btn btn-ghost">
            {user?.firstName ?? "Профиль"}
          </Link>
        </div>
      </nav>

      <main className="home-main">
        {!course || !progressLoaded ? (
          <p style={{ textAlign: "center", color: "var(--color-text-muted)" }}>Загрузка…</p>
        ) : (
          <>
            <Breadcrumbs items={[{ label: "Курсы", to: "/courses" }, { label: course.title }]} />
            <div className="home-hero">
              <h1>{course.title}</h1>
              {course.description && <p>{course.description}</p>}
            </div>

            {course.lessons.length === 0 && (
              <div className="empty-state">
                <h3>Уроков пока нет</h3>
                <p>Администратор ещё наполняет этот курс.</p>
              </div>
            )}

            {course.lessons.length > 0 && (
              <div className="lesson-grid">
                {course.lessons.map((lesson, i) => {
                  const progress = store[lesson.id];
                  const ratio = courseProgressRatio(progress);
                  const completed = progress?.completedStages.includes("complete");
                  const target = progress ? nextIncompleteStage(progress) : "vocabulary";

                  return (
                    <Link key={lesson.id} to={`/courses/${courseId}/lesson/${lesson.id}/${target}`} className="lesson-card">
                      <span className="lesson-card__badge">{i + 1}</span>
                      <span className="lesson-card__title">{lesson.title}</span>
                      <span className="lesson-card__meta">{lesson.vocabulary.length} слов</span>
                      <div className="lesson-card__bar">
                        <div className="lesson-card__bar-fill" style={{ width: `${Math.round(ratio * 100)}%` }} />
                      </div>
                      {completed ? (
                        <span className="lesson-card__status">✓ Урок завершён</span>
                      ) : (
                        <span className="lesson-card__meta">{ratio > 0 ? "Продолжить" : "Начать урок"}</span>
                      )}
                    </Link>
                  );
                })}
              </div>
            )}
          </>
        )}
      </main>
    </div>
  );
}
