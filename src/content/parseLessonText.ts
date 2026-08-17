import { LessonBlock, PhraseEntry } from "./types";
import {
  extractBracketPronunciation,
  leadingEmoji,
  looksLikeContinuation,
  stripLeadingEmoji,
} from "./textUtils";

const STEP_RE = /^Шаг\s+(\d+)\.\s*(.*)$/u;
const DASH_SPLIT = " — ";

/**
 * Turns the raw lesson-text export into a sequence of typed blocks for
 * rendering. The source file wraps sentences across many short lines, so
 * every line is kept exactly as written and only *classified* (title, step
 * heading, sub-heading, vocabulary-style phrase, or plain line) — nothing is
 * reworded, merged or reordered.
 */
export function parseLessonText(raw: string): {
  blocks: LessonBlock[];
  phrases: PhraseEntry[];
} {
  const lines = raw
    .split(/\r\n|\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const blocks: LessonBlock[] = [];
  const phrases: PhraseEntry[] = [];
  const seenPhrases = new Set<string>();
  let phraseIndex = 0;

  lines.forEach((line, i) => {
    if (i === 0) {
      blocks.push({ type: "title", text: line });
      return;
    }

    const stepMatch = line.match(STEP_RE);
    if (stepMatch) {
      blocks.push({ type: "step", number: Number(stepMatch[1]), title: stepMatch[2] });
      return;
    }

    if (line.includes(DASH_SPLIT)) {
      const dashIndex = line.indexOf(DASH_SPLIT);
      const leftRaw = line.slice(0, dashIndex);
      const translation = line.slice(dashIndex + DASH_SPLIT.length).trim();
      const icon = leadingEmoji(leftRaw);
      const withoutIcon = icon ? stripLeadingEmoji(leftRaw) : leftRaw.trim();
      const { text: german, pronunciation } = extractBracketPronunciation(withoutIcon);

      blocks.push({ type: "phrase", icon, german, pronunciation, translation });

      const key = `${german}::${translation}`;
      if (german && translation && !seenPhrases.has(key)) {
        seenPhrases.add(key);
        phrases.push({
          id: `phrase-${phraseIndex++}`,
          german,
          pronunciation,
          translation,
        });
      }
      return;
    }

    const icon = leadingEmoji(line);
    if (icon) {
      blocks.push({ type: "subheading", icon, text: stripLeadingEmoji(line) });
      return;
    }

    blocks.push({ type: "line", text: line, tight: looksLikeContinuation(line) });
  });

  return { blocks, phrases };
}
