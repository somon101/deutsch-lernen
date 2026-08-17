import { useState } from "react";
import { ClozeExercise } from "../../content/exercises";
import { shuffle } from "../../content/textUtils";

export default function ClozeView({
  exercise,
  onAnswered,
}: {
  exercise: ClozeExercise;
  onAnswered: (correct: boolean) => void;
}) {
  // Re-shuffled every time this question is mounted (i.e. every attempt),
  // so the correct word's on-screen position isn't memorizable.
  const [options] = useState(() => shuffle(exercise.options, Math.random));
  const [selected, setSelected] = useState<string | null>(null);

  const select = (option: string) => {
    if (selected !== null) return;
    setSelected(option);
    onAnswered(option === exercise.answer);
  };

  return (
    <>
      <p className="stage-subtitle">Перевод: «{exercise.translation}»</p>
      <p className="cloze-sentence">
        {exercise.before} <span className="cloze-blank">{selected ?? "…"}</span> {exercise.after}
      </p>
      <div className="quiz-options">
        {options.map((option, i) => {
          let cls = "quiz-option";
          if (selected !== null) {
            if (option === exercise.answer) cls += " correct";
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
        <div className={`exercise-feedback ${selected === exercise.answer ? "correct" : "incorrect"}`}>
          {selected === exercise.answer ? "Верно!" : `Неверно. Правильное слово: «${exercise.answer}».`}
        </div>
      )}
    </>
  );
}
