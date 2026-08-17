import { useEffect, useRef, useState } from "react";
import { Exercise } from "../../content/exercises";
import ChoiceView from "./ChoiceView";
import TrueFalseView from "./TrueFalseView";
import MatchView from "./MatchView";
import ScrambleView from "./ScrambleView";
import ClozeView from "./ClozeView";
import { playSound } from "../../lib/sound";
import correctSoundUrl from "../../../sounds/correct-answer.mp3";
import incorrectSoundUrl from "../../../sounds/incorrect-answer.mp3";

interface Props {
  exercises: Exercise[];
  onFinish: (score: { correct: number; total: number }) => void;
}

function isEditableTarget(target: EventTarget | null): boolean {
  const el = target as HTMLElement | null;
  if (!el) return false;
  const tag = el.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
}

function exercisePrompt(exercise: Exercise): string {
  switch (exercise.kind) {
    case "choice":
      return exercise.prompt;
    case "truefalse":
      return exercise.statement;
    case "match":
      return "Сопоставление слов и переводов";
    case "scramble":
      return `Фраза по переводу «${exercise.translation}»`;
    case "cloze":
      return `Пропуск во фразе «${exercise.translation}»`;
  }
}

function exerciseKindLabel(exercise: Exercise): string {
  switch (exercise.kind) {
    case "choice":
      return "Выбор ответа";
    case "truefalse":
      return "Верно или неверно";
    case "match":
      return "Сопоставление";
    case "scramble":
      return "Собери фразу";
    case "cloze":
      return "Заполни пропуск";
  }
}

function correctAnswerLabel(exercise: Exercise): string {
  switch (exercise.kind) {
    case "choice":
      return `Правильный ответ: «${exercise.correctAnswer}»`;
    case "truefalse":
      return exercise.explanation;
    case "match":
      return "Не все пары были сопоставлены с первой попытки";
    case "scramble":
      return `Правильно: «${exercise.answer.join(" ")}»`;
    case "cloze":
      return `Правильное слово: «${exercise.answer}»`;
  }
}

export default function ExerciseRunner({ exercises, onFinish }: Props) {
  const [index, setIndex] = useState(0);
  const [answered, setAnswered] = useState(false);
  const [finished, setFinished] = useState(false);
  const [celebrate, setCelebrate] = useState(false);
  const [score, setScore] = useState({ correct: 0, total: exercises.length });
  const resultsRef = useRef<{ correct: boolean }[]>([]);

  const handleAnswered = (correct: boolean) => {
    resultsRef.current[index] = { correct };
    setScore((s) => ({ ...s, correct: s.correct + (correct ? 1 : 0) }));
    setAnswered(true);

    if (correct) {
      playSound(correctSoundUrl);
      setCelebrate(true);
      setTimeout(() => setCelebrate(false), 650);
    } else {
      playSound(incorrectSoundUrl);
    }
  };

  const handleNext = () => {
    if (index + 1 < exercises.length) {
      setIndex((i) => i + 1);
      setAnswered(false);
    } else {
      setFinished(true);
    }
  };

  // Enter repeats whatever "Continue" would do, once an answer has been
  // given (or the results screen is showing) — but never inside a field
  // where Enter has its own meaning.
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key !== "Enter" || isEditableTarget(e.target)) return;
      if (finished) {
        e.preventDefault();
        onFinish(score);
      } else if (answered) {
        e.preventDefault();
        handleNext();
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  });

  if (exercises.length === 0) {
    return (
      <div className="exercise-card">
        <p className="stage-subtitle">Недостаточно материала для этого блока — переходим дальше.</p>
        <div className="stage-footer">
          <button className="btn btn-primary" onClick={() => onFinish({ correct: 0, total: 0 })}>
            Далее
          </button>
        </div>
      </div>
    );
  }

  const current = exercises[index];

  if (finished) {
    const mistakes = resultsRef.current
      .map((r, i) => ({ ...r, exercise: exercises[i] }))
      .filter((r) => !r.correct);

    return (
      <div className="result-card">
        <div className="stage-eyebrow">Результат</div>
        <div className="result-score">
          {score.correct} / {score.total}
        </div>
        <p className="stage-subtitle">
          {score.correct === score.total ? "Отлично, всё верно!" : "Хороший результат. Разберём ошибки ниже."}
        </p>
        {mistakes.length > 0 && (
          <div className="mistake-list">
            {mistakes.map((m, i) => (
              <div className="mistake-item" key={i}>
                {exercisePrompt(m.exercise)} — {correctAnswerLabel(m.exercise)}
              </div>
            ))}
          </div>
        )}
        <button className="btn btn-primary" style={{ position: "sticky", bottom: 16 }} onClick={() => onFinish(score)}>
          Продолжить (Enter)
        </button>
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
      <div>
        <div className="quiz-progress-row">
          <span>
            Задание {index + 1} из {exercises.length}
          </span>
          <span>{score.correct} правильно</span>
        </div>
        <div className="quiz-progress-bar" style={{ marginTop: 6 }}>
          <div className="quiz-progress-bar-fill" style={{ width: `${(index / exercises.length) * 100}%` }} />
        </div>
      </div>

      <div className={`exercise-card ${celebrate ? "celebrate" : ""}`}>
        <div className="exercise-kind">{exerciseKindLabel(current)}</div>
        {current.kind === "choice" && <ChoiceView key={current.id} exercise={current} onAnswered={handleAnswered} />}
        {current.kind === "truefalse" && (
          <TrueFalseView key={current.id} exercise={current} onAnswered={handleAnswered} />
        )}
        {current.kind === "match" && <MatchView key={current.id} exercise={current} onAnswered={handleAnswered} />}
        {current.kind === "scramble" && (
          <ScrambleView key={current.id} exercise={current} onAnswered={handleAnswered} />
        )}
        {current.kind === "cloze" && <ClozeView key={current.id} exercise={current} onAnswered={handleAnswered} />}
      </div>

      {answered && (
        <div className="exercise-continue-bar">
          <button className="btn btn-primary" onClick={handleNext}>
            {index + 1 < exercises.length ? "Следующее (Enter)" : "Завершить (Enter)"}
          </button>
        </div>
      )}
    </div>
  );
}
