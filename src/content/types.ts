// Content model. Everything here is derived from files inside lessonN/ folders —
// nothing in this file describes actual lesson content, only its shape.

export interface VocabularyEntry {
  id: string;
  german: string;
  translation: string;
  pronunciation?: string;
}

/** A single line from the lesson text file, classified for display. Lines are
 * never merged or reworded — each block maps 1:1 to a line in the source file. */
export type LessonBlock =
  | { type: "title"; text: string }
  | { type: "step"; number: number; title: string }
  | { type: "subheading"; icon?: string; text: string }
  | {
      type: "phrase";
      icon?: string;
      german: string;
      pronunciation?: string;
      translation: string;
    }
  | { type: "line"; text: string; tight?: boolean };

export interface PhraseEntry {
  id: string;
  german: string;
  pronunciation?: string;
  translation: string;
}

export interface LessonAsset {
  url: string;
  name: string;
}

/** A question written by an admin, stored in the database. */
export interface AuthoredQuestion {
  setName: "minitest" | "practice" | "review";
  prompt: string;
  options: string[];
  /** Identified by value, not position, so reordering options is safe. */
  correctAnswer: string;
}

export interface LessonAssets {
  video?: LessonAsset;
  audio?: LessonAsset;
  images: LessonAsset[];
}

export interface LessonContent {
  id: string;
  title: string;
  vocabulary: VocabularyEntry[];
  material: LessonBlock[];
  /** Full sentences/phrases mined from the lesson text, used to build practice
   * exercises (sentence scramble, cloze) in addition to the vocabulary list. */
  phrases: PhraseEntry[];
  assets: LessonAssets;
  /** Text files found in the lesson folder that didn't match a known role —
   * surfaced to the user instead of silently discarded. */
  extraTextFiles: { name: string; content: string }[];
  /** Human-readable notes about resources the lesson structure expects but
   * that were not found (e.g. no video file present). */
  missing: string[];
  /** The raw lesson text `material` was parsed from — the file's contents, or
   * the admin's edited version when one has been saved. */
  materialText: string;
  /** Questions authored in the admin panel. Empty means the exercise
   * generator keeps producing them exactly as it did before. */
  authoredQuestions: AuthoredQuestion[];
  /** True when an admin has saved edits for this lesson. */
  hasContentOverrides: boolean;
}
