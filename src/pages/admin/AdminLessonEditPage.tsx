import { FormEvent, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { api, ApiError, API_URL } from "../../auth/api";
import { getAuthToken } from "../../auth/tokenStore";
import { canSynthesize, playWord, speakGerman } from "../../lib/speech";
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
  audioUrl: string | null;
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
          audioUrl: v.audioUrl ?? null,
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
        audioUrl: v.audioUrl,
      })),
    });

  // Audio is attached to a saved word, so the list must exist server-side first.
  const uploadAudio = async (index: number, file: File) => {
    const row = vocab[index];
    setError(null);
    setSaving(`audio-${index}`);
    try {
      const form = new FormData();
      form.append("audio", file);
      form.append("german", row.german);
      const res = await fetch(`${API_URL}/api/admin/content/${encodeURIComponent(lessonId)}/word-audio`, {
        method: "POST",
        headers: { Authorization: `Bearer ${getAuthToken() ?? ""}` },
        body: form,
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error ?? "Не удалось загрузить аудио");
      setVocab((v) => v.map((r, idx) => (idx === index ? { ...r, audioUrl: data.audioUrl } : r)));
      invalidateLessonCache(lessonId);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Не удалось загрузить аудио");
    } finally {
      setSaving(null);
    }
  };

  const deleteAudio = async (index: number) => {
    const row = vocab[index];
    setError(null);
    try {
      await api.delete(
        `/api/admin/content/${encodeURIComponent(lessonId)}/word-audio?german=${encodeURIComponent(row.german)}`,
      );
      setVocab((v) => v.map((r, idx) => (idx === index ? { ...r, audioUrl: null } : r)));
      invalidateLessonCache(lessonId);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Не удалось удалить аудио");
    }
  };

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
            <p className="stage-subtitle">
              Немецкое слово, перевод, транскрипция и произношение. 🔊 — прослушать, ⚙ — синтез речи браузера,
              ⬆ — загрузить свой файл. Загруженная запись всегда важнее синтеза. Слово нельзя добавить, если оно уже
              есть в другом уроке курса.
            </p>

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
                  <div className="admin-word-audio">
                    <button
                      type="button"
                      className="btn btn-ghost admin-word-audio__btn"
                      title={row.audioUrl ? "Прослушать загруженное аудио" : "Прослушать синтезом речи"}
                      onClick={() => playWord(row.german, row.audioUrl ?? undefined)}
                      disabled={!row.german.trim()}
                    >
                      🔊
                    </button>
                    {canSynthesize() && (
                      <button
                        type="button"
                        className="btn btn-ghost admin-word-audio__btn"
                        title="Сгенерировать произношение (синтез речи браузера)"
                        onClick={() => speakGerman(row.german)}
                        disabled={!row.german.trim()}
                      >
                        ⚙
                      </button>
                    )}
                    <label className="btn btn-ghost admin-word-audio__btn" title="Загрузить свой аудиофайл">
                      ⬆
                      <input
                        type="file"
                        accept="audio/*"
                        hidden
                        onChange={(e) => {
                          const file = e.target.files?.[0];
                          e.target.value = "";
                          if (file) uploadAudio(i, file);
                        }}
                      />
                    </label>
                    {row.audioUrl && (
                      <button
                        type="button"
                        className="btn btn-ghost admin-word-audio__btn admin-word-audio__btn--danger"
                        title="Удалить загруженное аудио"
                        onClick={() => deleteAudio(i)}
                      >
                        ✕🔊
                      </button>
                    )}
                    <button
                      type="button"
                      className="btn btn-ghost admin-row__remove"
                      title="Удалить слово"
                      onClick={() => setVocab((v) => v.filter((_, idx) => idx !== i))}
                    >
                      Удалить
                    </button>
                  </div>
                </div>
              ))}
            </div>

            <div className="stage-footer split">
              <button
                type="button"
                className="btn btn-secondary"
                onClick={() => setVocab((v) => [...v, { german: "", translation: "", pronunciation: "", audioUrl: null }])}
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
