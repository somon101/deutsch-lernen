import { useState } from "react";
import { ScrambleExercise } from "../../content/exercises";

interface Token {
  key: string;
  word: string;
}

export default function ScrambleView({
  exercise,
  onAnswered,
}: {
  exercise: ScrambleExercise;
  onAnswered: (correct: boolean) => void;
}) {
  const [bank, setBank] = useState<Token[]>(() => exercise.tokens.map((word, i) => ({ key: `${i}-${word}`, word })));
  const [placed, setPlaced] = useState<Token[]>([]);
  const [checked, setChecked] = useState(false);
  const [correct, setCorrect] = useState(false);

  const place = (token: Token) => {
    if (checked) return;
    setBank((b) => b.filter((t) => t.key !== token.key));
    setPlaced((p) => [...p, token]);
  };

  const unplace = (token: Token) => {
    if (checked) return;
    setPlaced((p) => p.filter((t) => t.key !== token.key));
    setBank((b) => [...b, token]);
  };

  const check = () => {
    const isCorrect = placed.map((t) => t.word).join(" ") === exercise.answer.join(" ");
    setChecked(true);
    setCorrect(isCorrect);
    onAnswered(isCorrect);
  };

  return (
    <>
      <p className="stage-subtitle">Соберите фразу по переводу: «{exercise.translation}»</p>

      <div className="scramble-answer">
        {placed.map((t) => (
          <button key={t.key} className="token-chip placed" onClick={() => unplace(t)} disabled={checked}>
            {t.word}
          </button>
        ))}
      </div>

      <div className="scramble-bank">
        {bank.map((t) => (
          <button key={t.key} className="token-chip" onClick={() => place(t)} disabled={checked}>
            {t.word}
          </button>
        ))}
      </div>

      {!checked && (
        <div className="stage-footer">
          <button className="btn btn-secondary" onClick={check} disabled={placed.length !== exercise.answer.length}>
            Проверить
          </button>
        </div>
      )}

      {checked && (
        <div className={`exercise-feedback ${correct ? "correct" : "incorrect"}`}>
          {correct ? "Верно!" : `Неверно. Правильно: «${exercise.answer.join(" ")}».`}
        </div>
      )}
    </>
  );
}
