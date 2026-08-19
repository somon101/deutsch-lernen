import { BuilderCourseLesson } from "./learnerCourses";
import { parseLessonText } from "./parseLessonText";
import { exercisesForStage } from "./questionMapping";
import { LessonContent, VocabularyEntry } from "./types";
import { LessonExerciseSets } from "./exercises";

/**
 * Adapts a builder-authored lesson into the exact LessonContent shape the
 * existing stage components (VocabularyStage, MaterialStage, VideoStage,
 * AudioStage) already render — so they're reused completely unchanged for
 * builder courses, same as the file-based one.
 */
export function toLessonContent(lesson: BuilderCourseLesson): LessonContent {
  const parsed = lesson.materialText ? parseLessonText(lesson.materialText) : { blocks: [], phrases: [] };

  const vocabulary: VocabularyEntry[] = lesson.vocabulary.map((w) => ({
    id: w.id,
    german: w.german,
    translation: w.translation,
    pronunciation: w.pronunciation ?? undefined,
    audioUrl: w.audioUrl ?? undefined,
  }));

  return {
    id: lesson.id,
    title: lesson.title,
    vocabulary,
    // No filtering needed here: the builder already refuses to let the same
    // word be added twice within a course (course-wide uniqueness check on
    // save), so a builder lesson's word list can never contain a word
    // already taught earlier in the same course.
    newVocabulary: vocabulary,
    material: parsed.blocks,
    phrases: parsed.phrases,
    assets: {
      video: lesson.videoUrl ? { url: lesson.videoUrl, name: "Видео" } : undefined,
      audio: lesson.audioUrl ? { url: lesson.audioUrl, name: "Аудио" } : undefined,
      images: [],
    },
    extraTextFiles: [],
    // Empty content isn't an error here — every stage component already
    // falls back to a "skip this stage" screen on its own when its data is
    // missing, so there's nothing extra to report.
    missing: [],
    materialText: lesson.materialText,
    authoredQuestions: [],
    blocks: lesson.blocks,
    hasContentOverrides: true,
  };
}

export function buildBuilderLessonExercises(lesson: BuilderCourseLesson): LessonExerciseSets {
  return {
    miniTest: exercisesForStage(lesson.blocks, "minitest"),
    practice: exercisesForStage(lesson.blocks, "practice"),
    review: exercisesForStage(lesson.blocks, "review"),
  };
}
