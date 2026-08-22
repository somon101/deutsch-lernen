import { useEffect, useState } from "react";
import { BuilderBlock, BuilderQuestion, builderApi } from "../../admin/builderApi";
import DragList from "./DragList";

type QuestionKind = BuilderQuestion["kind"];

/** Draft shape used while editing — choice/cloze track the correct option by
 * index (so retyping option text can't silently change which one is marked
 * correct), and scramble keeps the admin's typed phrase separate from the
 * extra decoy words so both can be edited independently. `id` exists only
 * client-side (drag identity for DragList) and is never sent to the server -
 * toSaved() below drops it along with the rest of the editing-only shape. */
type EditableQuestionBase =
  | { kind: "choice"; prompt: string; options: string[]; correctIndex: number }
  | { kind: "cloze"; prompt: string; options: string[]; correctIndex: number }
  | { kind: "truefalse"; prompt: string; correct: boolean }
  | { kind: "scramble"; prompt: string; correctPhrase: string; extraWords: string[] }
  | { kind: "match"; prompt: string; pairs: { left: string; right: string }[] };

type EditableQuestion = EditableQuestionBase & { id: string };

function newQuestionId(): string {
  return crypto.randomUUID();
}

const KIND_LABELS: Record<QuestionKind, string> = {
  choice: "Вопрос с вариантами",
  truefalse: "Верно / Неверно",
  cloze: "Пропущенное слово",
  scramble: "Собери фразу",
  match: "Сопоставление",
};

function tokenize(text: string): string[] {
  return text.trim().split(/\s+/).filter(Boolean);
}

function emptyQuestion(kind: QuestionKind): EditableQuestion {
  const base = ((): EditableQuestionBase => {
    switch (kind) {
      case "choice":
        return { kind: "choice", prompt: "", options: ["", ""], correctIndex: 0 };
      case "cloze":
        return { kind: "cloze", prompt: "", options: ["", ""], correctIndex: 0 };
      case "truefalse":
        return { kind: "truefalse", prompt: "", correct: true };
      case "scramble":
        return { kind: "scramble", prompt: "", correctPhrase: "", extraWords: [] };
      case "match":
        return {
          kind: "match",
          prompt: "",
          pairs: [
            { left: "", right: "" },
            { left: "", right: "" },
          ],
        };
    }
  })();
  return { ...base, id: newQuestionId() } as EditableQuestion;
}

function toEditable(q: BuilderQuestion): EditableQuestion {
  const base = ((): EditableQuestionBase => {
    switch (q.kind) {
      case "choice":
        return { kind: "choice", prompt: q.prompt, options: q.options, correctIndex: Math.max(0, q.options.indexOf(q.correctAnswer)) };
      case "cloze":
        return { kind: "cloze", prompt: q.prompt, options: q.options, correctIndex: Math.max(0, q.options.indexOf(q.correctAnswer)) };
      case "truefalse":
        return { kind: "truefalse", prompt: q.prompt, correct: q.correct };
      case "scramble": {
        const correctTokens = tokenize(q.correctAnswer);
        const extraWords = [...q.options];
        for (const token of correctTokens) {
          const idx = extraWords.indexOf(token);
          if (idx !== -1) extraWords.splice(idx, 1);
        }
        return { kind: "scramble", prompt: q.prompt, correctPhrase: q.correctAnswer, extraWords };
      }
      case "match":
        return {
          kind: "match",
          prompt: q.prompt,
          pairs: q.pairs.length > 0 ? q.pairs : [{ left: "", right: "" }, { left: "", right: "" }],
        };
    }
  })();
  return { ...base, id: newQuestionId() } as EditableQuestion;
}

function toSaved(q: EditableQuestion): BuilderQuestion {
  switch (q.kind) {
    case "choice":
      return { kind: "choice", prompt: q.prompt, options: q.options, correctAnswer: q.options[q.correctIndex] ?? "" };
    case "cloze":
      return { kind: "cloze", prompt: q.prompt, options: q.options, correctAnswer: q.options[q.correctIndex] ?? "" };
    case "truefalse":
      return { kind: "truefalse", prompt: q.prompt, correct: q.correct };
    case "scramble": {
      const correctTokens = tokenize(q.correctPhrase);
      return { kind: "scramble", prompt: q.prompt, options: [...correctTokens, ...q.extraWords], correctAnswer: correctTokens.join(" ") };
    }
    case "match":
      return { kind: "match", prompt: q.prompt, pairs: q.pairs };
  }
}

/** One named block of questions inside a stage ("Мини-тест 1", "Практика 2", …). */
export default function BuilderBlockEditor({
  courseId,
  lessonId,
  block,
  busy,
  saved,
  onRun,
}: {
  courseId: string;
  lessonId: string;
  block: BuilderBlock;
  busy: string | null;
  saved: string | null;
  onRun: (key: string, action: () => Promise<unknown>) => Promise<void>;
}) {
  const [title, setTitle] = useState(block.title);
  const [questions, setQuestions] = useState<EditableQuestion[]>([]);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    setTitle(block.title);
    setQuestions(block.questions.map(toEditable));
  }, [block]);

  const key = (name: string) => `${name}-${block.id}`;
  const update = (qi: number, patch: (q: EditableQuestion) => EditableQuestion) =>
    setQuestions((qs) => qs.map((r, x) => (x === qi ? patch(r) : r)));

  const addQuestion = (kind: QuestionKind) => setQuestions((qs) => [...qs, emptyQuestion(kind)]);
  const reorderQuestions = (ids: string[]) => {
    const byId = new Map(questions.map((q) => [q.id, q]));
    setQuestions(ids.map((id) => byId.get(id)!));
  };

  return (
    <div className="builder-block">
      <div className="builder-block__head">
        <button type="button" className="builder-block__toggle" onClick={() => setOpen(!open)}>
          {open ? "▾" : "▸"} {block.title}
          <span className="builder-block__count">{block.questions.length} вопросов</span>
        </button>
        <div className="builder-order">
          <button
            type="button"
            className="btn btn-ghost admin-row__remove"
            onClick={() => {
              if (window.confirm(`Удалить «${block.title}» вместе с вопросами?`)) {
                onRun(key("remove"), () => builderApi.removeBlock(courseId, lessonId, block.id));
              }
            }}
          >
            Удалить
          </button>
        </div>
      </div>

      {open && (
        <div className="builder-block__body">
          <div className="builder-block__rename">
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Название блока" />
            <button
              type="button"
              className="btn btn-secondary"
              disabled={busy === key("rename")}
              onClick={() => onRun(key("rename"), () => builderApi.renameBlock(courseId, lessonId, block.id, title))}
            >
              Переименовать
            </button>
          </div>

          <DragList
            items={questions}
            onReorder={reorderQuestions}
            renderItem={(q, qi) => (
            <div className="admin-question">
              <div className="admin-question__head">
                <span className="admin-question__hint">
                  Задание {qi + 1} · {KIND_LABELS[q.kind]}
                </span>
                <div className="builder-order">
                  <button
                    type="button"
                    className="btn btn-ghost admin-row__remove"
                    onClick={() => setQuestions((qs) => qs.filter((r) => r.id !== q.id))}
                  >
                    Удалить
                  </button>
                </div>
              </div>

              {(q.kind === "choice" || q.kind === "cloze") && (
                <>
                  <label className="auth-field">
                    <span>{q.kind === "cloze" ? "Фраза с пропуском (отметьте его как ___)" : "Текст вопроса"}</span>
                    <input
                      value={q.prompt}
                      placeholder={q.kind === "cloze" ? "Ich ___ aus Deutschland." : "Что значит «Hallo»?"}
                      onChange={(e) => update(qi, (r) => ({ ...r, prompt: e.target.value }))}
                    />
                  </label>

                  <span className="admin-question__hint">Отметьте правильный вариант:</span>
                  {q.options.map((option, oi) => (
                    <div className="admin-option" key={oi}>
                      <input
                        type="radio"
                        name={`correct-${block.id}-${qi}`}
                        checked={q.correctIndex === oi}
                        onChange={() => update(qi, (r) => ({ ...r, correctIndex: oi }))}
                      />
                      <input
                        className="admin-option__text"
                        placeholder={`Вариант ${oi + 1}`}
                        value={option}
                        onChange={(e) =>
                          update(qi, (r) =>
                            r.kind === "choice" || r.kind === "cloze"
                              ? { ...r, options: r.options.map((o, y) => (y === oi ? e.target.value : o)) }
                              : r,
                          )
                        }
                      />
                      <button
                        type="button"
                        className="btn btn-ghost admin-row__remove"
                        disabled={q.options.length <= 2}
                        onClick={() =>
                          update(qi, (r) => {
                            if (r.kind !== "choice" && r.kind !== "cloze") return r;
                            const options = r.options.filter((_, y) => y !== oi);
                            let correctIndex = r.correctIndex;
                            if (oi === r.correctIndex) correctIndex = 0;
                            else if (oi < r.correctIndex) correctIndex -= 1;
                            return { ...r, options, correctIndex };
                          })
                        }
                      >
                        ✕
                      </button>
                    </div>
                  ))}
                  <button
                    type="button"
                    className="btn btn-secondary"
                    onClick={() =>
                      update(qi, (r) => (r.kind === "choice" || r.kind === "cloze" ? { ...r, options: [...r.options, ""] } : r))
                    }
                  >
                    + Вариант ответа
                  </button>
                </>
              )}

              {q.kind === "truefalse" && (
                <>
                  <label className="auth-field">
                    <span>Утверждение</span>
                    <input
                      value={q.prompt}
                      placeholder="Berlin ist die Hauptstadt von Deutschland."
                      onChange={(e) => update(qi, (r) => ({ ...r, prompt: e.target.value }))}
                    />
                  </label>
                  <div className="admin-option">
                    <label style={{ display: "flex", alignItems: "center", gap: 6 }}>
                      <input
                        type="radio"
                        name={`tf-${block.id}-${qi}`}
                        checked={q.correct === true}
                        onChange={() => update(qi, (r) => (r.kind === "truefalse" ? { ...r, correct: true } : r))}
                      />
                      Верно
                    </label>
                    <label style={{ display: "flex", alignItems: "center", gap: 6, marginLeft: 16 }}>
                      <input
                        type="radio"
                        name={`tf-${block.id}-${qi}`}
                        checked={q.correct === false}
                        onChange={() => update(qi, (r) => (r.kind === "truefalse" ? { ...r, correct: false } : r))}
                      />
                      Неверно
                    </label>
                  </div>
                </>
              )}

              {q.kind === "scramble" && (
                <>
                  <label className="auth-field">
                    <span>Перевод / инструкция</span>
                    <input
                      value={q.prompt}
                      placeholder="Я живу в Берлине."
                      onChange={(e) => update(qi, (r) => ({ ...r, prompt: e.target.value }))}
                    />
                  </label>
                  <label className="auth-field">
                    <span>Правильная фраза</span>
                    <input
                      value={q.correctPhrase}
                      placeholder="Ich wohne in Berlin."
                      onChange={(e) => update(qi, (r) => (r.kind === "scramble" ? { ...r, correctPhrase: e.target.value } : r))}
                    />
                  </label>

                  <span className="admin-question__hint">
                    Слова из фразы: {tokenize(q.correctPhrase).join(", ") || "—"} (ученик увидит их вперемешку)
                  </span>

                  {q.extraWords.length > 0 && (
                    <div className="admin-rows">
                      {q.extraWords.map((word, wi) => (
                        <div className="admin-row" key={wi}>
                          <input
                            placeholder="лишнее слово"
                            value={word}
                            onChange={(e) =>
                              update(qi, (r) =>
                                r.kind === "scramble"
                                  ? { ...r, extraWords: r.extraWords.map((w, y) => (y === wi ? e.target.value : w)) }
                                  : r,
                              )
                            }
                          />
                          <button
                            type="button"
                            className="btn btn-ghost admin-row__remove"
                            onClick={() => update(qi, (r) => (r.kind === "scramble" ? { ...r, extraWords: r.extraWords.filter((_, y) => y !== wi) } : r))}
                          >
                            Удалить
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                  <button
                    type="button"
                    className="btn btn-secondary"
                    onClick={() => update(qi, (r) => (r.kind === "scramble" ? { ...r, extraWords: [...r.extraWords, ""] } : r))}
                  >
                    + Лишнее слово
                  </button>
                </>
              )}

              {q.kind === "match" && (
                <>
                  <label className="auth-field">
                    <span>Инструкция (необязательно)</span>
                    <input
                      value={q.prompt}
                      placeholder="Сопоставьте слова и переводы"
                      onChange={(e) => update(qi, (r) => ({ ...r, prompt: e.target.value }))}
                    />
                  </label>
                  <span className="admin-question__hint">Пары (количество не ограничено, минимум 2):</span>
                  <div className="admin-rows">
                    {q.pairs.map((pair, pi) => (
                      <div className="admin-row" key={pi}>
                        <input
                          placeholder="Haus"
                          value={pair.left}
                          onChange={(e) =>
                            update(qi, (r) =>
                              r.kind === "match"
                                ? { ...r, pairs: r.pairs.map((p, y) => (y === pi ? { ...p, left: e.target.value } : p)) }
                                : r,
                            )
                          }
                        />
                        <input
                          placeholder="Дом"
                          value={pair.right}
                          onChange={(e) =>
                            update(qi, (r) =>
                              r.kind === "match"
                                ? { ...r, pairs: r.pairs.map((p, y) => (y === pi ? { ...p, right: e.target.value } : p)) }
                                : r,
                            )
                          }
                        />
                        <button
                          type="button"
                          className="btn btn-ghost admin-row__remove"
                          disabled={q.pairs.length <= 2}
                          onClick={() => update(qi, (r) => (r.kind === "match" ? { ...r, pairs: r.pairs.filter((_, y) => y !== pi) } : r))}
                        >
                          Удалить
                        </button>
                      </div>
                    ))}
                  </div>
                  <button
                    type="button"
                    className="btn btn-secondary"
                    onClick={() =>
                      update(qi, (r) => (r.kind === "match" ? { ...r, pairs: [...r.pairs, { left: "", right: "" }] } : r))
                    }
                  >
                    + Пара
                  </button>
                </>
              )}
            </div>
            )}
          />

          <div className="stage-footer split">
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
              <span className="admin-question__hint" style={{ width: "100%" }}>
                Добавить задание:
              </span>
              {(Object.keys(KIND_LABELS) as QuestionKind[]).map((kind) => (
                <button key={kind} type="button" className="btn btn-secondary" onClick={() => addQuestion(kind)}>
                  + {KIND_LABELS[kind]}
                </button>
              ))}
            </div>
            <span style={{ display: "flex", alignItems: "center", gap: 12 }}>
              {saved === key("questions") && <span className="admin-saved">Сохранено</span>}
              <button
                type="button"
                className="btn btn-primary"
                disabled={busy === key("questions")}
                onClick={() => onRun(key("questions"), () => builderApi.saveBlockQuestions(courseId, lessonId, block.id, questions.map(toSaved)))}
              >
                Сохранить вопросы
              </button>
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
