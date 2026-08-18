import { MouseEvent, useState } from "react";
import { playWord } from "../lib/speech";

/**
 * Speaker control next to a German word. Deliberately not used inside
 * exercises: hearing the word there would turn a question into a hint.
 */
export default function WordAudioButton({
  word,
  audioUrl,
  size = "md",
  title = "Прослушать произношение",
}: {
  word: string;
  audioUrl?: string;
  size?: "sm" | "md";
  title?: string;
}) {
  const [playing, setPlaying] = useState(false);

  const handleClick = async (e: MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setPlaying(true);
    try {
      await playWord(word, audioUrl);
    } finally {
      setTimeout(() => setPlaying(false), 600);
    }
  };

  return (
    <button
      type="button"
      className={`word-audio word-audio--${size} ${playing ? "is-playing" : ""}`}
      onClick={handleClick}
      title={title}
      aria-label={`${title}: ${word}`}
    >
      🔊
    </button>
  );
}
