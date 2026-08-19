import { BuilderQuestion } from "../admin/builderApi";
import { shuffle } from "./textUtils";
import { ChoiceQuestion, ClozeExercise, Exercise, MatchExercise, ScrambleExercise, TrueFalseQuestion } from "./exercises";

function explanationFor(prompt: string, correct: boolean): string {
  return correct ? `Утверждение верно: «${prompt}»` : `Утверждение неверно: «${prompt}»`;
}

/** Splits a cloze prompt like "Ich ___ aus Deutschland." into its two
 * halves. Validated server-side to contain exactly one blank marker. */
function splitBlank(prompt: string): { before: string; after: string } {
  const [before = "", after = ""] = prompt.split("___");
  return { before: before.trim(), after: after.trim() };
}

/**
 * Converts one admin-authored question (any of the 5 kinds, from either the
 * course builder or a legacy lesson's blocks — same shape either way) into
 * the Exercise type ExerciseRunner already knows how to render and grade.
 * The one place this mapping lives, shared by builderExercises.ts and
 * exerciseGenerators.ts so neither reimplements it.
 */
export function toExercise(q: BuilderQuestion, id: string): Exercise {
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

interface BlockLike {
  id: string;
  stage: string;
  position: number;
  questions: BuilderQuestion[];
}

/** Flattens a stage's named blocks (ordered by block position, then question
 * position) into the flat exercise list ExerciseRunner expects. */
export function exercisesForStage(blocks: BlockLike[], stage: string): Exercise[] {
  return blocks
    .filter((b) => b.stage === stage)
    .sort((a, b) => a.position - b.position)
    .flatMap((block) => block.questions.map((q, i) => toExercise(q, `${block.id}-${i}`)));
}
