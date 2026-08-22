import { FormEvent, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { ApiError, assetUrl } from "../../auth/api";
import { BuilderCourseSummary, builderApi } from "../../admin/builderApi";
import { listLessonIds } from "../../content/loader";
import AdminTopNav from "../../components/admin/AdminTopNav";
import Breadcrumbs from "../../components/admin/Breadcrumbs";

const STATUS_LABEL = { DRAFT: "Черновик", PUBLISHED: "Опубликован" } as const;

/**
 * Unified "Курсы" hub: the original file-based course and every course made
 * in the constructor, in one list. A newly created course shows up here
 * immediately — this is the single place an admin opens to reach any course.
 */
export default function AdminCoursesHubPage() {
  const [courses, setCourses] = useState<BuilderCourseSummary[] | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = () => builderApi.list().then(setCourses);

  useEffect(() => {
    load();
  }, []);

  const handleCreate = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await builderApi.create({ title, description });
      setTitle("");
      setDescription("");
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Не удалось создать курс");
    } finally {
      setBusy(false);
    }
  };

  const move = async (index: number, delta: number) => {
    if (!courses) return;
    const next = [...courses];
    const target = index + delta;
    if (target < 0 || target >= next.length) return;
    [next[index], next[target]] = [next[target], next[index]];
    setCourses(next);
    setCourses(await builderApi.reorderCourses(next.map((c) => c.id)));
  };

  const remove = async (course: BuilderCourseSummary) => {
    if (!window.confirm(`Удалить курс «${course.title}» со всеми уроками и словами? Это действие необратимо.`)) return;
    await builderApi.remove(course.id);
    await load();
  };

  return (
    <div className="app-shell">
      <AdminTopNav back={{ label: "← На главную", to: "/" }} />

      <main className="home-main">
        <div className="admin-layout">
          <Breadcrumbs items={[{ label: "Курсы" }]} />

          <section className="profile-card">
            <h1 className="stage-title" style={{ fontSize: 22 }}>
              Курсы
            </h1>
            <p className="stage-subtitle">
              Основной курс и курсы, собранные в конструкторе — все в одном списке. Каждый курс независим: изменения в
              одном никак не затрагивают остальные.
            </p>

            <div className="builder-course-list">
              <div className="builder-course-row">
                <div className="builder-cover builder-cover--empty">🇩🇪</div>
                <div className="builder-course-row__main">
                  <span className="progress-lesson-row__title">Немецкий с нуля</span>
                  <span className="progress-lesson-row__stats">{listLessonIds().length} уроков · основной курс из файлов</span>
                </div>
                <div className="builder-course-row__actions">
                  <Link className="btn btn-secondary" to="/admin/courses/legacy">
                    Открыть
                  </Link>
                </div>
              </div>

              {courses === null && <p className="stage-subtitle">Загрузка…</p>}

              {courses?.map((course, i) => (
                <div className="builder-course-row" key={course.id}>
                  {course.coverUrl ? (
                    <img className="builder-cover" src={assetUrl(course.coverUrl)} alt="" />
                  ) : (
                    <div className="builder-cover builder-cover--empty">Без обложки</div>
                  )}

                  <div className="builder-course-row__main">
                    <span className="progress-lesson-row__title">{course.title}</span>
                    {course.description && <span className="progress-lesson-row__stats">{course.description}</span>}
                    <span className="progress-lesson-row__stats">
                      {course.lessonCount} уроков · {course.wordCount} слов · {course.questionCount} вопросов
                    </span>
                    <span className={`admin-status admin-status--${course.status === "PUBLISHED" ? "active" : "blocked"}`}>
                      {STATUS_LABEL[course.status]}
                    </span>
                  </div>

                  <div className="builder-course-row__actions">
                    <div className="builder-order">
                      <button type="button" className="btn btn-ghost" onClick={() => move(i, -1)} disabled={i === 0}>
                        ↑
                      </button>
                      <button
                        type="button"
                        className="btn btn-ghost"
                        onClick={() => move(i, 1)}
                        disabled={i === courses.length - 1}
                      >
                        ↓
                      </button>
                    </div>
                    <Link className="btn btn-secondary" to={`/admin/builder/${course.id}`}>
                      Открыть
                    </Link>
                    <button type="button" className="btn btn-ghost admin-row__remove" onClick={() => remove(course)}>
                      Удалить
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Создать курс
            </h2>
            <form className="auth-form" onSubmit={handleCreate}>
              <label className="auth-field">
                <span>Название курса</span>
                <input required value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Немецкий A2" />
              </label>
              <label className="auth-field">
                <span>Описание</span>
                <textarea
                  className="admin-textarea"
                  rows={3}
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Коротко о том, для кого этот курс"
                />
              </label>

              {error && <div className="exercise-feedback incorrect">{error}</div>}

              <div className="stage-footer">
                <button className="btn btn-primary" type="submit" disabled={busy}>
                  {busy ? "Создаём…" : "Создать курс"}
                </button>
              </div>
            </form>
            <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
              Новый курс создаётся пустым. Ничего не копируется из других курсов — уроки, слова и вопросы вы добавляете
              вручную.
            </p>
          </section>
        </div>
      </main>
    </div>
  );
}
