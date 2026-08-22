import { useState } from "react";
import { BuilderBlock, BuilderWord, QuestionSet } from "../../admin/builderApi";
import BuilderBlockEditor from "./BuilderBlockEditor";
import BuilderVocabularyEditor from "./BuilderVocabularyEditor";
import LessonMediaEditor from "./LessonMediaEditor";
import MaterialFormatGuide from "./MaterialFormatGuide";
import DragList from "./DragList";
import LessonFlowCanvas, { SavedCanvasLayout } from "./LessonFlowCanvas";

/**
 * The chain a learner actually walks, in the order the app runs it. Only the
 * three question stages hold blocks; "Аудио" is a listening stage and "Итог"
 * is the results screen, so neither takes questions. Shared by the course
 * builder and the legacy lesson editor — both walk the same fixed sequence.
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

/** Icon + accent color per node, purely presentational — the underlying
 * step order and data are unaffected by any of this. */
const STEP_STYLE: Record<string, { icon: string; accent: string }> = {
  vocabulary: { icon: "📚", accent: "#8b5cf6" },
  material: { icon: "📄", accent: "#3b82f6" },
  video: { icon: "🎬", accent: "#f43f5e" },
  minitest: { icon: "📝", accent: "#22c55e" },
  audio: { icon: "🎧", accent: "#14b8a6" },
  practice: { icon: "🧩", accent: "#f59e0b" },
  review: { icon: "🏁", accent: "#22c55e" },
  complete: { icon: "🏆", accent: "#64748b" },
};

/**
 * Node-flow view of a lesson's fixed 8-step chain — a horizontal row of
 * cards connected by arrows (styled after a reference the course owner
 * liked), each showing a live preview of its content, with the full editor
 * for the selected step opening in a panel below the row. The step order
 * and every underlying editor component are unchanged from before; only the
 * layout wrapping them is new, so no lesson data or save/generation logic is
 * touched here.
 */
export default function LessonChainEditor({
  lessonId,
  courseId,
  vocabulary,
  materialText,
  onMaterialChange,
  saveMaterial,
  videoUrl,
  audioUrl,
  uploadMedia,
  removeMedia,
  blocks,
  addBlock,
  reorderBlocks,
  canvasLayout,
  saveLayout,
  busy,
  saved,
  onRun,
}: {
  lessonId: string;
  courseId: string;
  vocabulary: BuilderWord[];
  materialText: string;
  onMaterialChange: (text: string) => void;
  saveMaterial: () => Promise<unknown>;
  videoUrl: string | null;
  audioUrl: string | null;
  uploadMedia: (kind: "video" | "audio", file: File) => Promise<unknown>;
  removeMedia: (kind: "video" | "audio") => Promise<unknown>;
  blocks: BuilderBlock[];
  addBlock: (stage: QuestionSet) => Promise<unknown>;
  reorderBlocks: (stage: QuestionSet, ids: string[]) => Promise<unknown>;
  /** Saved node-flow canvas layout, or null if never arranged/saved yet. */
  canvasLayout: SavedCanvasLayout | null;
  saveLayout: (layout: SavedCanvasLayout) => Promise<unknown>;
  busy: string | null;
  saved: string | null;
  onRun: (key: string, action: () => Promise<unknown>) => Promise<void>;
}) {
  const [openKey, setOpenKey] = useState<string | null>(null);

  const blocksOf = (stage: QuestionSet) => blocks.filter((b) => b.stage === stage).sort((a, b) => a.position - b.position);
  const stageSummary = (stage: QuestionSet) => {
    const bs = blocksOf(stage);
    const questions = bs.reduce((n, b) => n + b.questions.length, 0);
    if (bs.length === 0) return "нет блоков";
    return `${bs.length} блок(ов) · ${questions} вопросов`;
  };

  const materialKey = `material-${lessonId}`;
  const mediaKey = (kind: "video" | "audio") => `media-${kind}-${lessonId}`;
  const addKey = (stage: QuestionSet) => `add-${stage}-${lessonId}`;
  const reorderKey = (stage: QuestionSet) => `reorder-${stage}-${lessonId}`;

  const summaryOf = (key: string): string => {
    switch (key) {
      case "vocabulary":
        return `${vocabulary.length} слов`;
      case "material":
        return materialText ? `${materialText.length} символов` : "не заполнен";
      case "video":
        return videoUrl ? "файл загружен" : "файла нет";
      case "audio":
        return audioUrl ? "файл загружен" : "файла нет";
      case "minitest":
        return stageSummary("minitest");
      case "practice":
        return stageSummary("practice");
      case "review":
        return stageSummary("review");
      default:
        return "считается автоматически";
    }
  };

  const previewOf = (key: string): string[] => {
    if (key === "vocabulary") {
      const shown = vocabulary.slice(0, 5).map((w) => w.german);
      if (vocabulary.length > shown.length) shown.push(`+${vocabulary.length - shown.length}`);
      return shown;
    }
    if (key === "video" || key === "audio") {
      const url = key === "video" ? videoUrl : audioUrl;
      return url ? [key === "video" ? "▶ видео загружено" : "▶ аудио загружено"] : [];
    }
    if (key === "minitest" || key === "practice" || key === "review") {
      const bs = blocksOf(key as QuestionSet);
      const shown = bs.slice(0, 4).map((b) => `${b.title} · ${b.questions.length}`);
      if (bs.length > 4) shown.push(`+${bs.length - 4}`);
      return shown;
    }
    return [];
  };

  const questionStage = (stage: QuestionSet) => (
    <>
      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
        Этап может содержать несколько блоков — например «{STAGE_TITLES[stage]} 1» и «{STAGE_TITLES[stage]} 2».
        Ученик проходит их подряд внутри этого этапа.
      </p>

      <DragList
        items={blocksOf(stage)}
        onReorder={(ids) => onRun(reorderKey(stage), () => reorderBlocks(stage, ids))}
        renderItem={(block) => (
          <BuilderBlockEditor courseId={courseId} lessonId={lessonId} block={block} busy={busy} saved={saved} onRun={onRun} />
        )}
      />

      <div className="stage-footer">
        <button
          type="button"
          className="btn btn-secondary"
          disabled={busy === addKey(stage)}
          onClick={() => onRun(addKey(stage), () => addBlock(stage))}
        >
          + Добавить {STAGE_TITLES[stage].toLowerCase()}
        </button>
      </div>
    </>
  );

  const bodyOf = (key: string) => {
    switch (key) {
      case "vocabulary":
        return <BuilderVocabularyEditor courseId={courseId} lessonId={lessonId} words={vocabulary} busy={busy} saved={saved} onRun={onRun} />;
      case "material":
        return (
          <>
            <MaterialFormatGuide />
            <textarea
              className="admin-textarea"
              rows={14}
              value={materialText}
              onChange={(e) => onMaterialChange(e.target.value)}
              placeholder="# Урок 1&#10;&#10;Hallo [ха́лло] — привет"
            />
            <div className="stage-footer">
              {saved === materialKey && <span className="admin-saved">Сохранено</span>}
              <button
                type="button"
                className="btn btn-primary"
                disabled={busy === materialKey}
                onClick={() => onRun(materialKey, saveMaterial)}
              >
                {busy === materialKey ? "Сохраняем…" : "Сохранить материал"}
              </button>
            </div>
          </>
        );
      case "video":
      case "audio": {
        const kind = key as "video" | "audio";
        return (
          <LessonMediaEditor
            kind={kind}
            url={kind === "video" ? videoUrl : audioUrl}
            busy={busy === mediaKey(kind)}
            onUpload={(file) => onRun(mediaKey(kind), () => uploadMedia(kind, file))}
            onRemove={() => onRun(mediaKey(kind), () => removeMedia(kind))}
          />
        );
      }
      case "minitest":
      case "practice":
      case "review":
        return questionStage(key as QuestionSet);
      default:
        return <p className="stage-subtitle">Экран результатов формируется автоматически по ответам ученика.</p>;
    }
  };

  const openStep = LESSON_CHAIN.find((s) => s.key === openKey);

  const steps = LESSON_CHAIN.map((step) => ({
    key: step.key,
    icon: STEP_STYLE[step.key].icon,
    accent: STEP_STYLE[step.key].accent,
    title: step.label,
    summary: summaryOf(step.key),
    preview: previewOf(step.key),
    editable: true,
  }));

  return (
    <div className="lesson-flow-wrap">
      <LessonFlowCanvas
        steps={steps}
        activeKey={openKey}
        onSelect={(key) => setOpenKey((cur) => (cur === key ? null : key))}
        savedLayout={canvasLayout}
        onSaveLayout={saveLayout}
      />

      {openStep && (
        <div className="flow-panel">
          <div className="flow-panel__head">
            <span className="flow-panel__title">
              <span style={{ color: STEP_STYLE[openStep.key].accent }}>{STEP_STYLE[openStep.key].icon}</span> {openStep.label}
              {openStep.note && <span className="flow-panel__note">{openStep.note}</span>}
            </span>
            <button type="button" className="flow-panel__close" onClick={() => setOpenKey(null)} aria-label="Закрыть">
              ✕
            </button>
          </div>
          <div className="flow-panel__body">{bodyOf(openStep.key)}</div>
        </div>
      )}
    </div>
  );
}
