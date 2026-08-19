import { BuilderCourseLesson } from "./learnerCourses";
import { parseLessonText } from "./parseLessonText";
import { shuffle } from "./textUtils";
import { LessonContent, VocabularyEntry } from "./types";
import { ChoiceQuestion, ClozeExercise, Exercise, LessonExerciseSets, MatchExercise, ScrambleExercise, TrueFalseQuestion } from "./exercises";

/**
 * Adapts a builder-authored lesson into the exact LessonContent shape the
 * existing stage components (VocabularyStage, MaterialStage, VideoStage,
 * AudioStage) already render — so they're reused completely unchanged for
 * builder courses, same as the file-based one.
 */
export function toLessonContent(lesson: BuilderCourseLesson): LessonContent {
  const parsed = lesson.materialText ? parseLessonText(lesson.materialText) : { blocks: [], phrases: [] };

  const vocabulary: VocabularyEntry[] = lesson.vocabulary.map((w, index) => ({
    id: `${lesson.id}-vocab-${index}`,
    german: w.german,
    translation: w.translation,
    pronunciation: w.pronunciation ?? undefined,
    audioUrl: w.audioUrl ?? undefined,
  }));

  return {
    id: lesson.id,
    title: lesson.title,
    vocabulary,
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
    hasContentOverrides: true,
  };
}

function explanationFor(prompt: string, correct: boolean): string {
  return correct ? `Утверждение верно: «${prompt}»` : `Утверждение неверно: «${prompt}»`;
}

/** Splits a cloze prompt like "Ich ___ aus Deutschland." into its two
 * halves. Validated server-side to contain exactly one blank marker. */
function splitBlank(prompt: string): { before: string; after: string } {
  const [before = "", after = ""] = prompt.split("___");
  return { before: before.trim(), after: after.trim() };
}

function toExercise(q: BuilderCourseLesson["blocks"][number]["questions"][number], id: string): Exercise {
  switch (q.kind) {
    case "choice":
      return { kind: "choice", id, prompt: q.prompt, options: q.options, correctAnswer: q.correctAnswer } satisfies ChoiceQuestion;
    case "truefalse":
      return {
        kind: "truefalse",
        id,
        statement: q.prompt,
        correct: q.correct,
        explanation: explanationFor(q.prompt, q.correct),
      } satisfies TrueFalseQuestion;
    case "cloze": {
      const { before, after } = splitBlank(q.prompt);
      return { kind: "cloze", id, translation: "", before, after, options: q.options, answer: q.correctAnswer } satisfies ClozeExercise;
    }
    case "scramble":
      return {
        kind: "scramble",
        id,
        translation: q.prompt,
        tokens: shuffle(q.options, Math.random),
        answer: q.correctAnswer.split(" ").filter(Boolean),
      } satisfies ScrambleExercise;
    case "match":
      return {
        kind: "match",
        id,
        pairs: q.pairs.map((p, i) => ({ id: `${id}-${i}`, left: p.left, right: p.right })),
      } satisfies MatchExercise;
  }
}

/** Flattens a stage's named blocks (already ordered by block position, then
 * question position) into the flat exercise list ExerciseRunner expects. */
function exercisesFor(lesson: BuilderCourseLesson, stage: "minitest" | "practice" | "review"): Exercise[] {
  return lesson.blocks
    .filter((b) => b.stage === stage)
    .sort((a, b) => a.position - b.position)
    .flatMap((block) => block.questions.map((q, i) => toExercise(q, `${block.id}-${i}`)));
}

export function buildBuilderLessonExercises(lesson: BuilderCourseLesson): LessonExerciseSets {
  return {
    miniTest: exercisesFor(lesson, "minitest"),
    practice: exercisesFor(lesson, "practice"),
    review: exercisesFor(lesson, "review"),
  };
}
