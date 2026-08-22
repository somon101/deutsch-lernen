import { FormEvent, useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { ApiError, assetUrl } from "../../auth/api";
import {
  BuilderCourse,
  BuilderLesson,
  QuestionSet,
  builderApi,
  uploadCourseCover,
} from "../../admin/builderApi";
import AdminTopNav from "../../components/admin/AdminTopNav";
import Breadcrumbs from "../../components/admin/Breadcrumbs";
import DragList from "./DragList";

const STATUS_LABEL = { DRAFT: "Черновик", PUBLISHED: "Опубликован" } as const;

export const SET_LABELS: Record<QuestionSet, string> = {
  minitest: "Мини-тест",
  practice: "Практика",
  review: "Закрепление",
};

export default function BuilderCourseEditPage() {
  const { courseId = "" } = useParams();
  const navigate = useNavigate();

  const [course, setCourse] = useState<BuilderCourse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);

  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [newLessonTitle, setNewLessonTitle] = useState("");

  useEffect(() => {
    let cancelled = false;
    builderApi
      .get(courseId)
      .then((c) => {
        if (cancelled) return;
        setCourse(c);
        setTitle(c.title);
        setDescription(c.description);
      })
      .catch(() => navigate("/admin/courses", { replace: true }));
    return () => {
      cancelled = true;
    };
  }, [courseId, navigate]);

  const flash = (key: string) => {
    setSaved(key);
    setTimeout(() => setSaved((s) => (s === key ? null : s)), 2500);
  };

  /** Runs the mutation, then re-fetches the course so state stays in sync —
   * shared with the legacy-lesson editor, whose mutations don't have a
   * BuilderCourse to hand back directly (see AdminLessonEditPage.tsx). */
  const run = async (key: string, action: () => Promise<unknown>) => {
    setError(null);
    setBusy(key);
    try {
      await action();
      setCourse(await builderApi.get(courseId));
      flash(key);
    } catch (err) {
      setError(err instanceof ApiError || err instanceof Error ? err.message : "Не удалось сохранить");
    } finally {
      setBusy(null);
    }
  };

  if (!course) {
    return (
      <div className="app-shell">
        <main className="home-main">
          <p className="stage-subtitle" style={{ textAlign: "center" }}>
            Загрузка курса…
          </p>
        </main>
      </div>
    );
  }

  const saveCourse = (e: FormEvent) => {
    e.preventDefault();
    run("course", () => builderApi.update(courseId, { title, description }));
  };

  const togglePublish = () =>
    run("status", () =>
      builderApi.update(courseId, { status: course.status === "PUBLISHED" ? "DRAFT" : "PUBLISHED" }),
    );

  const addLesson = (e: FormEvent) => {
    e.preventDefault();
    if (!newLessonTitle.trim()) return;
    run("addLesson", async () => {
      const next = await builderApi.addLesson(courseId, { title: newLessonTitle.trim() });
      setNewLessonTitle("");
      return next;
    });
  };

  const reorderLessons = (ids: string[]) => run("reorder", () => builderApi.reorderLessons(courseId, ids));

  const removeLesson = (lesson: BuilderLesson) => {
    if (!window.confirm(`Удалить урок «${lesson.title}» вместе со словами и вопросами?`)) return;
    run("removeLesson", () => builderApi.removeLesson(courseId, lesson.id));
  };

  const totalWords = course.lessons.reduce((n, l) => n + l.vocabulary.length, 0);
  const totalQuestions = course.lessons.reduce(
    (n, l) => n + l.blocks.reduce((m, b) => m + b.questions.length, 0),
    0,
  );

  return (
    <div className="app-shell">
      <AdminTopNav back={{ label: "← Ко всем курсам", to: "/admin/courses" }} />

      <main className="home-main">
        <div className="admin-layout">
          <Breadcrumbs items={[{ label: "Курсы", to: "/admin/courses" }, { label: course.title }]} />

          {error && <div className="exercise-feedback incorrect">{error}</div>}

          {/* ------------------------- Course settings ------------------------- */}
          <section className="profile-card">
            <div className="builder-course-head">
              <h1 className="stage-title" style={{ fontSize: 22 }}>
                {course.title}
              </h1>
              <span className={`admin-status admin-status--${course.status === "PUBLISHED" ? "active" : "blocked"}`}>
                {STATUS_LABEL[course.status]}
              </span>
            </div>

            <form className="auth-form" onSubmit={saveCourse}>
              <label className="auth-field">
                <span>Название курса</span>
                <input required value={title} onChange={(e) => setTitle(e.target.value)} />
              </label>
              <label className="auth-field">
                <span>Описание</span>
                <textarea
                  className="admin-textarea"
                  rows={3}
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                />
              </label>

              <div className="builder-cover-row">
                {course.coverUrl ? (
                  <img className="builder-cover" src={assetUrl(course.coverUrl)} alt="" />
                ) : (
                  <div className="builder-cover builder-cover--empty">Без обложки</div>
                )}
                <div className="profile-avatar-actions">
                  <label className="btn btn-secondary">
                    {course.coverUrl ? "Заменить обложку" : "Загрузить обложку"}
                    <input
                      type="file"
                      accept="image/jpeg,image/png,image/webp"
                      hidden
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        e.target.value = "";
                        if (file) run("cover", () => uploadCourseCover(courseId, file));
                      }}
                    />
                  </label>
                  {course.coverUrl && (
                    <button type="button" className="btn btn-ghost" onClick={() => run("cover", () => builderApi.removeCover(courseId))}>
                      Удалить обложку
                    </button>
                  )}
                </div>
              </div>

              <div className="stage-footer split">
                <button type="button" className="btn btn-secondary" onClick={togglePublish} disabled={busy === "status"}>
                  {course.status === "PUBLISHED" ? "Вернуть в черновики" : "Опубликовать курс"}
                </button>
                <span style={{ display: "flex", alignItems: "center", gap: 12 }}>
                  {saved === "course" && <span className="admin-saved">Сохранено</span>}
                  <button className="btn btn-primary" type="submit" disabled={busy === "course"}>
                    {busy === "course" ? "Сохраняем…" : "Сохранить курс"}
                  </button>
                </span>
              </div>
            </form>
          </section>

          {/* --------------------------- Course tree --------------------------- */}
          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Структура курса
            </h2>
            <p className="stage-subtitle">
              {course.lessons.length} уроков · {totalWords} слов · {totalQuestions} вопросов
            </p>

            <div className="builder-tree">
              <div className="builder-tree__root">📘 {course.title}</div>
              {course.lessons.length === 0 && (
                <div className="builder-tree__empty">Уроков пока нет — добавьте первый ниже.</div>
              )}
              <DragList
                items={course.lessons}
                onReorder={reorderLessons}
                renderItem={(lesson, i) => (
                  <div className="builder-tree__lesson">
                    <div className="builder-tree__lesson-head">
                      <button
                        type="button"
                        className="builder-tree__toggle"
                        onClick={() => navigate(`/admin/builder/${courseId}/lessons/${lesson.id}`)}
                      >
                        {/* The number comes from the position, so it stays right
                            however the admin chooses to name the lesson. */}
                        <span className="builder-tree__index">{i + 1}</span>
                        {lesson.title}
                        <span className="builder-tree__open-hint">Открыть →</span>
                      </button>
                      <div className="builder-order">
                        <button type="button" className="btn btn-ghost admin-row__remove" onClick={() => removeLesson(lesson)}>
                          Удалить
                        </button>
                      </div>
                    </div>

                    <ul className="builder-tree__parts">
                      <li className={lesson.vocabulary.length ? "" : "is-missing"}>
                        <span>Слова</span>
                        <span>{lesson.vocabulary.length}</span>
                      </li>
                      <li className={lesson.materialText ? "" : "is-missing"}>
                        <span>Материал</span>
                        <span>{lesson.materialText ? "заполнен" : "пусто"}</span>
                      </li>
                      <li className={lesson.videoUrl ? "" : "is-missing"}>
                        <span>Видео</span>
                        <span>{lesson.videoUrl ? "есть" : "нет"}</span>
                      </li>
                      <li className={lesson.audioUrl ? "" : "is-missing"}>
                        <span>Аудио</span>
                        <span>{lesson.audioUrl ? "есть" : "нет"}</span>
                      </li>
                      {(Object.keys(SET_LABELS) as QuestionSet[]).map((stage) => {
                        const blocks = lesson.blocks.filter((b) => b.stage === stage);
                        const n = blocks.reduce((sum, b) => sum + b.questions.length, 0);
                        return (
                          <li key={stage} className={blocks.length ? "" : "is-missing"}>
                            <span>{SET_LABELS[stage]}</span>
                            <span>{blocks.length ? `${blocks.length} бл. · ${n} вопр.` : "нет блоков"}</span>
                          </li>
                        );
                      })}
                    </ul>
                  </div>
                )}
              />
            </div>

            <form className="builder-add-lesson" onSubmit={addLesson}>
              <input
                value={newLessonTitle}
                onChange={(e) => setNewLessonTitle(e.target.value)}
                placeholder="Название нового урока"
              />
              <button className="btn btn-secondary" type="submit" disabled={busy === "addLesson"}>
                + Добавить урок
              </button>
            </form>
          </section>
        </div>
      </main>
    </div>
  );
}
