import { LessonBlock, PhraseEntry } from "./types";
import {
  extractBracketPronunciation,
  leadingEmoji,
  looksLikeContinuation,
  normalizeAnswer,
  stripLeadingEmoji,
} from "./textUtils";

const STEP_RE = /^Шаг\s+(\d+)\.\s*(.*)$/u;
const DASH_SPLIT = " — ";

// Lesson files may be written either as plain text (lesson 1) or in Markdown
// (lesson 2). These patterns normalise the Markdown flavour into the same
// shapes the plain format already produced, so both render identically.
const HORIZONTAL_RULE = /^\s*([-*_])\1{2,}\s*$/;
const TABLE_SEPARATOR = /^\s*\|?[\s:|-]*-{2,}[\s:|-]*\|?\s*$/;
const TABLE_ROW = /^\s*\|(.+)\|\s*$/;
const HEADING = /^(#{1,6})\s+(.*)$/;
const NUMBERED_HEADING = /^(\d+)\.\s*(.+)$/;

function stripEmphasis(text: string): string {
  return text
    .replace(/\*\*(.+?)\*\*/g, "$1")
    .replace(/__(.+?)__/g, "$1")
    .replace(/(^|\s)\*(\S(?:.*?\S)?)\*(?=\s|$)/g, "$1$2");
}

function tableCells(line: string): string[] {
  const match = line.match(TABLE_ROW);
  if (!match) return [];
  return match[1]
    .split("|")
    .map((cell) => cell.trim())
    .filter((cell) => cell.length > 0);
}

/**
 * Turns the raw lesson text into a sequence of typed blocks for rendering.
 * Wording is never changed — lines are only classified (title, step heading,
 * sub-heading, phrase, or plain line) and Markdown markers are removed.
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
  let titleTaken = false;

  const pushPhrase = (icon: string | undefined, left: string, translation: string) => {
    const { text: german, pronunciation } = extractBracketPronunciation(left);
    blocks.push({ type: "phrase", icon, german, pronunciation, translation });

    // Keyed by normalized text (case/punctuation-insensitive) rather than the
    // raw string, so "Hallo! — Привет!" and a later "Hallo — привет" collapse
    // into one practice-pool entry instead of feeding the exercise generator
    // two options that only differ formally. The displayed card above still
    // shows the raw text exactly as written.
    const key = `${normalizeAnswer(german)}::${normalizeAnswer(translation)}`;
    if (german && translation && !seenPhrases.has(key)) {
      seenPhrases.add(key);
      phrases.push({ id: `phrase-${phraseIndex++}`, german, pronunciation, translation });
    }
  };

  lines.forEach((rawLine, i) => {
    // Structural Markdown noise carries no lesson content.
    if (HORIZONTAL_RULE.test(rawLine) || TABLE_SEPARATOR.test(rawLine)) return;

    const cells = tableCells(rawLine);
    if (cells.length > 0) {
      // The row above a separator is the table's header, not a word pair.
      const nextLine = lines[i + 1];
      const isHeader = nextLine !== undefined && TABLE_SEPARATOR.test(nextLine);
      if (isHeader) {
        blocks.push({ type: "subheading", text: stripEmphasis(cells.join(" · ")) });
        return;
      }
      if (cells.length >= 2) {
        pushPhrase(undefined, stripEmphasis(cells[0]), stripEmphasis(cells.slice(1).join(" ")));
        return;
      }
      blocks.push({ type: "line", text: stripEmphasis(cells[0]) });
      return;
    }

    const headingMatch = rawLine.match(HEADING);
    const line = stripEmphasis(headingMatch ? headingMatch[2].trim() : rawLine);
    if (!line) return;

    if (!titleTaken) {
      titleTaken = true;
      blocks.push({ type: "title", text: line });
      return;
    }

    if (headingMatch) {
      const numbered = line.match(NUMBERED_HEADING);
      if (headingMatch[1].length === 1 && numbered) {
        blocks.push({ type: "step", number: Number(numbered[1]), title: numbered[2] });
        return;
      }
      const icon = leadingEmoji(line);
      blocks.push({ type: "subheading", icon, text: icon ? stripLeadingEmoji(line) : line });
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
      pushPhrase(icon, icon ? stripLeadingEmoji(leftRaw) : leftRaw.trim(), translation);
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
