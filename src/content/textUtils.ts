// Small text/randomization helpers shared by the content parsers and exercise
// generators. No lesson-specific knowledge lives here.

/** True if a leading pictographic symbol (emoji) starts the string. */
const LEADING_EMOJI = /^\p{Extended_Pictographic}(️)?/u;

export function leadingEmoji(text: string): string | undefined {
  const match = text.match(LEADING_EMOJI);
  return match ? match[0] : undefined;
}

export function stripLeadingEmoji(text: string): string {
  return text.replace(LEADING_EMOJI, "").trim();
}

/** A line that starts with a lowercase letter or a "hanging" punctuation mark
 * is very likely the tail end of the previous line rather than a new
 * thought — used only for tightening vertical spacing, never for merging text. */
const CONTINUATION_START = /^[.,:;!)/–—]|^\p{Ll}/u;

export function looksLikeContinuation(text: string): boolean {
  return CONTINUATION_START.test(text);
}

export function extractBracketPronunciation(
  text: string,
): { text: string; pronunciation?: string } {
  const match = text.match(/\[([^\]]+)\]/);
  if (!match) return { text: text.trim() };
  return {
    text: text.replace(match[0], "").replace(/\s+/g, " ").trim(),
    pronunciation: match[1].trim(),
  };
}

/** Deterministic PRNG (mulberry32) so exercise shuffling is stable across
 * reloads of the same lesson instead of re-randomizing on every render. */
export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function hashString(input: string): number {
  let hash = 2166136261;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

export function shuffle<T>(items: T[], rand: () => number): T[] {
  const copy = items.slice();
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

export function pickN<T>(items: T[], n: number, rand: () => number): T[] {
  return shuffle(items, rand).slice(0, Math.min(n, items.length));
}

/**
 * Normalizes an answer for comparison: case, surrounding whitespace and
 * incidental punctuation are ignored, so "Hallo", "hallo" and "Hallo!" all
 * count as the same answer. Letters — umlauts included — are left untouched,
 * so a genuinely different word still compares as different.
 */
export function normalizeAnswer(value: string): string {
  return value
    .toLowerCase()
    .replace(/[.,!?;:…"'«»„“”()]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** True when two answers match under {@link normalizeAnswer}. */
export function answersMatch(a: string, b: string): boolean {
  return normalizeAnswer(a) === normalizeAnswer(b);
}
