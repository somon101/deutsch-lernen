import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { BuilderCourse, builderApi } from "../../admin/builderApi";
import AdminTopNav from "../../components/admin/AdminTopNav";
import Breadcrumbs from "../../components/admin/Breadcrumbs";
import BuilderLessonEditor from "./BuilderLessonEditor";

/**
 * Full-screen editor for one lesson of a builder course — its own page
 * (rather than an inline-expanding row inside BuilderCourseEditPage), so the
 * node-flow chain gets real room, with an explicit exit back to the course.
 * Nothing about how a lesson is edited changes here; only that it now opens
 * as a dedicated screen instead of expanding in place.
 */
export default function BuilderLessonEditPage() {
  const { courseId = "", lessonId = "" } = useParams();
  const navigate = useNavigate();

  const [course, setCourse] = useState<BuilderCourse | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    builderApi
      .get(courseId)
      .then((c) => {
        if (!cancelled) setCourse(c);
      })
      .catch(() => navigate(`/admin/builder/${courseId}`, { replace: true }));
    return () => {
      cancelled = true;
    };
  }, [courseId, navigate]);

  const flash = (key: string) => {
    setSaved(key);
    setTimeout(() => setSaved((s) => (s === key ? null : s)), 2500);
  };

  const run = async (key: string, action: () => Promise<unknown>) => {
    setError(null);
    setBusy(key);
    try {
      await action();
      setCourse(await builderApi.get(courseId));
      flash(key);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось сохранить");
    } finally {
      setBusy(null);
    }
  };

  const lesson = course?.lessons.find((l) => l.id === lessonId);

  if (!course) {
    return (
      <div className="app-shell">
        <main className="home-main">
          <p className="stage-subtitle" style={{ textAlign: "center" }}>
            Загрузка урока…
          </p>
        </main>
      </div>
    );
  }

  if (!lesson) {
    navigate(`/admin/builder/${courseId}`, { replace: true });
    return null;
  }

  return (
    <div className="app-shell">
      <AdminTopNav back={{ label: "← Выйти из редактора", to: `/admin/builder/${courseId}` }} />

      <main className="home-main">
        <div className="admin-layout admin-layout--wide">
          <Breadcrumbs
            items={[
              { label: "Курсы", to: "/admin/courses" },
              { label: course.title, to: `/admin/builder/${courseId}` },
              { label: lesson.title },
            ]}
          />

          {error && <div className="exercise-feedback incorrect">{error}</div>}

          <BuilderLessonEditor courseId={courseId} lesson={lesson} busy={busy} saved={saved} onRun={run} />
        </div>
      </main>
    </div>
  );
}
