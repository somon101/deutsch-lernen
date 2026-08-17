export interface ChoiceQuestion {
  kind: "choice";
  id: string;
  prompt: string;
  options: string[];
  /** The correct option's value — identifies correctness by content, not by
   * array position, so option order can be shuffled safely on every attempt. */
  correctAnswer: string;
}

export interface TrueFalseQuestion {
  kind: "truefalse";
  id: string;
  statement: string;
  correct: boolean;
  explanation: string;
}

export interface MatchExercise {
  kind: "match";
  id: string;
  pairs: { id: string; left: string; right: string }[];
}

export interface ScrambleExercise {
  kind: "scramble";
  id: string;
  translation: string;
  tokens: string[];
  answer: string[];
}

export interface ClozeExercise {
  kind: "cloze";
  id: string;
  translation: string;
  before: string;
  after: string;
  options: string[];
  answer: string;
}

export type Exercise =
  | ChoiceQuestion
  | TrueFalseQuestion
  | MatchExercise
  | ScrambleExercise
  | ClozeExercise;

export interface LessonExerciseSets {
  miniTest: Exercise[];
  practice: Exercise[];
  review: Exercise[];
}
