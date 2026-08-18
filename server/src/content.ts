import { z } from "zod";
import { prisma } from "./db.js";

export const QUESTION_SETS = ["minitest", "practice", "review"] as const;
export type QuestionSet = (typeof QUESTION_SETS)[number];

export const vocabularyItemSchema = z.object({
  german: z.string().trim().min(1, "Немецкое слово не может быть пустым"),
  translation: z.string().trim().min(1, "Перевод не может быть пустым"),
  pronunciation: z.string().trim().optional().nullable(),
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
  vocabulary: { german: string; translation: string; pronunciation: string | null }[];
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
      await tx.vocabularyItem.deleteMany({ where: { lessonId } });
      if (payload.vocabulary.length > 0) {
        await tx.vocabularyItem.createMany({
          data: payload.vocabulary.map((item, index) => ({
            lessonId,
            german: item.german,
            translation: item.translation,
            pronunciation: item.pronunciation?.trim() ? item.pronunciation.trim() : null,
            position: index,
          })),
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
