import { ReactNode, useEffect, useState } from "react";
import { assetUrl } from "../../auth/api";
import { canSynthesize, playWord, speakGerman } from "../../lib/speech";
import { BuilderCourse, BuilderLesson, QuestionSet, builderApi, uploadLessonMedia } from "../../admin/builderApi";
import BuilderBlockEditor from "./BuilderBlockEditor";

/**
 * The chain a learner actually walks, in the order the app runs it. Only the
 * three question stages hold blocks; "Аудио" is a listening stage and "Итог"
 * is the results screen, so neither takes questions.
 */
export const LESSON_CHAIN: { key: string; label: string; note?: string }[] = [
  { key: "vocabulary", label: "Слова", note: "карточки словаря" },
  { key: "material", label: "Материал", note: "текст урока" },
  { key: "video", label: "Видео" },
  { key: "minitest", label: "Мини-тест", note: "вопросы после видео" },
  { key: "audio", label: "Аудио", note: "прослушивание, без заданий" },
  { key: "practice", label: "Практика", note: "вопросы" },
  { key: "review", label: "Закрепление", note: "итоговый тест урока" },
  { key: "complete", label: "Итог", note: "экран результатов" },
];

const STAGE_TITLES: Record<QuestionSet, string> = {
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

/** One expandable element of the lesson chain. */
function ChainItem({
  index,
  label,
  note,
  summary,
  editable,
  open,
  onToggle,
  children,
}: {
  index: number;
  label: string;
  note?: string;
  summary: string;
  editable: boolean;
  open: boolean;
  onToggle: () => void;
  children?: ReactNode;
}) {
  return (
    <div className={`chain-item ${open ? "is-open" : ""} ${editable ? "" : "is-readonly"}`}>
      <button type="button" className="chain-item__head" onClick={onToggle} disabled={!editable}>
        <span className="chain-item__index">{index}</span>
        <span className="chain-item__label">
          {label}
          {note && <span className="chain-item__note">{note}</span>}
        </span>
        <span className="chain-item__summary">{summary}</span>
        {editable && <span className="chain-item__caret">{open ? "▾" : "▸"}</span>}
      </button>
      {open && editable && <div className="chain-item__body">{children}</div>}
    </div>
  );
}

export default function BuilderLessonEditor({
  courseId,
  lesson,
  busy,
  saved,
  onRun,
}: {
  courseId: string;
  lesson: BuilderLesson;
  busy: string | null;
  saved: string | null;
  onRun: (key: string, action: () => Promise<BuilderCourse>) => Promise<void>;
}) {
  const [openKey, setOpenKey] = useState<string | null>(null);
  const [title, setTitle] = useState(lesson.title);
  const [description, setDescription] = useState(lesson.description);
  const [materialText, setMaterialText] = useState(lesson.materialText);
  const [words, setWords] = useState<WordRow[]>([]);

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
  }, [lesson]);

  const key = (name: string) => `${name}-${lesson.id}`;
  const blocksOf = (stage: QuestionSet) =>
    lesson.blocks.filter((b) => b.stage === stage).sort((a, b) => a.position - b.position);

  const addBlock = (stage: QuestionSet) => {
    const n = blocksOf(stage).length + 1;
    onRun(key(`add-${stage}`), () => builderApi.addBlock(courseId, lesson.id, stage, `${STAGE_TITLES[stage]} ${n}`));
  };

  const moveBlock = (stage: QuestionSet, index: number, delta: number) => {
    const ids = blocksOf(stage).map((b) => b.id);
    const target = index + delta;
    if (target < 0 || target >= ids.length) return;
    [ids[index], ids[target]] = [ids[target], ids[index]];
    onRun(key(`reorder-${stage}`), () => builderApi.reorderBlocks(courseId, lesson.id, stage, ids));
  };

  const stageSummary = (stage: QuestionSet) => {
    const blocks = blocksOf(stage);
    const questions = blocks.reduce((n, b) => n + b.questions.length, 0);
    if (blocks.length === 0) return "нет блоков";
    return `${blocks.length} блок(ов) · ${questions} вопросов`;
  };

  const questionStage = (stage: QuestionSet) => (
    <>
      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
        Этап может содержать несколько блоков — например «{STAGE_TITLES[stage]} 1» и «{STAGE_TITLES[stage]} 2».
        Ученик проходит их подряд внутри этого этапа.
      </p>

      {blocksOf(stage).map((block, i) => (
        <BuilderBlockEditor
          key={block.id}
          courseId={courseId}
          lessonId={lesson.id}
          block={block}
          index={i}
          total={blocksOf(stage).length}
          busy={busy}
          saved={saved}
          onRun={onRun}
          onMove={(delta) => moveBlock(stage, i, delta)}
        />
      ))}

      <div className="stage-footer">
        <button type="button" className="btn btn-secondary" onClick={() => addBlock(stage)}>
          + Добавить {STAGE_TITLES[stage].toLowerCase()}
        </button>
      </div>
    </>
  );

  return (
    <div className="builder-lesson-editor">
      {/* ---------- Lesson name ---------- */}
      <div className="auth-form-grid">
        <label className="auth-field">
          <span>Название урока</span>
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

      <h4 className="builder-section-title">Цепочка урока</h4>
      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
        Порядок этапов задан методикой курса и одинаков для всех уроков. Нажмите на элемент, чтобы отредактировать его.
      </p>

      <div className="lesson-chain">
        {LESSON_CHAIN.map((step, i) => {
          const open = openKey === step.key;
          const toggle = () => setOpenKey(open ? null : step.key);

          if (step.key === "vocabulary") {
            return (
              <ChainItem
                key={step.key}
                index={i + 1}
                label={step.label}
                note={step.note}
                summary={`${words.length} слов`}
                editable
                open={open}
                onToggle={toggle}
              >
                <div className="admin-rows">
                  {words.map((row, wi) => (
                    <div className="admin-row builder-word-row" key={wi}>
                      <input
                        placeholder="Hallo"
                        value={row.german}
                        onChange={(e) => setWords((w) => w.map((r, x) => (x === wi ? { ...r, german: e.target.value } : r)))}
                      />
                      <input
                        placeholder="привет"
                        value={row.translation}
                        onChange={(e) =>
                          setWords((w) => w.map((r, x) => (x === wi ? { ...r, translation: e.target.value } : r)))
                        }
                      />
                      <input
                        placeholder="ха́лло"
                        value={row.pronunciation}
                        onChange={(e) =>
                          setWords((w) => w.map((r, x) => (x === wi ? { ...r, pronunciation: e.target.value } : r)))
                        }
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
                        onClick={() => setWords((w) => w.filter((_, x) => x !== wi))}
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
              </ChainItem>
            );
          }

          if (step.key === "material") {
            return (
              <ChainItem
                key={step.key}
                index={i + 1}
                label={step.label}
                note={step.note}
                summary={materialText ? `${materialText.length} символов` : "не заполнен"}
                editable
                open={open}
                onToggle={toggle}
              >
                <textarea
                  className="admin-textarea"
                  rows={12}
                  value={materialText}
                  onChange={(e) => setMaterialText(e.target.value)}
                  placeholder="# Урок 1&#10;&#10;Hallo [ха́лло] — привет"
                />
                <div className="stage-footer">
                  {saved === key("material") && <span className="admin-saved">Сохранено</span>}
                  <button
                    type="button"
                    className="btn btn-primary"
                    disabled={busy === key("material")}
                    onClick={() => onRun(key("material"), () => builderApi.updateLesson(courseId, lesson.id, { materialText }))}
                  >
                    Сохранить материал
                  </button>
                </div>
              </ChainItem>
            );
          }

          if (step.key === "video" || step.key === "audio") {
            const kind = step.key === "video" ? "video" : "audio";
            const url = kind === "video" ? lesson.videoUrl : lesson.audioUrl;
            return (
              <ChainItem
                key={step.key}
                index={i + 1}
                label={step.label}
                note={step.note}
                summary={url ? "файл загружен" : "файла нет"}
                editable
                open={open}
                onToggle={toggle}
              >
                {url ? (
                  kind === "video" ? (
                    <video className="builder-media-preview" src={assetUrl(url)} controls preload="metadata" />
                  ) : (
                    <audio src={assetUrl(url)} controls preload="none" />
                  )
                ) : (
                  <p className="stage-subtitle">Файл ещё не загружен.</p>
                )}
                <div className="profile-avatar-actions">
                  <label className="btn btn-secondary">
                    {url ? "Заменить файл" : "Загрузить файл"}
                    <input
                      type="file"
                      accept={kind === "video" ? "video/mp4,video/webm,video/quicktime" : "audio/*"}
                      hidden
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        e.target.value = "";
                        if (file) onRun(key(`media-${kind}`), () => uploadLessonMedia(courseId, lesson.id, kind, file));
                      }}
                    />
                  </label>
                  {url && (
                    <button
                      type="button"
                      className="btn btn-ghost admin-row__remove"
                      onClick={() => onRun(key(`media-${kind}`), () => builderApi.removeMedia(courseId, lesson.id, kind))}
                    >
                      Удалить файл
                    </button>
                  )}
                </div>
              </ChainItem>
            );
          }

          if (step.key === "minitest" || step.key === "practice" || step.key === "review") {
            const stage = step.key as QuestionSet;
            return (
              <ChainItem
                key={step.key}
                index={i + 1}
                label={step.label}
                note={step.note}
                summary={stageSummary(stage)}
                editable
                open={open}
                onToggle={toggle}
              >
                {questionStage(stage)}
              </ChainItem>
            );
          }

          // "Итог" is generated from the learner's results — nothing to edit.
          return (
            <ChainItem
              key={step.key}
              index={i + 1}
              label={step.label}
              note={step.note}
              summary="считается автоматически"
              editable={false}
              open={false}
              onToggle={() => {}}
            />
          );
        })}
      </div>
    </div>
  );
}
