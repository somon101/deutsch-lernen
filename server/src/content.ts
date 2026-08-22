import { z } from "zod";
import { Prisma } from "@prisma/client";
import { prisma } from "./db.js";

/**
 * Case- and punctuation-insensitive form of a word, used as the course-wide
 * uniqueness key. "Hallo", "hallo" and "Hallo!" all normalise to the same
 * value, so none of them can be added twice under a different spelling.
 */
/** The original, file-based course. Courses made in the builder use their
 * own Course id, so words never clash across independent courses. */
export const LEGACY_COURSE_ID = "legacy";

export function normalizeWord(german: string): string {
  return german
    .toLowerCase()
    .replace(/[.,!?;:…"'«»„""()]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** Formal marks stripped only from the edges of a quiz answer/option — never
 * from the middle, where punctuation like a mid-phrase comma usually carries
 * real meaning. Mirrors the client's cleanQuizText (src/content/textUtils.ts)
 * exactly, since both must agree on what counts as a "hint" character. */
const QUIZ_EDGE_PUNCTUATION = /^[.!?;:…"'«»„""()/]+|[.!?;:…"'«»„""()/]+$/g;

/**
 * Cleans a string before it's stored as a quiz option/answer, so its
 * punctuation can never visually single out the correct choice among
 * distractors. Never applied to material text or a question's own prompt —
 * only to the answer-bearing fields validated in blockQuestionSchema
 * (courses.ts).
 */
export function cleanQuizText(value: string): string {
  return value.replace(QUIZ_EDGE_PUNCTUATION, "").replace(/\s+/g, " ").trim();
}

/** Human-readable lesson name for duplicate messages ("lesson2" -> "Урок 2"). */
export function lessonLabel(lessonId: string): string {
  const n = lessonId.match(/(\d+)$/);
  return n ? `Урок ${n[1]}` : lessonId;
}

/** Raised when a word would end up in two lessons of the same course. */
export class DuplicateWordError extends Error {}

export const QUESTION_SETS = ["minitest", "practice", "review"] as const;
export type QuestionSet = (typeof QUESTION_SETS)[number];

export const vocabularyItemSchema = z.object({
  german: z.string().trim().min(1, "Немецкое слово не может быть пустым"),
  translation: z.string().trim().min(1, "Перевод не может быть пустым"),
  pronunciation: z.string().trim().optional().nullable(),
  audioUrl: z.string().trim().optional().nullable(),
});

export const questionSchema = z
  .object({
    setName: z.enum(QUESTION_SETS),
    prompt: z.string().trim().min(1, "Текст вопроса не может быть пустым"),
    options: z.array(z.string().trim().min(1, "Вариант ответа не может быть пустым")).min(2, "Нужно минимум 2 варианта ответа"),
    correctAnswer: z.string().trim().min(1, "Нужно отметить правильный вариант"),
  })
  // Correctness is stored by value, so the marked answer must actually be one
  // of the options — otherwise the question would be unanswerable.
  .refine((q) => q.options.includes(q.correctAnswer), {
    message: "Правильный ответ должен быть одним из вариантов",
  })
  .refine((q) => new Set(q.options).size === q.options.length, {
    message: "Варианты ответа не должны повторяться",
  });

export const contentPayloadSchema = z.object({
  materialText: z.string().optional(),
  vocabulary: z.array(vocabularyItemSchema).optional(),
  questions: z.array(questionSchema).optional(),
});

export type ContentPayload = z.infer<typeof contentPayloadSchema>;

/**
 * A question authored in the admin panel (either course), tagged with its
 * kind. `kind` matches `Exercise["kind"]` in src/content/exercises.ts
 * exactly, so the client can map one straight onto the other with a plain
 * switch. Lives here (not in courses.ts) so both the legacy course and the
 * builder can import it without a circular dependency between the two.
 */
export type QuestionDTO =
  | { kind: "choice"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "truefalse"; prompt: string; correct: boolean }
  | { kind: "cloze"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "scramble"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "match"; prompt: string; pairs: { left: string; right: string }[] };

export function toQuestionDTO(q: {
  kind: string;
  prompt: string;
  options: string[];
  correctAnswer: string;
  data: unknown;
}): QuestionDTO {
  switch (q.kind) {
    case "truefalse":
      return { kind: "truefalse", prompt: q.prompt, correct: q.correctAnswer === "true" };
    case "cloze":
      return { kind: "cloze", prompt: q.prompt, options: q.options, correctAnswer: q.correctAnswer };
    case "scramble":
      return { kind: "scramble", prompt: q.prompt, options: q.options, correctAnswer: q.correctAnswer };
    case "match":
      return { kind: "match", prompt: q.prompt, pairs: (q.data as { left: string; right: string }[] | null) ?? [] };
    case "choice":
    default:
      return { kind: "choice", prompt: q.prompt, options: q.options, correctAnswer: q.correctAnswer };
  }
}

export interface LessonBlockDTO {
  id: string;
  stage: QuestionSet;
  title: string;
  position: number;
  questions: QuestionDTO[];
}

export interface LessonContentDTO {
  lessonId: string;
  /** null means "no admin edits yet" — the client keeps using the file. */
  materialText: string | null;
  /** null means "use the bundled file" — same override-if-present meaning as materialText. */
  videoUrl: string | null;
  audioUrl: string | null;
  vocabulary: { id: string; german: string; translation: string; pronunciation: string | null; audioUrl: string | null }[];
  questions: { setName: string; prompt: string; options: string[]; correctAnswer: string }[];
  /** Named question blocks (multiple mini-tests/practice/review sets), same shape the builder uses. */
  blocks: LessonBlockDTO[];
  /** False when nothing has ever been saved for this lesson. */
  hasOverrides: boolean;
  updatedAt: string | null;
  /** Saved LessonFlowCanvas layout, or null if never saved yet. */
  canvasLayout: unknown;
}

export async function getLessonContent(lessonId: string): Promise<LessonContentDTO> {
  const [content, vocabulary, questions, blocks] = await Promise.all([
    prisma.lessonContent.findUnique({ where: { lessonId } }),
    prisma.vocabularyItem.findMany({ where: { lessonId }, orderBy: { position: "asc" } }),
    prisma.lessonQuestion.findMany({ where: { lessonId }, orderBy: [{ setName: "asc" }, { position: "asc" }] }),
    prisma.lessonBlock.findMany({ where: { lessonId }, orderBy: [{ stage: "asc" }, { position: "asc" }] }),
  ]);

  return {
    lessonId,
    materialText: content?.materialText ?? null,
    videoUrl: content?.videoUrl ?? null,
    audioUrl: content?.audioUrl ?? null,
    vocabulary: vocabulary.map((v) => ({
      id: v.id,
      german: v.german,
      translation: v.translation,
      pronunciation: v.pronunciation,
      audioUrl: v.audioUrl,
    })),
    questions: questions.map((q) => ({
      setName: q.setName,
      prompt: q.prompt,
      options: q.options,
      correctAnswer: q.correctAnswer,
    })),
    blocks: blocks.map((b) => ({
      id: b.id,
      stage: b.stage as QuestionSet,
      title: b.title,
      position: b.position,
      questions: questions.filter((q) => q.blockId === b.id).map(toQuestionDTO),
    })),
    hasOverrides: Boolean(content) || vocabulary.length > 0 || questions.length > 0,
    updatedAt: content?.updatedAt.toISOString() ?? null,
    canvasLayout: content?.canvasLayout ?? null,
  };
}

/**
 * Saves whichever sections were supplied. Each section is replaced wholesale
 * inside one transaction, so a half-applied vocabulary list can never reach
 * learners. Sections that are omitted are left untouched.
 */
export async function saveLessonContent(
  lessonId: string,
  payload: ContentPayload,
  editorId: string,
): Promise<LessonContentDTO> {
  await prisma.$transaction(async (tx) => {
    if (payload.materialText !== undefined) {
      await tx.lessonContent.upsert({
        where: { lessonId },
        update: { materialText: payload.materialText, updatedById: editorId },
        create: { lessonId, materialText: payload.materialText, updatedById: editorId },
      });
    }

    if (payload.vocabulary !== undefined) {
      // A word may only belong to one lesson of the course. Reject the whole
      // save (rather than silently dropping a word) and name the lesson the
      // word already lives in, so the admin knows where to look.
      const keys = payload.vocabulary.map((item) => normalizeWord(item.german));
      const duplicateInPayload = keys.find((key, i) => keys.indexOf(key) !== i);
      if (duplicateInPayload) {
        const word = payload.vocabulary[keys.indexOf(duplicateInPayload)].german;
        throw new DuplicateWordError(`Слово «${word}» указано в этом уроке дважды`);
      }

      const clashes = await tx.vocabularyItem.findMany({
        where: { courseId: LEGACY_COURSE_ID, germanKey: { in: keys }, lessonId: { not: lessonId } },
        select: { german: true, lessonId: true },
      });
      if (clashes.length > 0) {
        const list = clashes
          .map((c) => `«${c.german}» — уже в уроке «${lessonLabel(c.lessonId)}»`)
          .join("; ");
        throw new DuplicateWordError(`Это слово уже используется в другом уроке: ${list}`);
      }

      // Recorded pronunciations are attached to the word, so they survive a
      // full rewrite of the lesson's list.
      const existing = await tx.vocabularyItem.findMany({
        where: { lessonId },
        select: { germanKey: true, audioUrl: true },
      });
      const audioByKey = new Map(existing.map((e) => [e.germanKey, e.audioUrl]));

      await tx.vocabularyItem.deleteMany({ where: { lessonId } });
      if (payload.vocabulary.length > 0) {
        await tx.vocabularyItem.createMany({
          data: payload.vocabulary.map((item, index) => {
            const germanKey = normalizeWord(item.german);
            return {
              lessonId,
              german: item.german,
              translation: item.translation,
              pronunciation: item.pronunciation?.trim() ? item.pronunciation.trim() : null,
              audioUrl: item.audioUrl?.trim() ? item.audioUrl.trim() : (audioByKey.get(germanKey) ?? null),
              position: index,
              germanKey,
            };
          }),
        });
      }
    }

    if (payload.questions !== undefined) {
      await tx.lessonQuestion.deleteMany({ where: { lessonId } });
      if (payload.questions.length > 0) {
        // Positions are per-set so each stage keeps its own ordering.
        const counters: Record<string, number> = {};
        await tx.lessonQuestion.createMany({
          data: payload.questions.map((q) => {
            const position = counters[q.setName] ?? 0;
            counters[q.setName] = position + 1;
            return {
              lessonId,
              setName: q.setName,
              prompt: q.prompt,
              options: q.options,
              correctAnswer: q.correctAnswer,
              position,
            };
          }),
        });
      }
    }
  });

  return getLessonContent(lessonId);
}

/**
 * Overrides (or clears, with url = null) the bundled video/audio file for a
 * legacy lesson. Upserts because a lesson may not have a LessonContent row
 * yet (e.g. its material has never been edited) — same pattern as
 * materialText/vocabulary above.
 */
export async function setLegacyLessonMedia(
  lessonId: string,
  kind: "video" | "audio",
  url: string | null,
): Promise<LessonContentDTO> {
  const field = kind === "video" ? "videoUrl" : "audioUrl";
  await prisma.lessonContent.upsert({
    where: { lessonId },
    update: { [field]: url },
    create: { lessonId, [field]: url },
  });
  return getLessonContent(lessonId);
}

/** Saves the LessonFlowCanvas layout for a legacy lesson — same upsert
 * pattern as setLegacyLessonMedia above, and just as presentation-only
 * (accepted as opaque JSON; see LessonContentDTO.canvasLayout). */
export async function saveLegacyCanvasLayout(lessonId: string, layout: unknown): Promise<LessonContentDTO> {
  await prisma.lessonContent.upsert({
    where: { lessonId },
    update: { canvasLayout: layout as Prisma.InputJsonValue },
    create: { lessonId, canvasLayout: layout as Prisma.InputJsonValue },
  });
  return getLessonContent(lessonId);
}
