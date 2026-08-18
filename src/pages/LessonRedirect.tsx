import { Navigate, useParams } from "react-router-dom";
import { useLessonProgress, useProgressStore } from "../progress/ProgressContext";
import { nextIncompleteStage } from "../progress/types";

export default function LessonRedirect() {
  const { lessonId = "" } = useParams();
  const progress = useLessonProgress(lessonId);
  const { isLoaded } = useProgressStore();

  // Wait for the server-side progress before deciding which stage to resume at.
  if (!isLoaded) {
    return (
      <div className="app-shell">
        <main className="home-main">
          <p style={{ textAlign: "center", color: "var(--color-text-muted)" }}>Загружаем ваш прогресс…</p>
        </main>
      </div>
    );
  }

  return <Navigate to={`/lesson/${lessonId}/${nextIncompleteStage(progress)}`} replace />;
}
