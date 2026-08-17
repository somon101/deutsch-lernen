import ExerciseRunner from "../../components/practice/ExerciseRunner";
import { Exercise } from "../../content/exercises";
import { useProgressStore } from "../../progress/ProgressContext";

export default function ReviewStage({
  lessonId,
  exercises,
  onComplete,
}: {
  lessonId: string;
  exercises: Exercise[];
  onComplete: () => void;
}) {
  const { recordQuizResult } = useProgressStore();

  return (
    <div className="stage-panel">
      <div className="stage-eyebrow">Закрепление</div>
      <h1 className="stage-title">Финальная проверка по всем словам урока</h1>
      <p className="stage-subtitle">Быстро пройдитесь по каждому слову урока, чтобы закрепить его в памяти.</p>
      <ExerciseRunner
        exercises={exercises}
        onFinish={(score) => {
          recordQuizResult(lessonId, "reviewResult", { ...score, completedAt: new Date().toISOString() });
          onComplete();
        }}
      />
    </div>
  );
}
