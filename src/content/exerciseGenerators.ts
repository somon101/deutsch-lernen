import { AuthoredQuestion, LessonContent, PhraseEntry, VocabularyEntry } from "./types";
import { answersMatch, cleanQuizText, hashString, normalizeAnswer, pickN, seededRandom, shuffle } from "./textUtils";
import { exercisesForStage } from "./questionMapping";
import {
  ChoiceQuestion,
  ClozeExercise,
  Exercise,
  LessonExerciseSets,
  MatchExercise,
  ScrambleExercise,
  TrueFalseQuestion,
} from "./exercises";

interface Pair {
  german: string;
  translation: string;
}

function pool(content: LessonContent): Pair[] {
  const seen = new Set<string>();
  const items: Pair[] = [];
  // Vocabulary entries come first so the curated spelling ("Hallo") wins over
  // a material phrase that writes the same word with different punctuation
  // ("Hallo!") — the dedup key below is normalized (case/punctuation-
  // insensitive) so those two are recognised as the same word and only the
  // first is kept, instead of both ending up as separate quiz options.
  for (const entry of [...content.vocabulary, ...content.phrases] as (VocabularyEntry | PhraseEntry)[]) {
    const key = `${normalizeAnswer(entry.german)}::${normalizeAnswer(entry.translation)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    // Cleaned here too (phrases are already clean at the source, vocabulary
    // isn't) so no quiz option/distractor built from this pool can carry a
    // stray trailing mark that hints at correctness.
    items.push({ german: cleanQuizText(entry.german), translation: cleanQuizText(entry.translation) });
  }
  return items;
}

function buildChoiceQuestions(items: Pair[], count: number, seed: number, idPrefix: string): ChoiceQuestion[] {
  if (items.length < 2) return [];
  const rand = seededRandom(seed);
  const ordered = shuffle(items, rand);
  const questions: ChoiceQuestion[] = [];

  for (let i = 0; i < count && i < ordered.length; i++) {
    const item = ordered[i];
    const germanToRussian = i % 2 === 0;
    const prompt = germanToRussian
      ? `Как переводится «${item.german}»?`
      : `Как будет по-немецки «${item.translation}»?`;
    const correct = germanToRussian ? item.translation : item.german;

    // Distractors are excluded both against the correct answer and against
    // each other by normalized value, so two options that would grade as the
    // same answer (differing only by case/punctuation) never appear
    // together — the raw, as-written text is still what's displayed.
    const correctKey = normalizeAnswer(correct);
    const seenDistractorKeys = new Set<string>();
    const distractorValues = items
      .filter((other) => other !== item)
      .map((other) => (germanToRussian ? other.translation : other.german))
      .filter((value) => {
        const valueKey = normalizeAnswer(value);
        if (valueKey === correctKey || seenDistractorKeys.has(valueKey)) return false;
        seenDistractorKeys.add(valueKey);
        return true;
      });

    const distractors = pickN(distractorValues, Math.min(3, distractorValues.length), rand);
    // Order here doesn't matter — the view component re-shuffles on every
    // attempt so the correct answer's position isn't memorizable.
    const options = [correct, ...distractors];

    questions.push({
      kind: "choice",
      id: `${idPrefix}-choice-${i}`,
      prompt,
      options,
      correctAnswer: correct,
    });
  }

  return questions;
}

function buildTrueFalseQuestions(items: Pair[], count: number, seed: number, idPrefix: string): TrueFalseQuestion[] {
  if (items.length < 2) return [];
  const rand = seededRandom(seed);
  const ordered = shuffle(items, rand);
  const questions: TrueFalseQuestion[] = [];

  for (let i = 0; i < count && i < ordered.length; i++) {
    const item = ordered[i];
    const isTrue = rand() < 0.5;
    let shownTranslation = item.translation;

    if (!isTrue) {
      // Compared by normalized value so a translation that only differs by
      // case/punctuation from the correct one is never offered as the
      // "wrong" statement — that would make the statement arguably true.
      const others = items.filter((other) => !answersMatch(other.translation, item.translation));
      if (others.length === 0) continue;
      shownTranslation = pickN(others, 1, rand)[0].translation;
    }

    questions.push({
      kind: "truefalse",
      id: `${idPrefix}-tf-${i}`,
      statement: `«${item.german}» переводится как «${shownTranslation}»`,
      correct: isTrue,
      explanation: `Правильный перевод «${item.german}» — «${item.translation}».`,
    });
  }

  return questions;
}

function buildMatchExercises(items: Pair[], size: number, seed: number, idPrefix: string): MatchExercise[] {
  if (items.length < 3) return [];
  const rand = seededRandom(seed);
  const chosen = pickN(items, Math.min(size, items.length), rand);

  return [
    {
      kind: "match",
      id: `${idPrefix}-match-0`,
      pairs: chosen.map((item, i) => ({
        id: `${idPrefix}-match-0-${i}`,
        left: item.german,
        right: item.translation,
      })),
    },
  ];
}

function tokenize(text: string): string[] {
  return text.split(/\s+/).filter(Boolean);
}

function buildScrambleExercises(phrases: PhraseEntry[], count: number, seed: number, idPrefix: string): ScrambleExercise[] {
  const rand = seededRandom(seed);
  const candidates = phrases.filter((p) => tokenize(p.german).length >= 2);
  const chosen = pickN(candidates, Math.min(count, candidates.length), rand);

  return chosen.map((phrase, i) => {
    const answer = tokenize(phrase.german);
    let tokens = shuffle(answer, rand);
    let attempts = 0;
    while (tokens.join(" ") === answer.join(" ") && attempts < 5) {
      tokens = shuffle(answer, rand);
      attempts++;
    }
    return {
      kind: "scramble" as const,
      id: `${idPrefix}-scramble-${i}`,
      translation: phrase.translation,
      tokens,
      answer,
    };
  });
}

function buildClozeExercises(phrases: PhraseEntry[], vocabWords: string[], count: number, seed: number, idPrefix: string): ClozeExercise[] {
  const rand = seededRandom(seed);
  const candidates = phrases.filter((p) => tokenize(p.german).length >= 2);
  const chosen = pickN(candidates, Math.min(count, candidates.length), rand);

  return chosen.map((phrase, i) => {
    const tokens = tokenize(phrase.german);
    const blankIndex = Math.floor(rand() * tokens.length);
    const answer = tokens[blankIndex];

    const otherWords = [
      ...tokens.filter((_, idx) => idx !== blankIndex),
      ...vocabWords,
    ].filter((w) => !answersMatch(w, answer));
    // Deduped by normalized value (not raw text) so e.g. "Hallo" from the
    // sentence and "hallo" from the vocabulary list don't both end up as
    // separate options for the same blank.
    const seenOtherKeys = new Set<string>();
    const uniqueOthers = otherWords.filter((w) => {
      const wKey = normalizeAnswer(w);
      if (seenOtherKeys.has(wKey)) return false;
      seenOtherKeys.add(wKey);
      return true;
    });
    const distractors = pickN(uniqueOthers, Math.min(3, uniqueOthers.length), rand);
    const options = shuffle([answer, ...distractors], rand);

    return {
      kind: "cloze" as const,
      id: `${idPrefix}-cloze-${i}`,
      translation: phrase.translation,
      before: tokens.slice(0, blankIndex).join(" "),
      after: tokens.slice(blankIndex + 1).join(" "),
      options,
      answer,
    };
  });
}

/** Converts admin-authored questions into the exercise shapes the runner
 * already understands. A stage's named blocks (any of the 5 kinds — same
 * mechanism the course builder uses) win when present; the old flat,
 * choice-only list is only a fallback for anything that predates blocks. */
function authoredFor(content: LessonContent, setName: AuthoredQuestion["setName"]): Exercise[] {
  const blockExercises = exercisesForStage(content.blocks, setName);
  if (blockExercises.length > 0) return blockExercises;

  return content.authoredQuestions
    .filter((q) => q.setName === setName)
    .map((q, i) => ({
      kind: "choice" as const,
      id: `${setName}-authored-${i}`,
      prompt: q.prompt,
      options: q.options,
      correctAnswer: q.correctAnswer,
    }));
}

export function buildLessonExercises(content: LessonContent): LessonExerciseSets {
  const items = pool(content);
  const vocabWords = content.vocabulary.map((v) => cleanQuizText(v.german));

  // A stage that has admin-authored questions uses exactly those; otherwise
  // it is generated as it always was.
  const authoredMiniTest = authoredFor(content, "minitest");
  const authoredPractice = authoredFor(content, "practice");
  const authoredReview = authoredFor(content, "review");

  const miniTestSeed = hashString(`${content.id}:minitest`);
  const generatedMiniTest: Exercise[] = [
    ...buildChoiceQuestions(items, 4, miniTestSeed, "minitest"),
    ...buildTrueFalseQuestions(items, 2, miniTestSeed + 1, "minitest"),
  ];

  const practiceSeed = hashString(`${content.id}:practice`);
  const generatedPractice: Exercise[] = [
    ...buildChoiceQuestions(items, 6, practiceSeed, "practice"),
    ...buildClozeExercises(content.phrases, vocabWords, 4, practiceSeed + 1, "practice"),
    ...buildScrambleExercises(content.phrases, 4, practiceSeed + 2, "practice"),
    ...buildMatchExercises(items, 8, practiceSeed + 3, "practice"),
    ...buildTrueFalseQuestions(items, 4, practiceSeed + 4, "practice"),
  ];

  const reviewSeed = hashString(`${content.id}:review`);
  const generatedReview: Exercise[] = buildChoiceQuestions(items, items.length, reviewSeed, "review");

  return {
    miniTest: authoredMiniTest.length > 0 ? authoredMiniTest : generatedMiniTest,
    practice: authoredPractice.length > 0 ? authoredPractice : generatedPractice,
    review: authoredReview.length > 0 ? authoredReview : generatedReview,
  };
}
