import { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useLessonProgress } from "../progress/ProgressContext";
import { StageId } from "../progress/types";
import Stepper from "./Stepper";

export default function LessonLayout({
  lessonId,
  lessonTitle,
  currentStage,
  exitTo = "/",
  stagePath,
  breadcrumb,
  children,
}: {
  lessonId: string;
  lessonTitle: string;
  currentStage: StageId;
  /** Where "Выйти из урока" goes — the legacy course's lesson list by
   * default; a builder course passes its own lesson-list path here. */
  exitTo?: string;
  /** Where each stepper dot navigates to — defaults to the legacy course's
   * URL shape so its own call site needs no changes. */
  stagePath?: (stage: StageId) => string;
  /** Optional breadcrumb trail above the header, e.g. "Курсы / Курс / Урок /
   * Этап" — only builder-course lessons pass this, so the legacy course's
   * lesson view is pixel-identical to before. */
  breadcrumb?: ReactNode;
  children: ReactNode;
}) {
  const progress = useLessonProgress(lessonId);

  return (
    <div className="lesson-layout">
      <header className="lesson-header">
        {breadcrumb}
        <div className="lesson-header__row">
          <span className="lesson-header__title">{lessonTitle}</span>
          <Link to={exitTo} className="lesson-header__exit">
            ✕ Выйти из урока
          </Link>
        </div>
        <Stepper lessonId={lessonId} currentStage={currentStage} progress={progress} stagePath={stagePath} />
      </header>
      <div className="stage-scroll">{children}</div>
    </div>
  );
}
