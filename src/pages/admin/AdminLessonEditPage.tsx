import { FormEvent, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, ApiError } from "../../auth/api";
import { invalidateLessonCache, loadLesson } from "../../content/loader";
import { AuthoredQuestion, LessonContent } from "../../content/types";

type SetName = AuthoredQuestion["setName"];

const SET_LABELS: Record<SetName, string> = {
  minitest: "Мини-тест",
  practice: "Практика",
  review: "Закрепление",
};

interface VocabRow {
  german: string;
  translation: string;
  pronunciation: string;
}

interface QuestionRow {
  setName: SetName;
  prompt: string;
  options: string[];
  correctIndex: number;
}

export default function AdminLessonEditPage() {
  const { lessonId = "" } = useParams();

  const [lesson, setLesson] = useState<LessonContent | null>(null);
  const [materialText, setMaterialText] = useState("");
  const [vocab, setVocab] = useState<VocabRow[]>([]);
  const [questions, setQuestions] = useState<QuestionRow[]>([]);

  const [saving, setSaving] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    invalidateLessonCache(lessonId);
    loadLesson(lessonId).then((content) => {
      if (cancelled) return;
      setLesson(content);
      setMaterialText(content.materialText);
      setVocab(
        content.vocabulary.map((v) => ({
          german: v.german,
          translation: v.translation,
          pronunciation: v.pronunciation ?? "",
        })),
      );
      setQuestions(
        content.authoredQuestions.map((q) => ({
          setName: q.setName,
          prompt: q.prompt,
          options: q.options,
          correctIndex: Math.max(0, q.options.indexOf(q.correctAnswer)),
        })),
      );
    });
    return () => {
      cancelled = true;
    };
  }, [lessonId]);

  const flash = (section: string) => {
    setSaved(section);
    setTimeout(() => setSaved((s) => (s === section ? null : s)), 2500);
  };

  const save = async (section: string, body: unknown) => {
    setError(null);
    setSaving(section);
    try {
      await api.put(`/api/admin/content/${encodeURIComponent(lessonId)}`, body);
      // Learners read through the same cache, so drop it to publish the change.
      invalidateLessonCache(lessonId);
      flash(section);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Не удалось сохранить изменения");
    } finally {
      setSaving(null);
    }
  };

  const saveMaterial = (e: FormEvent) => {
    e.preventDefault();
    save("material", { materialText });
  };

  const saveVocabulary = () =>
    save("vocabulary", {
      vocabulary: vocab.map((v) => ({
        german: v.german,
        translation: v.translation,
        pronunciation: v.pronunciation.trim() ? v.pronunciation : null,
      })),
    });

  const saveQuestions = () =>
    save("questions", {
      questions: questions.map((q) => ({
        setName: q.setName,
        prompt: q.prompt,
        options: q.options,
        correctAnswer: q.options[q.correctIndex] ?? "",
      })),
    });

  if (!lesson) {
    return (
      <div className="app-shell">
        <main className="home-main">
          <p className="stage-subtitle" style={{ textAlign: "center" }}>
            Загрузка урока…
          </p>
        </main>
      </div>
    );
  }

  const displayTitle = lesson.title.replace(/^\p{Extended_Pictographic}\s*/u, "");

  return (
    <div className="app-shell">
      <nav className="top-nav">
        <Link to="/" className="brand">
          <span className="brand-flag">🇩🇪</span> Deutsch Lernen
        </Link>
        <Link to="/admin/courses" className="btn btn-ghost">
          ← К урокам курса
        </Link>
      </nav>

      <main className="home-main">
        <div className="admin-layout">
          <p className="admin-breadcrumbs">
            <Link to="/admin/courses">Курсы</Link> → <Link to="/admin/courses">Немецкий с нуля</Link> → {displayTitle}
          </p>

          {error && <div className="exercise-feedback incorrect">{error}</div>}

          {/* ---------------- Material ---------------- */}
          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Материал урока
            </h2>
            <p className="stage-subtitle">
              Текст урока в том же формате, что и раньше: заголовок, строки «Шаг 1. …» и пары «Hallo! [ха́лло] — Привет!».
              Он разбирается тем же способом, что и файл урока.
            </p>
            <form className="auth-form" onSubmit={saveMaterial}>
              <textarea
                className="admin-textarea"
                rows={18}
                value={materialText}
                onChange={(e) => setMaterialText(e.target.value)}
              />
              <div className="stage-footer">
                {saved === "material" && <span className="admin-saved">Сохранено</span>}
                <button className="btn btn-primary" type="submit" disabled={saving === "material"}>
                  {saving === "material" ? "Сохраняем…" : "Сохранить материал"}
                </button>
              </div>
            </form>
          </section>

          {/* ---------------- Vocabulary ---------------- */}
          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Словарь ({vocab.length})
            </h2>
            <p className="stage-subtitle">Немецкое слово, перевод и, по желанию, произношение.</p>

            <div className="admin-rows">
              {vocab.map((row, i) => (
                <div className="admin-row" key={i}>
                  <input
                    aria-label="Немецкое слово"
                    placeholder="Hallo"
                    value={row.german}
                    onChange={(e) =>
                      setVocab((v) => v.map((r, idx) => (idx === i ? { ...r, german: e.target.value } : r)))
                    }
                  />
                  <input
                    aria-label="Перевод"
                    placeholder="привет"
                    value={row.translation}
                    onChange={(e) =>
                      setVocab((v) => v.map((r, idx) => (idx === i ? { ...r, translation: e.target.value } : r)))
                    }
                  />
                  <input
                    aria-label="Произношение"
                    placeholder="ха́лло"
                    value={row.pronunciation}
                    onChange={(e) =>
                      setVocab((v) => v.map((r, idx) => (idx === i ? { ...r, pronunciation: e.target.value } : r)))
                    }
                  />
                  <button
                    type="button"
                    className="btn btn-ghost admin-row__remove"
                    onClick={() => setVocab((v) => v.filter((_, idx) => idx !== i))}
                  >
                    Удалить
                  </button>
                </div>
              ))}
            </div>

            <div className="stage-footer split">
              <button
                type="button"
                className="btn btn-secondary"
                onClick={() => setVocab((v) => [...v, { german: "", translation: "", pronunciation: "" }])}
              >
                + Добавить слово
              </button>
              <span style={{ display: "flex", alignItems: "center", gap: 12 }}>
                {saved === "vocabulary" && <span className="admin-saved">Сохранено</span>}
                <button className="btn btn-primary" onClick={saveVocabulary} disabled={saving === "vocabulary"}>
                  {saving === "vocabulary" ? "Сохраняем…" : "Сохранить словарь"}
                </button>
              </span>
            </div>
          </section>

          {/* ---------------- Questions ---------------- */}
          <section className="profile-card">
            <h2 className="stage-title" style={{ fontSize: 20 }}>
              Вопросы ({questions.length})
            </h2>
            <p className="stage-subtitle">
              Пока для этапа не добавлено ни одного вопроса, он формируется автоматически из словаря — как и раньше. Как
              только вы добавите сюда вопрос, этап будет показывать именно ваши вопросы.
            </p>

            {questions.map((q, qi) => (
              <div className="admin-question" key={qi}>
                <div className="admin-question__head">
                  <select
                    value={q.setName}
                    onChange={(e) =>
                      setQuestions((qs) =>
                        qs.map((row, idx) => (idx === qi ? { ...row, setName: e.target.value as SetName } : row)),
                      )
                    }
                  >
                    {(Object.keys(SET_LABELS) as SetName[]).map((s) => (
                      <option key={s} value={s}>
                        {SET_LABELS[s]}
                      </option>
                    ))}
                  </select>
                  <button
                    type="button"
                    className="btn btn-ghost"
                    onClick={() => setQuestions((qs) => qs.filter((_, idx) => idx !== qi))}
                  >
                    Удалить вопрос
                  </button>
                </div>

                <label className="auth-field">
                  <span>Текст вопроса</span>
                  <input
                    placeholder="Как переводится «Hallo»?"
                    value={q.prompt}
                    onChange={(e) =>
                      setQuestions((qs) => qs.map((row, idx) => (idx === qi ? { ...row, prompt: e.target.value } : row)))
                    }
                  />
                </label>

                <span className="admin-question__hint">Отметьте правильный вариант:</span>
                {q.options.map((option, oi) => (
                  <div className="admin-option" key={oi}>
                    <input
                      type="radio"
                      name={`correct-${qi}`}
                      checked={q.correctIndex === oi}
                      onChange={() =>
                        setQuestions((qs) => qs.map((row, idx) => (idx === qi ? { ...row, correctIndex: oi } : row)))
                      }
                    />
                    <input
                      className="admin-option__text"
                      placeholder={`Вариант ${oi + 1}`}
                      value={option}
                      onChange={(e) =>
                        setQuestions((qs) =>
                          qs.map((row, idx) =>
                            idx === qi
                              ? { ...row, options: row.options.map((o, x) => (x === oi ? e.target.value : o)) }
                              : row,
                          ),
                        )
                      }
                    />
                    <button
                      type="button"
                      className="btn btn-ghost admin-row__remove"
                      disabled={q.options.length <= 2}
                      onClick={() =>
                        setQuestions((qs) =>
                          qs.map((row, idx) => {
                            if (idx !== qi) return row;
                            const options = row.options.filter((_, x) => x !== oi);
                            // Keep the same option marked correct after a removal.
                            let correctIndex = row.correctIndex;
                            if (oi === row.correctIndex) correctIndex = 0;
                            else if (oi < row.correctIndex) correctIndex -= 1;
                            return { ...row, options, correctIndex };
                          }),
                        )
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
                    setQuestions((qs) =>
                      qs.map((row, idx) => (idx === qi ? { ...row, options: [...row.options, ""] } : row)),
                    )
                  }
                >
                  + Вариант ответа
                </button>
              </div>
            ))}

            <div className="stage-footer split">
              <button
                type="button"
                className="btn btn-secondary"
                onClick={() =>
                  setQuestions((qs) => [
                    ...qs,
                    { setName: "minitest", prompt: "", options: ["", ""], correctIndex: 0 },
                  ])
                }
              >
                + Добавить вопрос
              </button>
              <span style={{ display: "flex", alignItems: "center", gap: 12 }}>
                {saved === "questions" && <span className="admin-saved">Сохранено</span>}
                <button className="btn btn-primary" onClick={saveQuestions} disabled={saving === "questions"}>
                  {saving === "questions" ? "Сохраняем…" : "Сохранить вопросы"}
                </button>
              </span>
            </div>
          </section>
        </div>
      </main>
    </div>
  );
}
