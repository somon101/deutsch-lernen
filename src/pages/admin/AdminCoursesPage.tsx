import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { listLessonIds, loadLesson } from "../../content/loader";
import { LessonContent } from "../../content/types";

export default function AdminCoursesPage() {
  const [lessons, setLessons] = useState<LessonContent[] | null>(null);

  useEffect(() => {
    Promise.all(listLessonIds().map((id) => loadLesson(id))).then(setLessons);
  }, []);

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
          <Link to="/profile" className="btn btn-ghost">
            Профиль
          </Link>
        </div>
      </nav>

      <main className="home-main">
        <div className="admin-layout">
          <p className="admin-breadcrumbs">Курсы → Немецкий с нуля</p>

          <section className="profile-card">
            <h1 className="stage-title" style={{ fontSize: 22 }}>
              Уроки курса
            </h1>
            <p className="stage-subtitle">
              Выберите урок, чтобы отредактировать его материал, словарь и вопросы.
            </p>

            {lessons === null && <p className="stage-subtitle">Загрузка…</p>}

            {lessons !== null && lessons.length === 0 && (
              <div className="empty-state">
                <h3>Уроки не найдены</h3>
                <p>Добавьте папку lesson1 (затем lesson2, lesson3…) с материалами урока в корень проекта.</p>
              </div>
            )}

            {lessons !== null && lessons.length > 0 && (
              <div className="progress-lesson-list">
                {lessons.map((lesson, i) => (
                  <div className="progress-lesson-row" key={lesson.id}>
                    <span className="progress-lesson-row__title">
                      Урок {i + 1}. {lesson.title.replace(/^\p{Extended_Pictographic}\s*/u, "")}
                    </span>
                    <span className="progress-lesson-row__stats">
                      {lesson.vocabulary.length} слов
                      {lesson.authoredQuestions.length > 0 && ` · ${lesson.authoredQuestions.length} своих вопросов`}
                      {lesson.hasContentOverrides ? " · отредактирован" : " · из файлов"}
                    </span>
                    <Link className="btn btn-secondary" to={`/admin/lessons/${lesson.id}`}>
                      Редактировать
                    </Link>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      </main>
    </div>
  );
}
