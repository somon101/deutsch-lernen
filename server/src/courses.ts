import { z } from "zod";
import { prisma } from "./db.js";
import { QUESTION_SETS, QuestionSet, DuplicateWordError, normalizeWord, questionSchema, vocabularyItemSchema } from "./content.js";

/**
 * Courses built from scratch in the admin panel. They live entirely in the
 * database and are completely independent of the original file-based course
 * and of each other — nothing is ever copied between them.
 */

export const courseInputSchema = z.object({
  title: z.string().trim().min(1, "Название курса не может быть пустым").max(200),
  description: z.string().trim().max(4000).optional(),
  status: z.enum(["DRAFT", "PUBLISHED"]).optional(),
});

export const lessonInputSchema = z.object({
  title: z.string().trim().min(1, "Название урока не может быть пустым").max(200),
  description: z.string().trim().max(4000).optional(),
  materialText: z.string().optional(),
});

export const reorderSchema = z.object({
  ids: z.array(z.string().min(1)).min(1, "Нужен хотя бы один элемент"),
});

export const vocabularyPayloadSchema = z.object({
  vocabulary: z.array(vocabularyItemSchema),
});

export const questionsPayloadSchema = z.object({
  questions: z.array(questionSchema),
});

export interface CourseSummaryDTO {
  id: string;
  title: string;
  description: string;
  coverUrl: string | null;
  status: "DRAFT" | "PUBLISHED";
  position: number;
  lessonCount: number;
  wordCount: number;
  questionCount: number;
  updatedAt: string;
}

/**
 * A question authored in the builder. `kind` matches `Exercise["kind"]` in
 * src/content/exercises.ts exactly, so the client can map one straight onto
 * the other with a plain switch — no renaming layer between DB, API and the
 * learner-facing exercise runner.
 */
export type BuilderQuestionDTO =
  | { kind: "choice"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "truefalse"; prompt: string; correct: boolean }
  | { kind: "cloze"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "scramble"; prompt: string; options: string[]; correctAnswer: string }
  | { kind: "match"; prompt: string; pairs: { left: string; right: string }[] };

function toQuestionDTO(q: {
  kind: string;
  prompt: string;
  options: string[];
  correctAnswer: string;
  data: unknown;
}): BuilderQuestionDTO {
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
  questions: BuilderQuestionDTO[];
}

export interface CourseLessonDTO {
  id: string;
  title: string;
  description: string;
  materialText: string;
  videoUrl: string | null;
  audioUrl: string | null;
  position: number;
  vocabulary: { german: string; translation: string; pronunciation: string | null; audioUrl: string | null }[];
  questions: (BuilderQuestionDTO & { setName: string })[];
  /** Named question blocks, grouped by stage and ordered within it. */
  blocks: LessonBlockDTO[];
}

export interface CourseDTO extends Omit<CourseSummaryDTO, "lessonCount" | "wordCount" | "questionCount"> {
  lessons: CourseLessonDTO[];
}

export async function listCourses(): Promise<CourseSummaryDTO[]> {
  const courses = await prisma.course.findMany({
    orderBy: { position: "asc" },
    include: { lessons: { select: { id: true } } },
  });

  // Words and questions hang off lesson ids, so count them per course in one go.
  const [words, questions] = await Promise.all([
    prisma.vocabularyItem.groupBy({ by: ["courseId"], _count: { _all: true } }),
    prisma.lessonQuestion.groupBy({ by: ["courseId"], _count: { _all: true } }),
  ]);
  const wordsBy = new Map(words.map((w) => [w.courseId, w._count._all]));
  const questionsBy = new Map(questions.map((q) => [q.courseId, q._count._all]));

  return courses.map((course) => ({
    id: course.id,
    title: course.title,
    description: course.description,
    coverUrl: course.coverUrl,
    status: course.status,
    position: course.position,
    lessonCount: course.lessons.length,
    wordCount: wordsBy.get(course.id) ?? 0,
    questionCount: questionsBy.get(course.id) ?? 0,
    updatedAt: course.updatedAt.toISOString(),
  }));
}

export async function getCourse(courseId: string): Promise<CourseDTO | null> {
  const course = await prisma.course.findUnique({
    where: { id: courseId },
    include: { lessons: { orderBy: { position: "asc" } } },
  });
  if (!course) return null;

  const lessonIds = course.lessons.map((l) => l.id);
  const [words, questions, blocks] = await Promise.all([
    prisma.vocabularyItem.findMany({
      where: { lessonId: { in: lessonIds } },
      orderBy: { position: "asc" },
    }),
    prisma.lessonQuestion.findMany({
      where: { lessonId: { in: lessonIds } },
      orderBy: [{ setName: "asc" }, { position: "asc" }],
    }),
    prisma.lessonBlock.findMany({
      where: { lessonId: { in: lessonIds } },
      orderBy: [{ stage: "asc" }, { position: "asc" }],
    }),
  ]);

  return {
    id: course.id,
    title: course.title,
    description: course.description,
    coverUrl: course.coverUrl,
    status: course.status,
    position: course.position,
    updatedAt: course.updatedAt.toISOString(),
    lessons: course.lessons.map((lesson) => ({
      id: lesson.id,
      title: lesson.title,
      description: lesson.description,
      materialText: lesson.materialText,
      videoUrl: lesson.videoUrl,
      audioUrl: lesson.audioUrl,
      position: lesson.position,
      vocabulary: words
        .filter((w) => w.lessonId === lesson.id)
        .map((w) => ({
          german: w.german,
          translation: w.translation,
          pronunciation: w.pronunciation,
          audioUrl: w.audioUrl,
        })),
      questions: questions
        .filter((q) => q.lessonId === lesson.id)
        .map((q) => ({ setName: q.setName, ...toQuestionDTO(q) })),
      blocks: blocks
        .filter((b) => b.lessonId === lesson.id)
        .map((b) => ({
          id: b.id,
          stage: b.stage as QuestionSet,
          title: b.title,
          position: b.position,
          questions: questions.filter((q) => q.blockId === b.id).map((q) => toQuestionDTO(q)),
        })),
    })),
  };
}

export async function createCourse(
  input: z.infer<typeof courseInputSchema>,
  createdById: string,
): Promise<CourseDTO> {
  const last = await prisma.course.findFirst({ orderBy: { position: "desc" }, select: { position: true } });
  const course = await prisma.course.create({
    data: {
      title: input.title,
      description: input.description ?? "",
      status: input.status ?? "DRAFT",
      position: (last?.position ?? -1) + 1,
      createdById,
    },
  });
  return (await getCourse(course.id))!;
}

export async function updateCourse(
  courseId: string,
  input: Partial<z.infer<typeof courseInputSchema>>,
): Promise<CourseDTO | null> {
  const exists = await prisma.course.findUnique({ where: { id: courseId }, select: { id: true } });
  if (!exists) return null;
  await prisma.course.update({ where: { id: courseId }, data: input });
  return getCourse(courseId);
}

export async function deleteCourse(courseId: string): Promise<boolean> {
  const course = await prisma.course.findUnique({
    where: { id: courseId },
    include: { lessons: { select: { id: true } } },
  });
  if (!course) return false;

  const lessonIds = course.lessons.map((l) => l.id);
  await prisma.$transaction([
    prisma.vocabularyItem.deleteMany({ where: { lessonId: { in: lessonIds } } }),
    prisma.lessonQuestion.deleteMany({ where: { lessonId: { in: lessonIds } } }),
    prisma.lessonBlock.deleteMany({ where: { lessonId: { in: lessonIds } } }),
    // Lessons go with the course through the cascade on the relation.
    prisma.course.delete({ where: { id: courseId } }),
  ]);
  return true;
}

/** Applies the given order; ids not listed keep their relative order after them. */
export async function reorderCourses(ids: string[]): Promise<void> {
  await prisma.$transaction(
    ids.map((id, index) => prisma.course.update({ where: { id }, data: { position: index } })),
  );
}

export async function createLesson(
  courseId: string,
  input: z.infer<typeof lessonInputSchema>,
): Promise<CourseDTO | null> {
  const course = await prisma.course.findUnique({ where: { id: courseId }, select: { id: true } });
  if (!course) return null;

  const last = await prisma.courseLesson.findFirst({
    where: { courseId },
    orderBy: { position: "desc" },
    select: { position: true },
  });
  await prisma.courseLesson.create({
    data: {
      courseId,
      title: input.title,
      description: input.description ?? "",
      materialText: input.materialText ?? "",
      position: (last?.position ?? -1) + 1,
    },
  });
  return getCourse(courseId);
}

export async function updateLesson(
  courseId: string,
  lessonId: string,
  input: Partial<z.infer<typeof lessonInputSchema>>,
): Promise<CourseDTO | null> {
  const lesson = await prisma.courseLesson.findFirst({ where: { id: lessonId, courseId }, select: { id: true } });
  if (!lesson) return null;
  await prisma.courseLesson.update({ where: { id: lessonId }, data: input });
  return getCourse(courseId);
}

export async function deleteLesson(courseId: string, lessonId: string): Promise<CourseDTO | null> {
  const lesson = await prisma.courseLesson.findFirst({ where: { id: lessonId, courseId }, select: { id: true } });
  if (!lesson) return null;
  await prisma.$transaction([
    prisma.vocabularyItem.deleteMany({ where: { lessonId } }),
    prisma.lessonQuestion.deleteMany({ where: { lessonId } }),
    prisma.lessonBlock.deleteMany({ where: { lessonId } }),
    prisma.courseLesson.delete({ where: { id: lessonId } }),
  ]);
  return getCourse(courseId);
}

export async function reorderLessons(courseId: string, ids: string[]): Promise<CourseDTO | null> {
  const lessons = await prisma.courseLesson.findMany({ where: { courseId }, select: { id: true } });
  const owned = new Set(lessons.map((l) => l.id));
  // Silently ignoring foreign ids would let one course reorder another's.
  if (!ids.every((id) => owned.has(id))) return null;

  await prisma.$transaction(
    ids.map((id, index) => prisma.courseLesson.update({ where: { id }, data: { position: index } })),
  );
  return getCourse(courseId);
}

export async function setLessonMedia(
  courseId: string,
  lessonId: string,
  kind: "video" | "audio",
  url: string | null,
): Promise<CourseDTO | null> {
  const lesson = await prisma.courseLesson.findFirst({ where: { id: lessonId, courseId }, select: { id: true } });
  if (!lesson) return null;
  await prisma.courseLesson.update({
    where: { id: lessonId },
    data: kind === "video" ? { videoUrl: url } : { audioUrl: url },
  });
  return getCourse(courseId);
}

export async function setCourseCover(courseId: string, url: string | null): Promise<CourseDTO | null> {
  const course = await prisma.course.findUnique({ where: { id: courseId }, select: { id: true } });
  if (!course) return null;
  await prisma.course.update({ where: { id: courseId }, data: { coverUrl: url } });
  return getCourse(courseId);
}

/**
 * Replaces a lesson's word list. A word may only appear once per course, so
 * the whole save is rejected — naming the lesson it already lives in — rather
 * than silently dropping the duplicate.
 */
export async function saveLessonVocabulary(
  courseId: string,
  lessonId: string,
  items: z.infer<typeof vocabularyItemSchema>[],
): Promise<CourseDTO | null> {
  const lesson = await prisma.courseLesson.findFirst({ where: { id: lessonId, courseId } });
  if (!lesson) return null;

  const keys = items.map((item) => normalizeWord(item.german));
  const twiceHere = keys.find((key, i) => keys.indexOf(key) !== i);
  if (twiceHere) {
    throw new DuplicateWordError(`Слово «${items[keys.indexOf(twiceHere)].german}» указано в этом уроке дважды`);
  }

  const clashes = await prisma.vocabularyItem.findMany({
    where: { courseId, germanKey: { in: keys }, lessonId: { not: lessonId } },
    select: { german: true, lessonId: true },
  });
  if (clashes.length > 0) {
    const lessons = await prisma.courseLesson.findMany({
      where: { id: { in: clashes.map((c) => c.lessonId) } },
      select: { id: true, title: true },
    });
    const titleById = new Map(lessons.map((l) => [l.id, l.title]));
    const list = clashes
      .map((c) => `«${c.german}» — уже в уроке «${titleById.get(c.lessonId) ?? c.lessonId}»`)
      .join("; ");
    throw new DuplicateWordError(`Это слово уже используется в другом уроке курса: ${list}`);
  }

  await prisma.$transaction(async (tx) => {
    // Recorded pronunciations belong to the word, so they survive a rewrite.
    const existing = await tx.vocabularyItem.findMany({
      where: { lessonId },
      select: { germanKey: true, audioUrl: true },
    });
    const audioByKey = new Map(existing.map((e) => [e.germanKey, e.audioUrl]));

    await tx.vocabularyItem.deleteMany({ where: { lessonId } });
    if (items.length > 0) {
      await tx.vocabularyItem.createMany({
        data: items.map((item, index) => {
          const germanKey = normalizeWord(item.german);
          return {
            courseId,
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
  });

  return getCourse(courseId);
}

export async function saveLessonQuestions(
  courseId: string,
  lessonId: string,
  questions: z.infer<typeof questionSchema>[],
): Promise<CourseDTO | null> {
  const lesson = await prisma.courseLesson.findFirst({ where: { id: lessonId, courseId }, select: { id: true } });
  if (!lesson) return null;

  await prisma.$transaction(async (tx) => {
    await tx.lessonQuestion.deleteMany({ where: { lessonId } });
    if (questions.length > 0) {
      // Positions are per-set so each stage keeps its own ordering.
      const counters: Record<string, number> = {};
      await tx.lessonQuestion.createMany({
        data: questions.map((q) => {
          const position = counters[q.setName] ?? 0;
          counters[q.setName] = position + 1;
          return {
            courseId,
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
  });

  return getCourse(courseId);
}

// ---------------------------------------------------------------------------
// Question blocks
//
// A stage may hold several named blocks, so a lesson can have "Мини-тест 1"
// and "Мини-тест 2" while the learner still walks the same stage sequence.
// ---------------------------------------------------------------------------

export const blockInputSchema = z.object({
  stage: z.enum(QUESTION_SETS),
  title: z.string().trim().min(1, "Название блока не может быть пустым").max(200),
});

// Five question kinds an admin can author inside a block. `kind` matches
// Exercise["kind"] in src/content/exercises.ts exactly (see BuilderQuestionDTO
// above), so the learner-facing runner needs no translation layer.
const choiceQuestionObject = z.object({
  kind: z.literal("choice"),
  prompt: z.string().trim().min(1, "Текст вопроса не может быть пустым"),
  options: z
    .array(z.string().trim().min(1, "Вариант ответа не может быть пустым"))
    .min(2, "Нужно минимум 2 варианта ответа"),
  correctAnswer: z.string().trim().min(1, "Нужно отметить правильный вариант"),
});

const trueFalseQuestionObject = z.object({
  kind: z.literal("truefalse"),
  prompt: z.string().trim().min(1, "Текст утверждения не может быть пустым"),
  correct: z.boolean(),
});

const clozeQuestionObject = z.object({
  kind: z.literal("cloze"),
  prompt: z.string().trim().min(1, "Текст фразы не может быть пустым"),
  options: z
    .array(z.string().trim().min(1, "Вариант ответа не может быть пустым"))
    .min(2, "Нужно минимум 2 варианта ответа"),
  correctAnswer: z.string().trim().min(1, "Нужно отметить правильный вариант"),
});

const scrambleQuestionObject = z.object({
  kind: z.literal("scramble"),
  prompt: z.string().trim().min(1, "Укажите перевод или инструкцию"),
  options: z.array(z.string().trim().min(1, "Слово не может быть пустым")).min(1, "Добавьте хотя бы одно слово"),
  correctAnswer: z.string().trim().min(1, "Укажите правильную фразу"),
});

const matchQuestionObject = z.object({
  kind: z.literal("match"),
  prompt: z.string().trim().optional().default(""),
  pairs: z
    .array(
      z.object({
        left: z.string().trim().min(1, "Заполните обе части пары"),
        right: z.string().trim().min(1, "Заполните обе части пары"),
      }),
    )
    .min(2, "Нужно минимум 2 пары"),
});

export const blockQuestionSchema = z
  .discriminatedUnion("kind", [
    choiceQuestionObject,
    trueFalseQuestionObject,
    clozeQuestionObject,
    scrambleQuestionObject,
    matchQuestionObject,
  ])
  // Cross-field rules that z.discriminatedUnion's member schemas can't
  // express on their own (they must stay plain ZodObjects for the
  // discriminator lookup to work).
  .superRefine((q, ctx) => {
    if (q.kind === "choice" || q.kind === "cloze") {
      if (!q.options.includes(q.correctAnswer)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "Правильный ответ должен быть одним из вариантов",
          path: ["correctAnswer"],
        });
      }
      if (new Set(q.options).size !== q.options.length) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "Варианты ответа не должны повторяться",
          path: ["options"],
        });
      }
    }
    if (q.kind === "cloze" && (q.prompt.match(/___/g) ?? []).length !== 1) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "Отметьте ровно один пропуск как ___",
        path: ["prompt"],
      });
    }
  });

export const blockQuestionsPayloadSchema = z.object({
  questions: z.array(blockQuestionSchema),
});

async function ownedLesson(courseId: string, lessonId: string) {
  return prisma.courseLesson.findFirst({ where: { id: lessonId, courseId }, select: { id: true } });
}

export async function createBlock(
  courseId: string,
  lessonId: string,
  input: z.infer<typeof blockInputSchema>,
): Promise<CourseDTO | null> {
  if (!(await ownedLesson(courseId, lessonId))) return null;

  const last = await prisma.lessonBlock.findFirst({
    where: { lessonId, stage: input.stage },
    orderBy: { position: "desc" },
    select: { position: true },
  });
  await prisma.lessonBlock.create({
    data: { courseId, lessonId, stage: input.stage, title: input.title, position: (last?.position ?? -1) + 1 },
  });
  return getCourse(courseId);
}

export async function updateBlock(
  courseId: string,
  lessonId: string,
  blockId: string,
  title: string,
): Promise<CourseDTO | null> {
  const block = await prisma.lessonBlock.findFirst({ where: { id: blockId, lessonId, courseId } });
  if (!block) return null;
  await prisma.lessonBlock.update({ where: { id: blockId }, data: { title } });
  return getCourse(courseId);
}

export async function deleteBlock(courseId: string, lessonId: string, blockId: string): Promise<CourseDTO | null> {
  const block = await prisma.lessonBlock.findFirst({ where: { id: blockId, lessonId, courseId } });
  if (!block) return null;
  await prisma.$transaction([
    prisma.lessonQuestion.deleteMany({ where: { blockId } }),
    prisma.lessonBlock.delete({ where: { id: blockId } }),
  ]);
  return getCourse(courseId);
}

/** Reorders the blocks of one stage; ids from another stage are refused. */
export async function reorderBlocks(
  courseId: string,
  lessonId: string,
  stage: QuestionSet,
  ids: string[],
): Promise<CourseDTO | null> {
  const blocks = await prisma.lessonBlock.findMany({ where: { lessonId, courseId, stage }, select: { id: true } });
  const owned = new Set(blocks.map((b) => b.id));
  if (ids.length !== owned.size || !ids.every((id) => owned.has(id))) return null;

  await prisma.$transaction(
    ids.map((id, index) => prisma.lessonBlock.update({ where: { id }, data: { position: index } })),
  );
  return getCourse(courseId);
}

export async function saveBlockQuestions(
  courseId: string,
  lessonId: string,
  blockId: string,
  questions: z.infer<typeof blockQuestionSchema>[],
): Promise<CourseDTO | null> {
  const block = await prisma.lessonBlock.findFirst({ where: { id: blockId, lessonId, courseId } });
  if (!block) return null;

  await prisma.$transaction(async (tx) => {
    await tx.lessonQuestion.deleteMany({ where: { blockId } });
    if (questions.length > 0) {
      await tx.lessonQuestion.createMany({
        data: questions.map((q, index) => {
          const base = { courseId, lessonId, blockId, setName: block.stage, position: index, kind: q.kind };
          switch (q.kind) {
            case "truefalse":
              return { ...base, prompt: q.prompt, options: [], correctAnswer: String(q.correct) };
            case "match":
              return { ...base, prompt: q.prompt ?? "", options: [], correctAnswer: "", data: q.pairs };
            default:
              // choice / cloze / scramble all fit prompt + options + correctAnswer as-is.
              return { ...base, prompt: q.prompt, options: q.options, correctAnswer: q.correctAnswer };
          }
        }),
      });
    }
  });

  return getCourse(courseId);
}
