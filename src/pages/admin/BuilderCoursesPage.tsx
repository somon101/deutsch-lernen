import { FormEvent, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { ApiError, assetUrl } from "../../auth/api";
import { BuilderCourseSummary, builderApi } from "../../admin/builderApi";

export default function BuilderCoursesPage() {
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
      <nav className="top-nav">
        <Link to="/" className="brand">
          <span className="brand-flag">🇩🇪</span> Deutsch Lernen
        </Link>
        <div style={{ display: "flex", gap: 10 }}>
          <Link to="/admin" className="btn btn-ghost">
            Пользователи
          </Link>
          <Link to="/admin/courses" className="btn btn-ghost">
            Основной курс
          </Link>
        </div>
      </nav>

      <main className="home-main">
        <div className="admin-layout">
          <p className="admin-breadcrumbs">Конструктор курсов</p>

          <section className="profile-card">
            <h1 className="stage-title" style={{ fontSize: 22 }}>
              Мои курсы
            </h1>
            <p className="stage-subtitle">
              Курсы, собранные вручную в конструкторе. Каждый курс независим: изменения в одном никак не затрагивают
              остальные. Основной курс из файлов живёт отдельно и здесь не показывается.
            </p>

            {courses === null && <p className="stage-subtitle">Загрузка…</p>}

            {courses !== null && courses.length === 0 && (
              <div className="empty-state">
                <h3>Курсов пока нет</h3>
                <p>Создайте первый курс в форме ниже, а затем наполните его уроками.</p>
              </div>
            )}

            {courses !== null && courses.length > 0 && (
              <div className="builder-course-list">
                {courses.map((course, i) => (
                  <div className="builder-course-row" key={course.id}>
                    {course.coverUrl ? (
                      <img className="builder-cover" src={assetUrl(course.coverUrl)} alt="" />
                    ) : (
                      <div className="builder-cover builder-cover--empty">Без обложки</div>
                    )}

                    <div className="builder-course-row__main">
                      <span className="progress-lesson-row__title">{course.title}</span>
                      {course.description && (
                        <span className="progress-lesson-row__stats">{course.description}</span>
                      )}
                      <span className="progress-lesson-row__stats">
                        {course.lessonCount} уроков · {course.wordCount} слов · {course.questionCount} вопросов
                      </span>
                      <span className={`admin-status admin-status--${course.status === "PUBLISHED" ? "active" : "blocked"}`}>
                        {course.status === "PUBLISHED" ? "Опубликован" : "Черновик"}
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
            )}
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
