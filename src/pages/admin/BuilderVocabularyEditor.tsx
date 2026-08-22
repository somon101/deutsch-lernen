import { useEffect, useState } from "react";
import { ApiError } from "../../auth/api";
import { canSynthesize, playWord, speakGerman } from "../../lib/speech";
import {
  BuilderWord,
  VocabularyImportItemResult,
  VocabularyImportPreview,
  VocabularyImportWord,
  builderApi,
  wordAudioApi,
} from "../../admin/builderApi";

interface WordRow {
  id: string;
  german: string;
  translation: string;
  pronunciation: string;
  audioUrl: string | null;
}

const JSON_PLACEHOLDER = `[
  { "original": "Hallo", "transcription": "[ˈhaloː]", "translation": "привет" }
]`;

function newWordsLabel(n: number): string {
  const mod10 = n % 10;
  const mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) return `${n} новое слово`;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return `${n} новых слова`;
  return `${n} новых слов`;
}

/**
 * Vocabulary section of the lesson chain. Add/edit go through the server's
 * per-course uniqueness check and are blocked outright on a duplicate; JSON
 * import instead skips duplicates automatically and reports what it skipped
 * (see addVocabularyWord/updateVocabularyWord/importVocabularyWords in
 * server/src/courses.ts) — nothing here is a substitute for those checks,
 * only a front for them.
 */
export default function BuilderVocabularyEditor({
  courseId,
  lessonId,
  words,
  busy,
  saved,
  onRun,
}: {
  courseId: string;
  lessonId: string;
  words: BuilderWord[];
  busy: string | null;
  saved: string | null;
  onRun: (key: string, action: () => Promise<unknown>) => Promise<void>;
}) {
  const [rows, setRows] = useState<WordRow[]>([]);
  const [mode, setMode] = useState<"manual" | "import">("manual");
  const [newWord, setNewWord] = useState({ german: "", translation: "", pronunciation: "" });

  const [jsonText, setJsonText] = useState("");
  const [preview, setPreview] = useState<VocabularyImportPreview | null>(null);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [previewBusy, setPreviewBusy] = useState(false);
  const [importBusy, setImportBusy] = useState(false);
  const [importResult, setImportResult] = useState<{ addedCount: number; skipped: VocabularyImportItemResult[] } | null>(null);

  const key = (name: string) => `${name}-${lessonId}`;

  useEffect(() => {
    setRows(
      words.map((w) => ({ id: w.id, german: w.german, translation: w.translation, pronunciation: w.pronunciation ?? "", audioUrl: w.audioUrl })),
    );
  }, [words]);

  // Only clear the "add word" form once the server actually confirms the
  // save (the `saved` flash) — a blocked duplicate leaves it as typed, so
  // the admin can see and fix what was rejected instead of losing it.
  useEffect(() => {
    if (saved === key("word-add")) setNewWord({ german: "", translation: "", pronunciation: "" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [saved]);

  const addWord = () => {
    const german = newWord.german.trim();
    const translation = newWord.translation.trim();
    const pronunciation = newWord.pronunciation.trim();
    if (!german || !translation || !pronunciation) return;
    onRun(key("word-add"), () => builderApi.addWord(courseId, lessonId, { german, translation, pronunciation }));
  };

  const saveRow = (row: WordRow) => {
    const german = row.german.trim();
    const translation = row.translation.trim();
    const pronunciation = row.pronunciation.trim();
    if (!german || !translation || !pronunciation) return;
    onRun(key(`word-save-${row.id}`), () => builderApi.updateWord(courseId, lessonId, row.id, { german, translation, pronunciation }));
  };

  const removeRow = (row: WordRow) => {
    if (!window.confirm(`Удалить слово «${row.german}» из словаря курса?`)) return;
    onRun(key(`word-remove-${row.id}`), () => builderApi.removeWord(courseId, lessonId, row.id));
  };

  const uploadRowAudio = (row: WordRow, file: File) => {
    onRun(key(`word-audio-${row.id}`), () => wordAudioApi.upload(courseId, lessonId, row.id, file));
  };

  const removeRowAudio = (row: WordRow) => {
    onRun(key(`word-audio-${row.id}`), () => wordAudioApi.remove(courseId, lessonId, row.id));
  };

  const resetImport = () => {
    setPreview(null);
    setPreviewError(null);
    setImportResult(null);
  };

  const runPreview = async () => {
    resetImport();
    let parsed: unknown;
    try {
      parsed = JSON.parse(jsonText);
    } catch {
      setPreviewError("Некорректный JSON: не удалось разобрать текст. Проверьте синтаксис.");
      return;
    }
    if (!Array.isArray(parsed)) {
      setPreviewError("Корневой элемент JSON должен быть массивом.");
      return;
    }
    setPreviewBusy(true);
    try {
      const report = await builderApi.previewVocabularyImport(courseId, lessonId, parsed as VocabularyImportWord[]);
      setPreview(report);
    } catch (err) {
      setPreviewError(err instanceof ApiError || err instanceof Error ? err.message : "Не удалось проверить JSON");
    } finally {
      setPreviewBusy(false);
    }
  };

  // Duplicates no longer block the import — they're skipped automatically,
  // so importing is possible as long as at least one word in the file is new.
  const canImport = preview !== null && preview.newCount > 0;

  const runImport = async () => {
    if (!canImport) return;
    let parsed: VocabularyImportWord[];
    try {
      parsed = JSON.parse(jsonText);
    } catch {
      return;
    }
    setImportBusy(true);
    setPreviewError(null);
    try {
      const result = await builderApi.importVocabulary(courseId, lessonId, parsed);
      // Reuses onRun purely to trigger the caller's "reload my view" step and
      // the busy/saved flash — the import already happened above.
      await onRun(key("import"), async () => {});
      setImportResult({ addedCount: result.addedCount, skipped: result.skipped });
      setJsonText("");
      setPreview(null);
    } catch (err) {
      setPreviewError(err instanceof ApiError || err instanceof Error ? err.message : "Не удалось импортировать слова");
    } finally {
      setImportBusy(false);
    }
  };

  return (
    <>
      <div className="admin-rows">
        {rows.map((row) => (
          <div className="admin-row builder-word-row" key={row.id}>
            <input
              placeholder="Hallo"
              value={row.german}
              onChange={(e) => setRows((rs) => rs.map((r) => (r.id === row.id ? { ...r, german: e.target.value } : r)))}
            />
            <input
              placeholder="привет"
              value={row.translation}
              onChange={(e) => setRows((rs) => rs.map((r) => (r.id === row.id ? { ...r, translation: e.target.value } : r)))}
            />
            <input
              placeholder="ха́лло"
              value={row.pronunciation}
              onChange={(e) => setRows((rs) => rs.map((r) => (r.id === row.id ? { ...r, pronunciation: e.target.value } : r)))}
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
            <label className="btn btn-ghost" title="Загрузить своё произношение">
              ⬆
              <input
                type="file"
                accept="audio/*"
                hidden
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  e.target.value = "";
                  if (file) uploadRowAudio(row, file);
                }}
              />
            </label>
            {row.audioUrl && (
              <button
                type="button"
                className="btn btn-ghost admin-row__remove"
                title="Удалить загруженное произношение"
                onClick={() => removeRowAudio(row)}
              >
                ✕🔊
              </button>
            )}
            <button
              type="button"
              className="btn btn-secondary"
              disabled={busy === key(`word-save-${row.id}`)}
              onClick={() => saveRow(row)}
            >
              {saved === key(`word-save-${row.id}`) ? "Сохранено" : "Сохранить"}
            </button>
            <button type="button" className="btn btn-ghost admin-row__remove" onClick={() => removeRow(row)}>
              Удалить
            </button>
          </div>
        ))}
        {rows.length === 0 && <p className="stage-subtitle">Слов пока нет — добавьте первое ниже.</p>}
      </div>

      <div className="builder-vocab-tabs">
        <button type="button" className={`btn ${mode === "manual" ? "btn-primary" : "btn-secondary"}`} onClick={() => setMode("manual")}>
          Добавить слово
        </button>
        <button type="button" className={`btn ${mode === "import" ? "btn-primary" : "btn-secondary"}`} onClick={() => setMode("import")}>
          Импортировать JSON
        </button>
      </div>

      {mode === "manual" && (
        <div className="admin-row builder-word-row">
          <input placeholder="Hallo" value={newWord.german} onChange={(e) => setNewWord((w) => ({ ...w, german: e.target.value }))} />
          <input
            placeholder="привет"
            value={newWord.translation}
            onChange={(e) => setNewWord((w) => ({ ...w, translation: e.target.value }))}
          />
          <input
            placeholder="[ˈhaloː]"
            value={newWord.pronunciation}
            onChange={(e) => setNewWord((w) => ({ ...w, pronunciation: e.target.value }))}
          />
          <button
            type="button"
            className="btn btn-primary"
            disabled={busy === key("word-add") || !newWord.german.trim() || !newWord.translation.trim() || !newWord.pronunciation.trim()}
            onClick={addWord}
          >
            + Добавить слово
          </button>
        </div>
      )}

      {mode === "import" && (
        <div className="builder-vocab-import">
          <div className="profile-avatar-actions">
            <label className="btn btn-secondary">
              Загрузить .json файл
              <input
                type="file"
                accept="application/json,.json"
                hidden
                onChange={async (e) => {
                  const file = e.target.files?.[0];
                  e.target.value = "";
                  if (!file) return;
                  resetImport();
                  try {
                    setJsonText(await file.text());
                  } catch {
                    setPreviewError("Не удалось прочитать файл.");
                  }
                }}
              />
            </label>
            <span className="stage-subtitle" style={{ margin: 0 }}>
              или вставьте JSON в поле ниже
            </span>
          </div>

          <label className="auth-field">
            <span>JSON со словами — original / transcription / translation</span>
            <textarea
              className="admin-textarea"
              rows={8}
              value={jsonText}
              onChange={(e) => {
                setJsonText(e.target.value);
                resetImport();
              }}
              placeholder={JSON_PLACEHOLDER}
            />
          </label>

          {previewError && <div className="exercise-feedback incorrect">{previewError}</div>}

          <div className="stage-footer split">
            <button type="button" className="btn btn-secondary" disabled={previewBusy || !jsonText.trim()} onClick={runPreview}>
              {previewBusy ? "Проверяем…" : "Проверить JSON"}
            </button>
            {canImport && (
              <button type="button" className="btn btn-primary" disabled={importBusy} onClick={runImport}>
                {importBusy ? "Импортируем…" : `Импортировать ${newWordsLabel(preview.newCount)}`}
              </button>
            )}
          </div>

          {preview && (
            <div className="builder-import-report">
              <ul className="builder-tree__parts">
                <li>
                  <span>Всего слов</span>
                  <span>{preview.total}</span>
                </li>
                <li className={preview.newCount === preview.total ? "" : "is-missing"}>
                  <span>Новых слов</span>
                  <span>{preview.newCount}</span>
                </li>
                <li className={preview.duplicateCount > 0 ? "is-missing" : ""}>
                  <span>Дубликаты</span>
                  <span>{preview.duplicateCount}</span>
                </li>
                <li className={preview.errorCount > 0 ? "is-missing" : ""}>
                  <span>Ошибки формата</span>
                  <span>{preview.errorCount}</span>
                </li>
              </ul>

              {preview.items.some((i) => i.status !== "new") && (
                <div className="admin-rows">
                  {preview.items
                    .filter((i) => i.status !== "new")
                    .map((item) => (
                      <div className="exercise-feedback incorrect" key={item.index}>
                        «{item.original}» — {item.message}
                      </div>
                    ))}
                </div>
              )}

              {preview.duplicateCount > 0 && canImport && (
                <p className="stage-subtitle">
                  Дубликаты будут пропущены автоматически — импортируются только новые слова.
                </p>
              )}
            </div>
          )}

          {importResult && (
            <div className="builder-import-report">
              <div className="exercise-feedback correct">Добавлено слов: {importResult.addedCount}.</div>
              {importResult.skipped.length > 0 && (
                <>
                  <p className="stage-subtitle">Пропущено как дубликаты:</p>
                  <div className="admin-rows">
                    {importResult.skipped.map((item) => (
                      <div className="exercise-feedback incorrect" key={item.index}>
                        «{item.original}» — {item.message}
                      </div>
                    ))}
                  </div>
                </>
              )}
            </div>
          )}
        </div>
      )}
    </>
  );
}
