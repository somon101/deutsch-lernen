import { VocabularyEntry } from "./types";

/**
 * Parses a vocabulary file laid out as repeating groups of lines:
 *   German word
 *   Russian translation
 *   [pronunciation]   (optional — only consumed if present)
 *
 * Resilient to entries missing a pronunciation line, so it keeps working if a
 * future lesson's словарь file doesn't include one for every word.
 */
export function parseVocabulary(raw: string, lessonId: string): VocabularyEntry[] {
  const lines = raw
    .split(/\r\n|\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const entries: VocabularyEntry[] = [];
  let i = 0;
  let index = 0;

  while (i < lines.length) {
    const german = lines[i++];
    if (i >= lines.length) break; // dangling word with no translation — drop it
    const translation = lines[i++];

    let pronunciation: string | undefined;
    const next = lines[i];
    if (next && /^\[.*\]$/.test(next)) {
      pronunciation = next.slice(1, -1).trim();
      i++;
    }

    entries.push({
      id: `${lessonId}-vocab-${index++}`,
      german,
      translation,
      pronunciation,
    });
  }

  return entries;
}
