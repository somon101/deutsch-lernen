import { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useLessonProgress } from "../progress/ProgressContext";
import { StageId } from "../progress/types";
import Stepper from "./Stepper";

export default function LessonLayout({
  lessonId,
  lessonTitle,
  currentStage,
  children,
}: {
  lessonId: string;
  lessonTitle: string;
  currentStage: StageId;
  children: ReactNode;
}) {
  const progress = useLessonProgress(lessonId);

  return (
    <div className="lesson-layout">
      <header className="lesson-header">
        <div className="lesson-header__row">
          <span className="lesson-header__title">{lessonTitle}</span>
          <Link to="/" className="lesson-header__exit">
            ✕ Выйти из урока
          </Link>
        </div>
        <Stepper lessonId={lessonId} currentStage={currentStage} progress={progress} />
      </header>
      <div className="stage-scroll">{children}</div>
    </div>
  );
}
