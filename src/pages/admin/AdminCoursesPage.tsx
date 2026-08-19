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
          <Link to="/admin/builder" className="btn btn-ghost">
            Конструктор
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
              Полная структура курса: материал, видео, аудиоурок, словарь и вопросы каждого этапа. Выберите урок,
              чтобы отредактировать его содержимое.
            </p>

            {lessons === null && <p className="stage-subtitle">Загрузка…</p>}

            {lessons !== null && lessons.length === 0 && (
              <div className="empty-state">
                <h3>Уроки не найдены</h3>
                <p>Добавьте папку lesson1 (затем lesson2, lesson3…) с материалами урока в корень проекта.</p>
              </div>
            )}

            {lessons !== null && lessons.length > 0 && (
              <div className="admin-course-tree">
                {lessons.map((lesson, i) => {
                  const authored = (set: string) => lesson.authoredQuestions.filter((q) => q.setName === set).length;
                  const withAudio = lesson.vocabulary.filter((v) => v.audioUrl).length;
                  const parts: { label: string; value: string; ok: boolean }[] = [
                    { label: "Материал", value: lesson.materialText ? "есть" : "нет", ok: Boolean(lesson.materialText) },
                    { label: "Видео", value: lesson.assets.video ? "есть" : "нет", ok: Boolean(lesson.assets.video) },
                    { label: "Аудиоурок", value: lesson.assets.audio ? "есть" : "нет", ok: Boolean(lesson.assets.audio) },
                    {
                      label: "Словарь",
                      value: `${lesson.vocabulary.length} слов · озвучено ${withAudio}`,
                      ok: lesson.vocabulary.length > 0,
                    },
                    {
                      label: "Мини-тест",
                      value: authored("minitest") ? `${authored("minitest")} своих вопросов` : "генерируется",
                      ok: true,
                    },
                    {
                      label: "Практика",
                      value: authored("practice") ? `${authored("practice")} своих вопросов` : "генерируется",
                      ok: true,
                    },
                    {
                      label: "Закрепление (итоговый тест)",
                      value: authored("review") ? `${authored("review")} своих вопросов` : "генерируется",
                      ok: true,
                    },
                  ];

                  return (
                    <div className="admin-course-lesson" key={lesson.id}>
                      <div className="admin-course-lesson__head">
                        <span className="progress-lesson-row__title">
                          Урок {i + 1}. {lesson.title.replace(/^\p{Extended_Pictographic}\s*/u, "")}
                        </span>
                        <Link className="btn btn-secondary" to={`/admin/lessons/${lesson.id}`}>
                          Редактировать
                        </Link>
                      </div>
                      <span className="progress-lesson-row__stats">
                        {lesson.hasContentOverrides ? "отредактирован в панели" : "используются файлы урока"}
                      </span>
                      <ul className="admin-course-parts">
                        {parts.map((part) => (
                          <li key={part.label} className={part.ok ? "" : "is-missing"}>
                            <span>{part.label}</span>
                            <span>{part.value}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  );
                })}
              </div>
            )}
          </section>
        </div>
      </main>
    </div>
  );
}
