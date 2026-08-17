import { useEffect, useMemo, useRef, useState } from "react";
import { MatchExercise } from "../../content/exercises";
import { hashString, seededRandom, shuffle } from "../../content/textUtils";
import { playSound } from "../../lib/sound";
import correctSoundUrl from "../../../sounds/correct-answer.mp3";
import incorrectSoundUrl from "../../../sounds/incorrect-answer.mp3";

export default function MatchView({
  exercise,
  onAnswered,
}: {
  exercise: MatchExercise;
  onAnswered: (correct: boolean) => void;
}) {
  const leftItems = useMemo(
    () => shuffle(exercise.pairs, seededRandom(hashString(exercise.id + "-left"))),
    [exercise],
  );
  const rightItems = useMemo(
    () => shuffle(exercise.pairs, seededRandom(hashString(exercise.id + "-right"))),
    [exercise],
  );

  const [matched, setMatched] = useState<Set<string>>(new Set());
  const [selectedLeft, setSelectedLeft] = useState<string | null>(null);
  const [selectedRight, setSelectedRight] = useState<string | null>(null);
  // Tracks the two specific cards involved in the current wrong attempt —
  // one id can appear on both sides of the board (same pair, left + right
  // card), so left/right are kept separate to avoid highlighting a card
  // that wasn't actually clicked just because it shares a pair id.
  const [wrongPair, setWrongPair] = useState<{ left: string; right: string } | null>(null);
  const wrongAttempts = useRef(0);
  const finishedRef = useRef(false);

  useEffect(() => {
    if (matched.size === exercise.pairs.length && !finishedRef.current) {
      finishedRef.current = true;
      const timeout = setTimeout(() => onAnswered(wrongAttempts.current === 0), 300);
      return () => clearTimeout(timeout);
    }
  }, [matched, exercise.pairs.length, onAnswered]);

  const attempt = (leftId: string | null, rightId: string | null) => {
    if (!leftId || !rightId) return;
    if (leftId === rightId) {
      setMatched((prev) => new Set(prev).add(leftId));
      setSelectedLeft(null);
      setSelectedRight(null);
      playSound(correctSoundUrl);
    } else {
      wrongAttempts.current += 1;
      setWrongPair({ left: leftId, right: rightId });
      playSound(incorrectSoundUrl);
      setTimeout(() => {
        setWrongPair(null);
        setSelectedLeft(null);
        setSelectedRight(null);
      }, 500);
    }
  };

  const pickLeft = (id: string) => {
    if (matched.has(id) || wrongPair) return;
    setSelectedLeft(id);
    attempt(id, selectedRight);
  };

  const pickRight = (id: string) => {
    if (matched.has(id) || wrongPair) return;
    setSelectedRight(id);
    attempt(selectedLeft, id);
  };

  const classForLeft = (id: string) => {
    let cls = "match-item";
    if (matched.has(id)) cls += " matched";
    else if (wrongPair?.left === id) cls += " wrong";
    else if (selectedLeft === id) cls += " selected";
    return cls;
  };

  const classForRight = (id: string) => {
    let cls = "match-item";
    if (matched.has(id)) cls += " matched";
    else if (wrongPair?.right === id) cls += " wrong";
    else if (selectedRight === id) cls += " selected";
    return cls;
  };

  return (
    <>
      <p className="exercise-prompt">Сопоставьте немецкие слова с переводом</p>
      <div className="match-columns">
        <div className="match-column">
          {leftItems.map((pair) => (
            <button
              key={pair.id}
              className={classForLeft(pair.id)}
              onClick={() => pickLeft(pair.id)}
              disabled={matched.has(pair.id)}
            >
              {pair.left}
            </button>
          ))}
        </div>
        <div className="match-column">
          {rightItems.map((pair) => (
            <button
              key={pair.id}
              className={classForRight(pair.id)}
              onClick={() => pickRight(pair.id)}
              disabled={matched.has(pair.id)}
            >
              {pair.right}
            </button>
          ))}
        </div>
      </div>
      <div className="exercise-feedback correct" style={{ opacity: matched.size === exercise.pairs.length ? 1 : 0.5 }}>
        Сопоставлено: {matched.size} / {exercise.pairs.length}
      </div>
    </>
  );
}
