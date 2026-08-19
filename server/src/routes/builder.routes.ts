import { Router } from "express";
import fs from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { requireAdmin, requireAuth } from "../auth/middleware.js";
import { DuplicateWordError } from "../content.js";
import { COURSE_MEDIA_DIR, uploadCourseMedia, WORD_AUDIO_DIR, uploadWordAudio } from "../upload.js";
import {
  addVocabularyWord,
  blockInputSchema,
  blockQuestionsPayloadSchema,
  createBlock,
  courseInputSchema,
  createCourse,
  createLesson,
  deleteCourse,
  deleteLesson,
  deleteVocabularyWord,
  getCourse,
  importVocabularyWords,
  lessonInputSchema,
  listCourses,
  previewVocabularyImport,
  questionsPayloadSchema,
  reorderCourses,
  reorderLessons,
  reorderSchema,
  deleteBlock,
  reorderBlocks,
  saveBlockQuestions,
  saveLessonQuestions,
  setVocabularyWordAudio,
  updateBlock,
  updateVocabularyWord,
  setCourseCover,
  setLessonMedia,
  updateCourse,
  updateLesson,
  vocabularyImportPayloadSchema,
  vocabularyWordInputSchema,
} from "../courses.js";

/**
 * Course builder. Every route here sits behind requireAuth + requireAdmin, so
 * a USER token is refused no matter what the interface offers.
 */
export const builderRouter = Router();

builderRouter.use(requireAuth, requireAdmin);

function firstIssue(error: z.ZodError, fallback: string): string {
  return error.issues[0]?.message ?? fallback;
}

// ---------------------------------------------------------------------------
// Courses
// ---------------------------------------------------------------------------

builderRouter.get("/courses", async (_req, res) => {
  res.json({ courses: await listCourses() });
});

builderRouter.post("/courses", async (req, res) => {
  const parsed = courseInputSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные курса") });
  const course = await createCourse(parsed.data, req.user!.id);
  res.status(201).json({ course });
});

builderRouter.post("/courses/reorder", async (req, res) => {
  const parsed = reorderSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректный порядок") });
  await reorderCourses(parsed.data.ids);
  res.json({ courses: await listCourses() });
});

builderRouter.get("/courses/:courseId", async (req, res) => {
  const course = await getCourse(req.params.courseId);
  if (!course) return res.status(404).json({ error: "Курс не найден" });
  res.json({ course });
});

builderRouter.patch("/courses/:courseId", async (req, res) => {
  const parsed = courseInputSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные курса") });
  const course = await updateCourse(req.params.courseId, parsed.data);
  if (!course) return res.status(404).json({ error: "Курс не найден" });
  res.json({ course });
});

builderRouter.delete("/courses/:courseId", async (req, res) => {
  const ok = await deleteCourse(req.params.courseId);
  if (!ok) return res.status(404).json({ error: "Курс не найден" });
  res.json({ ok: true });
});

builderRouter.post("/courses/:courseId/cover", uploadCourseMedia.single("file"), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: "Файл не получен" });
  const course = await setCourseCover(req.params.courseId, `/uploads/courses/${req.file.filename}`);
  if (!course) return res.status(404).json({ error: "Курс не найден" });
  res.json({ course });
});

builderRouter.delete("/courses/:courseId/cover", async (req, res) => {
  const existing = await getCourse(req.params.courseId);
  if (!existing) return res.status(404).json({ error: "Курс не найден" });
  if (existing.coverUrl) {
    fs.unlink(path.join(COURSE_MEDIA_DIR, path.basename(existing.coverUrl))).catch(() => {});
  }
  res.json({ course: await setCourseCover(req.params.courseId, null) });
});

// ---------------------------------------------------------------------------
// Lessons
// ---------------------------------------------------------------------------

builderRouter.post("/courses/:courseId/lessons", async (req, res) => {
  const parsed = lessonInputSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные урока") });
  const course = await createLesson(req.params.courseId, parsed.data);
  if (!course) return res.status(404).json({ error: "Курс не найден" });
  res.status(201).json({ course });
});

builderRouter.post("/courses/:courseId/lessons/reorder", async (req, res) => {
  const parsed = reorderSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректный порядок") });
  const course = await reorderLessons(req.params.courseId, parsed.data.ids);
  if (!course) return res.status(400).json({ error: "Список уроков не совпадает с курсом" });
  res.json({ course });
});

builderRouter.patch("/courses/:courseId/lessons/:lessonId", async (req, res) => {
  const parsed = lessonInputSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные урока") });
  const course = await updateLesson(req.params.courseId, req.params.lessonId, parsed.data);
  if (!course) return res.status(404).json({ error: "Урок не найден" });
  res.json({ course });
});

builderRouter.delete("/courses/:courseId/lessons/:lessonId", async (req, res) => {
  const course = await deleteLesson(req.params.courseId, req.params.lessonId);
  if (!course) return res.status(404).json({ error: "Урок не найден" });
  res.json({ course });
});

// ---------------------------------------------------------------------------
// Lesson media
// ---------------------------------------------------------------------------

const mediaKindSchema = z.enum(["video", "audio"]);

builderRouter.post(
  "/courses/:courseId/lessons/:lessonId/media",
  uploadCourseMedia.single("file"),
  async (req, res) => {
    const kind = mediaKindSchema.safeParse(req.body?.kind);
    if (!kind.success) return res.status(400).json({ error: "Укажите тип файла: video или audio" });
    if (!req.file) return res.status(400).json({ error: "Файл не получен" });

    const course = await setLessonMedia(
      req.params.courseId,
      req.params.lessonId,
      kind.data,
      `/uploads/courses/${req.file.filename}`,
    );
    if (!course) return res.status(404).json({ error: "Урок не найден" });
    res.json({ course });
  },
);

builderRouter.delete("/courses/:courseId/lessons/:lessonId/media", async (req, res) => {
  const kind = mediaKindSchema.safeParse(req.query.kind);
  if (!kind.success) return res.status(400).json({ error: "Укажите тип файла: video или audio" });

  const existing = await getCourse(req.params.courseId);
  const lesson = existing?.lessons.find((l) => l.id === req.params.lessonId);
  if (!lesson) return res.status(404).json({ error: "Урок не найден" });

  const url = kind.data === "video" ? lesson.videoUrl : lesson.audioUrl;
  if (url) fs.unlink(path.join(COURSE_MEDIA_DIR, path.basename(url))).catch(() => {});

  const course = await setLessonMedia(req.params.courseId, req.params.lessonId, kind.data, null);
  res.json({ course });
});

// ---------------------------------------------------------------------------
// Lesson vocabulary and questions
// ---------------------------------------------------------------------------

builderRouter.post("/courses/:courseId/lessons/:lessonId/vocabulary", async (req, res) => {
  const parsed = vocabularyWordInputSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректное слово") });

  try {
    const result = await addVocabularyWord(req.params.courseId, req.params.lessonId, parsed.data);
    if (!result) return res.status(404).json({ error: "Урок не найден" });
    res.status(201).json(result);
  } catch (e) {
    if (e instanceof DuplicateWordError) return res.status(409).json({ error: e.message });
    throw e;
  }
});

builderRouter.patch("/courses/:courseId/lessons/:lessonId/vocabulary/:wordId", async (req, res) => {
  const parsed = vocabularyWordInputSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректное слово") });

  try {
    const result = await updateVocabularyWord(req.params.courseId, req.params.lessonId, req.params.wordId, parsed.data);
    if (!result) return res.status(404).json({ error: "Слово не найдено" });
    res.json(result);
  } catch (e) {
    if (e instanceof DuplicateWordError) return res.status(409).json({ error: e.message });
    throw e;
  }
});

builderRouter.delete("/courses/:courseId/lessons/:lessonId/vocabulary/:wordId", async (req, res) => {
  const result = await deleteVocabularyWord(req.params.courseId, req.params.lessonId, req.params.wordId);
  if (!result) return res.status(404).json({ error: "Слово не найдено" });
  res.json(result);
});

builderRouter.post(
  "/courses/:courseId/lessons/:lessonId/vocabulary/:wordId/audio",
  uploadWordAudio.single("audio"),
  async (req, res) => {
    if (!req.file) return res.status(400).json({ error: "Файл не получен" });
    const audioUrl = `/uploads/words/${req.file.filename}`;
    const result = await setVocabularyWordAudio(req.params.courseId, req.params.lessonId, req.params.wordId, audioUrl);
    if (!result) {
      await fs.unlink(path.join(WORD_AUDIO_DIR, req.file.filename)).catch(() => {});
      return res.status(404).json({ error: "Слово не найдено" });
    }
    if (result.previousAudioUrl) {
      fs.unlink(path.join(WORD_AUDIO_DIR, path.basename(result.previousAudioUrl))).catch(() => {});
    }
    res.json({ ok: true, audioUrl });
  },
);

builderRouter.delete("/courses/:courseId/lessons/:lessonId/vocabulary/:wordId/audio", async (req, res) => {
  const result = await setVocabularyWordAudio(req.params.courseId, req.params.lessonId, req.params.wordId, null);
  if (!result) return res.status(404).json({ error: "Слово не найдено" });
  if (result.previousAudioUrl) {
    fs.unlink(path.join(WORD_AUDIO_DIR, path.basename(result.previousAudioUrl))).catch(() => {});
  }
  res.json({ ok: true });
});

// Dry run: validates a JSON word list against the whole course without
// writing anything, for the builder's "Проверить JSON" preview button.
builderRouter.post("/courses/:courseId/lessons/:lessonId/vocabulary/import/preview", async (req, res) => {
  const parsed = vocabularyImportPayloadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректный формат JSON") });

  const preview = await previewVocabularyImport(req.params.courseId, req.params.lessonId, parsed.data.words);
  if (!preview) return res.status(404).json({ error: "Урок не найден" });
  res.json({ preview });
});

builderRouter.post("/courses/:courseId/lessons/:lessonId/vocabulary/import", async (req, res) => {
  const parsed = vocabularyImportPayloadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректный формат JSON") });

  try {
    const result = await importVocabularyWords(req.params.courseId, req.params.lessonId, parsed.data.words);
    if (!result) return res.status(404).json({ error: "Урок не найден" });
    res.status(201).json(result);
  } catch (e) {
    if (e instanceof DuplicateWordError) return res.status(409).json({ error: e.message });
    throw e;
  }
});

builderRouter.put("/courses/:courseId/lessons/:lessonId/questions", async (req, res) => {
  const parsed = questionsPayloadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные вопросы") });

  const course = await saveLessonQuestions(req.params.courseId, req.params.lessonId, parsed.data.questions);
  if (!course) return res.status(404).json({ error: "Урок не найден" });
  res.json({ course });
});

// ---------------------------------------------------------------------------
// Question blocks inside a stage (several mini-tests, practice blocks, etc.)
// ---------------------------------------------------------------------------

builderRouter.post("/courses/:courseId/lessons/:lessonId/blocks", async (req, res) => {
  const parsed = blockInputSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные блока") });
  const result = await createBlock(req.params.courseId, req.params.lessonId, parsed.data);
  if (!result) return res.status(404).json({ error: "Урок не найден" });
  res.status(201).json(result);
});

builderRouter.post("/courses/:courseId/lessons/:lessonId/blocks/reorder", async (req, res) => {
  const stage = z.enum(["minitest", "practice", "review"]).safeParse(req.body?.stage);
  const parsed = reorderSchema.safeParse(req.body);
  if (!stage.success) return res.status(400).json({ error: "Укажите этап" });
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректный порядок") });

  const result = await reorderBlocks(req.params.courseId, req.params.lessonId, stage.data, parsed.data.ids);
  if (!result) return res.status(400).json({ error: "Список блоков не совпадает с этапом" });
  res.json(result);
});

builderRouter.patch("/courses/:courseId/lessons/:lessonId/blocks/:blockId", async (req, res) => {
  const title = z.string().trim().min(1, "Название блока не может быть пустым").max(200).safeParse(req.body?.title);
  if (!title.success) return res.status(400).json({ error: firstIssue(title.error, "Некорректное название") });

  const result = await updateBlock(req.params.courseId, req.params.lessonId, req.params.blockId, title.data);
  if (!result) return res.status(404).json({ error: "Блок не найден" });
  res.json(result);
});

builderRouter.delete("/courses/:courseId/lessons/:lessonId/blocks/:blockId", async (req, res) => {
  const result = await deleteBlock(req.params.courseId, req.params.lessonId, req.params.blockId);
  if (!result) return res.status(404).json({ error: "Блок не найден" });
  res.json(result);
});

builderRouter.put("/courses/:courseId/lessons/:lessonId/blocks/:blockId/questions", async (req, res) => {
  const parsed = blockQuestionsPayloadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные вопросы") });

  const result = await saveBlockQuestions(
    req.params.courseId,
    req.params.lessonId,
    req.params.blockId,
    parsed.data.questions,
  );
  if (!result) return res.status(404).json({ error: "Блок не найден" });
  res.json(result);
});
