import { z } from "zod";
import { prisma } from "./db.js";

/**
 * Case- and punctuation-insensitive form of a word, used as the course-wide
 * uniqueness key. "Hallo", "hallo" and "Hallo!" all normalise to the same
 * value, so none of them can be added twice under a different spelling.
 */
export function normalizeWord(german: string): string {
  return german
    .toLowerCase()
    .replace(/[.,!?;:…"'«»„""()]/g, "")
    .replace(/\s+/g, " ")
    .trim();
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

export interface LessonContentDTO {
  lessonId: string;
  /** null means "no admin edits yet" — the client keeps using the file. */
  materialText: string | null;
  vocabulary: { german: string; translation: string; pronunciation: string | null; audioUrl: string | null }[];
  questions: { setName: string; prompt: string; options: string[]; correctAnswer: string }[];
  /** False when nothing has ever been saved for this lesson. */
  hasOverrides: boolean;
  updatedAt: string | null;
}

export async function getLessonContent(lessonId: string): Promise<LessonContentDTO> {
  const [content, vocabulary, questions] = await Promise.all([
    prisma.lessonContent.findUnique({ where: { lessonId } }),
    prisma.vocabularyItem.findMany({ where: { lessonId }, orderBy: { position: "asc" } }),
    prisma.lessonQuestion.findMany({ where: { lessonId }, orderBy: [{ setName: "asc" }, { position: "asc" }] }),
  ]);

  return {
    lessonId,
    materialText: content?.materialText ?? null,
    vocabulary: vocabulary.map((v) => ({
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
    hasOverrides: Boolean(content) || vocabulary.length > 0 || questions.length > 0,
    updatedAt: content?.updatedAt.toISOString() ?? null,
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
        where: { germanKey: { in: keys }, lessonId: { not: lessonId } },
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
