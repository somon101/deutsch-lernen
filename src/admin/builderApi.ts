import { api, API_URL } from "../auth/api";
import { getAuthToken } from "../auth/tokenStore";

export type CourseStatus = "DRAFT" | "PUBLISHED";
export type QuestionSet = "minitest" | "practice" | "review";

export interface BuilderWord {
  id: string;
  german: string;
  translation: string;
  pronunciation: string | null;
  audioUrl: string | null;
}

/** The admin-facing JSON import shape — its own field names, mapped onto
 * BuilderWord (german/pronunciation) only at the API boundary. */
export interface VocabularyImportWord {
  original: string;
  transcription: string;
  translation: string;
}

export interface VocabularyImportItemResult {
  index: number;
  original: string;
  status: "new" | "duplicate-in-json" | "duplicate-in-course";
  message?: string;
  existingLessons?: string[];
}

export interface VocabularyImportPreview {
  total: number;
  newCount: number;
  duplicateCount: number;
  errorCount: number;
  items: VocabularyImportItemResult[];
}

/**
 * A question authored in the builder. `kind` matches `Exercise["kind"]` in
 * src/content/exercises.ts exactly, so the learner-facing runner can map one
 * straight onto the other with a plain switch.
 */
export type BuilderQuestion =
  | { kind: "choice"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "truefalse"; prompt: string; correct: boolean }
  | { kind: "cloze"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "scramble"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "match"; prompt: string; pairs: { left: string; right: string }[] };

export interface BuilderBlock {
  id: string;
  stage: QuestionSet;
  title: string;
  position: number;
  questions: BuilderQuestion[];
}

export interface BuilderLesson {
  id: string;
  title: string;
  description: string;
  materialText: string;
  videoUrl: string | null;
  audioUrl: string | null;
  position: number;
  vocabulary: BuilderWord[];
  questions: BuilderQuestion[];
  blocks: BuilderBlock[];
  /** Saved LessonFlowCanvas layout ({nodes, edges} — see that component), or
   * null if this lesson has never had its canvas arranged and saved yet. */
  canvasLayout: unknown;
}

export interface BuilderCourse {
  id: string;
  title: string;
  description: string;
  coverUrl: string | null;
  status: CourseStatus;
  position: number;
  updatedAt: string;
  lessons: BuilderLesson[];
}

export interface BuilderCourseSummary {
  id: string;
  title: string;
  description: string;
  coverUrl: string | null;
  status: CourseStatus;
  position: number;
  lessonCount: number;
  wordCount: number;
  questionCount: number;
  updatedAt: string;
}

const base = "/api/builder/courses";

export const builderApi = {
  list: () => api.get<{ courses: BuilderCourseSummary[] }>(base).then((d) => d.courses),
  get: (courseId: string) => api.get<{ course: BuilderCourse }>(`${base}/${courseId}`).then((d) => d.course),
  create: (input: { title: string; description?: string }) =>
    api.post<{ course: BuilderCourse }>(base, input).then((d) => d.course),
  update: (courseId: string, input: { title?: string; description?: string; status?: CourseStatus }) =>
    api.patch<{ course: BuilderCourse }>(`${base}/${courseId}`, input).then((d) => d.course),
  remove: (courseId: string) => api.delete<{ ok: boolean }>(`${base}/${courseId}`),
  reorderCourses: (ids: string[]) =>
    api.post<{ courses: BuilderCourseSummary[] }>(`${base}/reorder`, { ids }).then((d) => d.courses),

  addLesson: (courseId: string, input: { title: string; description?: string }) =>
    api.post<{ course: BuilderCourse }>(`${base}/${courseId}/lessons`, input).then((d) => d.course),
  updateLesson: (
    courseId: string,
    lessonId: string,
    input: { title?: string; description?: string; materialText?: string; canvasLayout?: unknown },
  ) => api.patch<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/${lessonId}`, input).then((d) => d.course),
  removeLesson: (courseId: string, lessonId: string) =>
    api.delete<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/${lessonId}`).then((d) => d.course),
  reorderLessons: (courseId: string, ids: string[]) =>
    api.post<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/reorder`, { ids }).then((d) => d.course),

  // These mutate one word/block/question and no longer return the whole
  // course — callers that need an updated view (BuilderCourseEditPage,
  // AdminLessonEditPage) re-fetch it themselves after the action resolves.
  // Real courses and courseId="legacy" (the two file-based lessons) go
  // through the exact same calls.
  addWord: (courseId: string, lessonId: string, input: { german: string; translation: string; pronunciation: string }) =>
    api.post(`${base}/${courseId}/lessons/${lessonId}/vocabulary`, input),
  updateWord: (
    courseId: string,
    lessonId: string,
    wordId: string,
    input: Partial<{ german: string; translation: string; pronunciation: string }>,
  ) => api.patch(`${base}/${courseId}/lessons/${lessonId}/vocabulary/${wordId}`, input),
  removeWord: (courseId: string, lessonId: string, wordId: string) =>
    api.delete(`${base}/${courseId}/lessons/${lessonId}/vocabulary/${wordId}`),
  reorderVocabulary: (courseId: string, lessonId: string, ids: string[]) =>
    api.post(`${base}/${courseId}/lessons/${lessonId}/vocabulary/reorder`, { ids }),
  previewVocabularyImport: (courseId: string, lessonId: string, words: VocabularyImportWord[]) =>
    api
      .post<{ preview: VocabularyImportPreview }>(`${base}/${courseId}/lessons/${lessonId}/vocabulary/import/preview`, { words })
      .then((d) => d.preview),
  // Duplicates are skipped automatically rather than blocking the whole
  // import — addedCount/skipped report exactly what happened.
  importVocabulary: (courseId: string, lessonId: string, words: VocabularyImportWord[]) =>
    api.post<{ addedCount: number; skipped: VocabularyImportItemResult[] }>(
      `${base}/${courseId}/lessons/${lessonId}/vocabulary/import`,
      { words },
    ),

  addBlock: (courseId: string, lessonId: string, stage: QuestionSet, title: string) =>
    api.post(`${base}/${courseId}/lessons/${lessonId}/blocks`, { stage, title }),
  renameBlock: (courseId: string, lessonId: string, blockId: string, title: string) =>
    api.patch(`${base}/${courseId}/lessons/${lessonId}/blocks/${blockId}`, { title }),
  removeBlock: (courseId: string, lessonId: string, blockId: string) =>
    api.delete(`${base}/${courseId}/lessons/${lessonId}/blocks/${blockId}`),
  reorderBlocks: (courseId: string, lessonId: string, stage: QuestionSet, ids: string[]) =>
    api.post(`${base}/${courseId}/lessons/${lessonId}/blocks/reorder`, { stage, ids }),
  saveBlockQuestions: (courseId: string, lessonId: string, blockId: string, questions: BuilderQuestion[]) =>
    api.put(`${base}/${courseId}/lessons/${lessonId}/blocks/${blockId}/questions`, { questions }),

  removeCover: (courseId: string) =>
    api.delete<{ course: BuilderCourse }>(`${base}/${courseId}/cover`).then((d) => d.course),
};

/** Course-lesson video/audio (real courses only) — still returns the whole
 * course, since BuilderLessonEditor's onRun re-fetches regardless. */
export const builderMedia = {
  removeMedia: (courseId: string, lessonId: string, kind: "video" | "audio") =>
    api.delete(`${base}/${courseId}/lessons/${lessonId}/media?kind=${kind}`),
};

/** Multipart word-audio upload/remove — used for both real-course and
 * legacy-lesson vocabulary, since word ownership is checked by the word's
 * own courseId/lessonId, not by a Course row. */
export const wordAudioApi = {
  upload: async (courseId: string, lessonId: string, wordId: string, file: File): Promise<{ audioUrl: string }> => {
    const form = new FormData();
    form.append("audio", file);
    return uploadForm(`${base}/${courseId}/lessons/${lessonId}/vocabulary/${wordId}/audio`, form);
  },
  remove: (courseId: string, lessonId: string, wordId: string) =>
    api.delete(`${base}/${courseId}/lessons/${lessonId}/vocabulary/${wordId}/audio`),
};

/** Multipart uploads go through fetch directly — the shared helper is JSON-only. */
async function uploadForm<T>(path: string, form: FormData): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${getAuthToken() ?? ""}` },
    body: form,
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) throw new Error(data?.error ?? "Не удалось загрузить файл");
  return data as T;
}

export function uploadLessonMedia(courseId: string, lessonId: string, kind: "video" | "audio", file: File): Promise<void> {
  const form = new FormData();
  form.append("kind", kind);
  form.append("file", file);
  return uploadForm(`${base}/${courseId}/lessons/${lessonId}/media`, form);
}

export function uploadCourseCover(courseId: string, file: File): Promise<BuilderCourse> {
  const form = new FormData();
  form.append("file", file);
  return uploadForm<{ course: BuilderCourse }>(`${base}/${courseId}/cover`, form).then((d) => d.course);
}
