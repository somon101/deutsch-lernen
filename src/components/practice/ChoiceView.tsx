import { useState } from "react";
import { ChoiceQuestion } from "../../content/exercises";
import { shuffle } from "../../content/textUtils";

export default function ChoiceView({
  exercise,
  onAnswered,
}: {
  exercise: ChoiceQuestion;
  onAnswered: (correct: boolean) => void;
}) {
  // Re-shuffled every time this question is mounted (i.e. every attempt),
  // so the correct answer's on-screen position isn't memorizable. Correctness
  // is checked by value below, never by position.
  const [options] = useState(() => shuffle(exercise.options, Math.random));
  const [selected, setSelected] = useState<string | null>(null);

  const select = (option: string) => {
    if (selected !== null) return;
    setSelected(option);
    onAnswered(option === exercise.correctAnswer);
  };

  return (
    <>
      <p className="exercise-prompt">{exercise.prompt}</p>
      <div className="quiz-options">
        {options.map((option, i) => {
          let cls = "quiz-option";
          if (selected !== null) {
            if (option === exercise.correctAnswer) cls += " correct";
            else if (option === selected) cls += " incorrect";
          }
          return (
            <button key={i} className={cls} disabled={selected !== null} onClick={() => select(option)}>
              {option}
            </button>
          );
        })}
      </div>
      {selected !== null && (
        <div className={`exercise-feedback ${selected === exercise.correctAnswer ? "correct" : "incorrect"}`}>
          {selected === exercise.correctAnswer ? "Верно!" : `Неверно. Правильный ответ: «${exercise.correctAnswer}».`}
        </div>
      )}
    </>
  );
}
