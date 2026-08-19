import { Fragment } from "react";
import { useNavigate } from "react-router-dom";
import { LessonProgress, STAGE_LABELS, STAGE_ORDER, StageId, isStageUnlocked } from "../progress/types";

export default function Stepper({
  lessonId,
  currentStage,
  progress,
  stagePath = (stage) => `/lesson/${lessonId}/${stage}`,
}: {
  lessonId: string;
  currentStage: StageId;
  progress: LessonProgress;
  stagePath?: (stage: StageId) => string;
}) {
  const navigate = useNavigate();
  const visibleStages = STAGE_ORDER.filter((s) => s !== "complete");

  return (
    <div className="stepper">
      {visibleStages.map((stage, i) => {
        const done = progress.completedStages.includes(stage);
        const current = stage === currentStage;
        const unlocked = isStageUnlocked(progress, stage);
        const clickable = unlocked && (done || current);

        return (
          <Fragment key={stage}>
            <div className={`stepper__item ${done ? "done" : ""} ${current ? "current" : ""}`}>
              <button
                type="button"
                className={`stepper__dot-wrap ${clickable ? "clickable" : ""}`}
                disabled={!clickable}
                onClick={() => clickable && navigate(stagePath(stage))}
                title={STAGE_LABELS[stage]}
              >
                <span className="stepper__dot">{done ? "✓" : i + 1}</span>
                <span className="stepper__label">{STAGE_LABELS[stage]}</span>
              </button>
            </div>
            {i < visibleStages.length - 1 && <div className="stepper__connector" />}
          </Fragment>
        );
      })}
    </div>
  );
}
