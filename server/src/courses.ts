import { z } from "zod";
import { prisma } from "./db.js";
import { DuplicateWordError, normalizeWord, questionSchema, vocabularyItemSchema } from "./content.js";

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

export interface CourseLessonDTO {
  id: string;
  title: string;
  description: string;
  materialText: string;
  videoUrl: string | null;
  audioUrl: string | null;
  position: number;
  vocabulary: { german: string; translation: string; pronunciation: string | null; audioUrl: string | null }[];
  questions: { setName: string; prompt: string; options: string[]; correctAnswer: string }[];
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
  const [words, questions] = await Promise.all([
    prisma.vocabularyItem.findMany({
      where: { lessonId: { in: lessonIds } },
      orderBy: { position: "asc" },
    }),
    prisma.lessonQuestion.findMany({
      where: { lessonId: { in: lessonIds } },
      orderBy: [{ setName: "asc" }, { position: "asc" }],
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
        .map((q) => ({
          setName: q.setName,
          prompt: q.prompt,
          options: q.options,
          correctAnswer: q.correctAnswer,
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
