import { useEffect, useState } from "react";
import { assetUrl } from "../../auth/api";
import { canSynthesize, playWord, speakGerman } from "../../lib/speech";
import {
  BuilderCourse,
  BuilderLesson,
  BuilderQuestion,
  QuestionSet,
  builderApi,
} from "../../admin/builderApi";

const SET_LABELS: Record<QuestionSet, string> = {
  minitest: "Мини-тест",
  practice: "Практика",
  review: "Закрепление",
};

interface WordRow {
  german: string;
  translation: string;
  pronunciation: string;
  audioUrl: string | null;
}

interface QuestionRow {
  setName: QuestionSet;
  prompt: string;
  options: string[];
  correctIndex: number;
}

export default function BuilderLessonEditor({
  courseId,
  lesson,
  busy,
  saved,
  onRun,
  onUploadMedia,
}: {
  courseId: string;
  lesson: BuilderLesson;
  busy: string | null;
  saved: string | null;
  onRun: (key: string, action: () => Promise<BuilderCourse>) => Promise<void>;
  onUploadMedia: (kind: "video" | "audio", file: File) => void;
}) {
  const [title, setTitle] = useState(lesson.title);
  const [description, setDescription] = useState(lesson.description);
  const [materialText, setMaterialText] = useState(lesson.materialText);
  const [words, setWords] = useState<WordRow[]>([]);
  const [questions, setQuestions] = useState<QuestionRow[]>([]);

  // Re-sync whenever the server sends a fresh copy of this lesson.
  useEffect(() => {
    setTitle(lesson.title);
    setDescription(lesson.description);
    setMaterialText(lesson.materialText);
    setWords(
      lesson.vocabulary.map((w) => ({
        german: w.german,
        translation: w.translation,
        pronunciation: w.pronunciation ?? "",
        audioUrl: w.audioUrl,
      })),
    );
    setQuestions(
      lesson.questions.map((q) => ({
        setName: q.setName,
        prompt: q.prompt,
        options: q.options,
        correctIndex: Math.max(0, q.options.indexOf(q.correctAnswer)),
      })),
    );
  }, [lesson]);

  const key = (name: string) => `${name}-${lesson.id}`;

  return (
    <div className="builder-lesson-editor">
      {/* ---------------- Lesson details ---------------- */}
      <h4 className="builder-section-title">Урок</h4>
      <div className="auth-form-grid">
        <label className="auth-field">
          <span>Название</span>
          <input value={title} onChange={(e) => setTitle(e.target.value)} />
        </label>
        <label className="auth-field">
          <span>Описание</span>
          <input value={description} onChange={(e) => setDescription(e.target.value)} />
        </label>
      </div>
      <div className="stage-footer">
        {saved === key("details") && <span className="admin-saved">Сохранено</span>}
        <button
          type="button"
          className="btn btn-secondary"
          disabled={busy === key("details")}
          onClick={() => onRun(key("details"), () => builderApi.updateLesson(courseId, lesson.id, { title, description }))}
        >
          Сохранить название
        </button>
      </div>

      {/* ---------------- Material ---------------- */}
      <h4 className="builder-section-title">Материал</h4>
      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
        Текст урока в том же формате, что и в основном курсе: заголовок, «Шаг 1. …», пары «Hallo [ха́лло] — привет».
      </p>
      <textarea
        className="admin-textarea"
        rows={10}
        value={materialText}
        onChange={(e) => setMaterialText(e.target.value)}
        placeholder="# Урок 1&#10;&#10;Hallo [ха́лло] — привет"
      />
      <div className="stage-footer">
        {saved === key("material") && <span className="admin-saved">Сохранено</span>}
        <button
          type="button"
          className="btn btn-secondary"
          disabled={busy === key("material")}
          onClick={() => onRun(key("material"), () => builderApi.updateLesson(courseId, lesson.id, { materialText }))}
        >
          Сохранить материал
        </button>
      </div>

      {/* ---------------- Media ---------------- */}
      <h4 className="builder-section-title">Видео и аудио</h4>
      {(["video", "audio"] as const).map((kind) => {
        const url = kind === "video" ? lesson.videoUrl : lesson.audioUrl;
        return (
          <div className="builder-media-row" key={kind}>
            <span className="builder-media-row__label">{kind === "video" ? "Видеоурок" : "Аудиоурок"}</span>
            {url ? (
              kind === "video" ? (
                <video className="builder-media-preview" src={assetUrl(url)} controls preload="metadata" />
              ) : (
                <audio src={assetUrl(url)} controls preload="none" />
              )
            ) : (
              <span className="progress-lesson-row__stats">файл не загружен</span>
            )}
            <div className="profile-avatar-actions">
              <label className="btn btn-secondary">
                {url ? "Заменить" : "Загрузить"}
                <input
                  type="file"
                  accept={kind === "video" ? "video/mp4,video/webm,video/quicktime" : "audio/*"}
                  hidden
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    e.target.value = "";
                    if (file) onUploadMedia(kind, file);
                  }}
                />
              </label>
              {url && (
                <button
                  type="button"
                  className="btn btn-ghost admin-row__remove"
                  onClick={() => onRun(key(`media-${kind}`), () => builderApi.removeMedia(courseId, lesson.id, kind))}
                >
                  Удалить
                </button>
              )}
            </div>
          </div>
        );
      })}

      {/* ---------------- Vocabulary ---------------- */}
      <h4 className="builder-section-title">Словарь ({words.length})</h4>
      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
        Слово нельзя добавить, если оно уже есть в другом уроке этого курса — регистр и знаки не помогут обойти
        проверку. В других курсах то же слово использовать можно.
      </p>
      <div className="admin-rows">
        {words.map((row, i) => (
          <div className="admin-row builder-word-row" key={i}>
            <input
              placeholder="Hallo"
              value={row.german}
              onChange={(e) => setWords((w) => w.map((r, x) => (x === i ? { ...r, german: e.target.value } : r)))}
            />
            <input
              placeholder="привет"
              value={row.translation}
              onChange={(e) => setWords((w) => w.map((r, x) => (x === i ? { ...r, translation: e.target.value } : r)))}
            />
            <input
              placeholder="ха́лло"
              value={row.pronunciation}
              onChange={(e) => setWords((w) => w.map((r, x) => (x === i ? { ...r, pronunciation: e.target.value } : r)))}
            />
            <button
              type="button"
              className="btn btn-ghost"
              title={row.audioUrl ? "Прослушать загруженное аудио" : "Прослушать синтезом речи"}
              onClick={() => (row.audioUrl ? playWord(row.audioUrl) : speakGerman(row.german))}
              disabled={!row.audioUrl && !canSynthesize()}
            >
              🔊
            </button>
            <button
              type="button"
              className="btn btn-ghost admin-row__remove"
              onClick={() => setWords((w) => w.filter((_, x) => x !== i))}
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
          onClick={() => setWords((w) => [...w, { german: "", translation: "", pronunciation: "", audioUrl: null }])}
        >
          + Добавить слово
        </button>
        <span style={{ display: "flex", alignItems: "center", gap: 12 }}>
          {saved === key("words") && <span className="admin-saved">Сохранено</span>}
          <button
            type="button"
            className="btn btn-primary"
            disabled={busy === key("words")}
            onClick={() =>
              onRun(key("words"), () =>
                builderApi.saveVocabulary(
                  courseId,
                  lesson.id,
                  words.map((w) => ({
                    german: w.german,
                    translation: w.translation,
                    pronunciation: w.pronunciation.trim() ? w.pronunciation : null,
                    audioUrl: w.audioUrl,
                  })),
                ),
              )
            }
          >
            Сохранить словарь
          </button>
        </span>
      </div>

      {/* ---------------- Questions ---------------- */}
      <h4 className="builder-section-title">Вопросы и тесты ({questions.length})</h4>
      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
        Вопросы распределяются по трём этапам урока: мини-тест после видео, практика и закрепление (итоговый тест).
        Правильный вариант отмечаете вы — автоматически он не выбирается.
      </p>

      {questions.map((q, qi) => (
        <div className="admin-question" key={qi}>
          <div className="admin-question__head">
            <select
              value={q.setName}
              onChange={(e) =>
                setQuestions((qs) => qs.map((r, x) => (x === qi ? { ...r, setName: e.target.value as QuestionSet } : r)))
              }
            >
              {(Object.keys(SET_LABELS) as QuestionSet[]).map((s) => (
                <option key={s} value={s}>
                  {SET_LABELS[s]}
                </option>
              ))}
            </select>
            <div className="builder-order">
              <button
                type="button"
                className="btn btn-ghost"
                disabled={qi === 0}
                onClick={() =>
                  setQuestions((qs) => {
                    const next = [...qs];
                    [next[qi - 1], next[qi]] = [next[qi], next[qi - 1]];
                    return next;
                  })
                }
              >
                ↑
              </button>
              <button
                type="button"
                className="btn btn-ghost"
                disabled={qi === questions.length - 1}
                onClick={() =>
                  setQuestions((qs) => {
                    const next = [...qs];
                    [next[qi + 1], next[qi]] = [next[qi], next[qi + 1]];
                    return next;
                  })
                }
              >
                ↓
              </button>
              <button
                type="button"
                className="btn btn-ghost admin-row__remove"
                onClick={() => setQuestions((qs) => qs.filter((_, x) => x !== qi))}
              >
                Удалить
              </button>
            </div>
          </div>

          <label className="auth-field">
            <span>Текст вопроса</span>
            <input
              value={q.prompt}
              placeholder="Что значит «Hallo»?"
              onChange={(e) => setQuestions((qs) => qs.map((r, x) => (x === qi ? { ...r, prompt: e.target.value } : r)))}
            />
          </label>

          <span className="admin-question__hint">Отметьте правильный вариант:</span>
          {q.options.map((option, oi) => (
            <div className="admin-option" key={oi}>
              <input
                type="radio"
                name={`correct-${lesson.id}-${qi}`}
                checked={q.correctIndex === oi}
                onChange={() => setQuestions((qs) => qs.map((r, x) => (x === qi ? { ...r, correctIndex: oi } : r)))}
              />
              <input
                className="admin-option__text"
                placeholder={`Вариант ${oi + 1}`}
                value={option}
                onChange={(e) =>
                  setQuestions((qs) =>
                    qs.map((r, x) =>
                      x === qi ? { ...r, options: r.options.map((o, y) => (y === oi ? e.target.value : o)) } : r,
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
                    qs.map((r, x) => {
                      if (x !== qi) return r;
                      const options = r.options.filter((_, y) => y !== oi);
                      // Keep the same option marked correct after a removal.
                      let correctIndex = r.correctIndex;
                      if (oi === r.correctIndex) correctIndex = 0;
                      else if (oi < r.correctIndex) correctIndex -= 1;
                      return { ...r, options, correctIndex };
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
            onClick={() => setQuestions((qs) => qs.map((r, x) => (x === qi ? { ...r, options: [...r.options, ""] } : r)))}
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
            setQuestions((qs) => [...qs, { setName: "minitest", prompt: "", options: ["", ""], correctIndex: 0 }])
          }
        >
          + Добавить вопрос
        </button>
        <span style={{ display: "flex", alignItems: "center", gap: 12 }}>
          {saved === key("questions") && <span className="admin-saved">Сохранено</span>}
          <button
            type="button"
            className="btn btn-primary"
            disabled={busy === key("questions")}
            onClick={() =>
              onRun(key("questions"), () =>
                builderApi.saveQuestions(
                  courseId,
                  lesson.id,
                  questions.map<BuilderQuestion>((q) => ({
                    setName: q.setName,
                    prompt: q.prompt,
                    options: q.options,
                    correctAnswer: q.options[q.correctIndex] ?? "",
                  })),
                ),
              )
            }
          >
            Сохранить вопросы
          </button>
        </span>
      </div>
    </div>
  );
}
