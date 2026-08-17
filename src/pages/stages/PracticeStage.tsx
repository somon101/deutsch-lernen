import ExerciseRunner from "../../components/practice/ExerciseRunner";
import { Exercise } from "../../content/exercises";
import { useProgressStore } from "../../progress/ProgressContext";

export default function PracticeStage({
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
      <div className="stage-eyebrow">Практика</div>
      <h1 className="stage-title">Отработайте слова и фразы урока</h1>
      <p className="stage-subtitle">
        Разные типы заданий: перевод, пропуски, сборка фраз, сопоставление. Практикуйтесь до конца блока.
      </p>
      <ExerciseRunner
        exercises={exercises}
        onFinish={(score) => {
          recordQuizResult(lessonId, "practiceResult", { ...score, completedAt: new Date().toISOString() });
          onComplete();
        }}
      />
    </div>
  );
}
