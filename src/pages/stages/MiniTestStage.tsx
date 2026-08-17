import ExerciseRunner from "../../components/practice/ExerciseRunner";
import { Exercise } from "../../content/exercises";
import { useProgressStore } from "../../progress/ProgressContext";

export default function MiniTestStage({
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
      <div className="stage-eyebrow">Мини-тест</div>
      <h1 className="stage-title">Проверьте понимание видео</h1>
      <p className="stage-subtitle">Несколько вопросов по словам и фразам урока, которые прозвучали в видео.</p>
      <ExerciseRunner
        exercises={exercises}
        onFinish={(score) => {
          recordQuizResult(lessonId, "miniTestResult", { ...score, completedAt: new Date().toISOString() });
          onComplete();
        }}
      />
    </div>
  );
}
