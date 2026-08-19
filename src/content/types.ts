// Content model. Everything here is derived from files inside lessonN/ folders —
// nothing in this file describes actual lesson content, only its shape.

import { BuilderBlock } from "../admin/builderApi";

export interface VocabularyEntry {
  id: string;
  german: string;
  translation: string;
  pronunciation?: string;
  /** Recorded pronunciation uploaded by an admin, if there is one. */
  audioUrl?: string;
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
  /** Same list as `vocabulary`, minus any word already taught as a new word
   * in an earlier lesson of the same course (compared case/punctuation-
   * insensitively). Drives the "learn new words" stage only — everything
   * else (material, phrase pool for exercises, audio lookups) keeps using
   * the full `vocabulary` above, since a word already learned can still
   * legitimately appear in later material or tests. */
  newVocabulary: VocabularyEntry[];
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
  /** Questions authored in the admin panel via the old flat (non-block)
   * editor. Empty for every lesson today — kept only so nothing already
   * relying on it breaks; new authoring goes through `blocks` below. */
  authoredQuestions: AuthoredQuestion[];
  /** Named question blocks (possibly several per stage), same shape the
   * course builder uses. Empty means the exercise generator keeps producing
   * questions exactly as it did before — nothing changes until an admin
   * actually authors a block. */
  blocks: BuilderBlock[];
  /** True when an admin has saved edits for this lesson. */
  hasContentOverrides: boolean;
}
