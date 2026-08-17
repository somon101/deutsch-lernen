import { useState } from "react";
import { TrueFalseQuestion } from "../../content/exercises";

export default function TrueFalseView({
  exercise,
  onAnswered,
}: {
  exercise: TrueFalseQuestion;
  onAnswered: (correct: boolean) => void;
}) {
  const [answer, setAnswer] = useState<boolean | null>(null);

  const select = (value: boolean) => {
    if (answer !== null) return;
    setAnswer(value);
    onAnswered(value === exercise.correct);
  };

  const cls = (value: boolean) => {
    let base = "quiz-option";
    if (answer === null) return base;
    if (value === exercise.correct) return `${base} correct`;
    if (value === answer) return `${base} incorrect`;
    return base;
  };

  return (
    <>
      <p className="exercise-prompt">{exercise.statement}</p>
      <div className="truefalse-row">
        <button className={cls(true)} disabled={answer !== null} onClick={() => select(true)}>
          Верно
        </button>
        <button className={cls(false)} disabled={answer !== null} onClick={() => select(false)}>
          Неверно
        </button>
      </div>
      {answer !== null && (
        <div className={`exercise-feedback ${answer === exercise.correct ? "correct" : "incorrect"}`}>
          {answer === exercise.correct ? "Верно! " : "Неверно. "}
          {exercise.explanation}
        </div>
      )}
    </>
  );
}
