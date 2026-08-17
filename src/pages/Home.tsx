import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { listLessonIds, loadLesson } from "../content/loader";
import { LessonContent } from "../content/types";
import { useProgressStore } from "../progress/ProgressContext";
import { courseProgressRatio, nextIncompleteStage } from "../progress/types";

export default function Home() {
  const [lessons, setLessons] = useState<LessonContent[] | null>(null);
  const { store } = useProgressStore();

  useEffect(() => {
    const ids = listLessonIds();
    Promise.all(ids.map((id) => loadLesson(id))).then(setLessons);
  }, []);

  return (
    <div className="app-shell">
      <nav className="top-nav">
        <Link to="/" className="brand">
          <span className="brand-flag">🇩🇪</span> Deutsch Lernen
        </Link>
      </nav>
      <main className="home-main">
        <div className="home-hero">
          <h1>Изучайте немецкий шаг за шагом</h1>
          <p>Слова → Материал → Видео → Мини-тест → Аудио → Практика → Закрепление</p>
        </div>

        {lessons === null && (
          <p style={{ textAlign: "center", color: "var(--color-text-muted)" }}>Загрузка уроков…</p>
        )}

        {lessons !== null && lessons.length === 0 && (
          <div className="empty-state">
            <h3>Уроки не найдены</h3>
            <p>Добавьте папку lesson1 (а затем lesson2, lesson3…) с материалами урока в корень проекта.</p>
          </div>
        )}

        {lessons !== null && lessons.length > 0 && (
          <div className="lesson-grid">
            {lessons.map((lesson, i) => {
              const progress = store[lesson.id];
              const ratio = courseProgressRatio(progress);
              const completed = progress?.completedStages.includes("complete");
              const target = progress ? nextIncompleteStage(progress) : "vocabulary";
              const displayTitle = lesson.title.replace(/^\p{Extended_Pictographic}\s*/u, "");

              return (
                <Link key={lesson.id} to={`/lesson/${lesson.id}/${target}`} className="lesson-card">
                  <span className="lesson-card__badge">{i + 1}</span>
                  <span className="lesson-card__title">{displayTitle}</span>
                  <span className="lesson-card__meta">
                    {lesson.vocabulary.length} слов{lesson.missing.length > 0 ? " · часть материалов отсутствует" : ""}
                  </span>
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
      </main>
    </div>
  );
}
