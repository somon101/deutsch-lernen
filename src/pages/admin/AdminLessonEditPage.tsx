import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { ApiError, api } from "../../auth/api";
import { invalidateLessonCache, loadLesson } from "../../content/loader";
import { fetchContentOverrides } from "../../content/overrides";
import { LessonContent } from "../../content/types";
import { QuestionSet, builderApi } from "../../admin/builderApi";
import { legacyMediaApi } from "../../admin/legacyContentApi";
import AdminTopNav from "../../components/admin/AdminTopNav";
import Breadcrumbs from "../../components/admin/Breadcrumbs";
import ChainItem from "./ChainItem";
import LessonMediaEditor from "./LessonMediaEditor";
import MaterialFormatGuide from "./MaterialFormatGuide";
import BuilderVocabularyEditor from "./BuilderVocabularyEditor";
import BuilderBlockEditor from "./BuilderBlockEditor";
import { LESSON_CHAIN } from "./BuilderLessonEditor";

/** courseId all of lesson1/lesson2's vocabulary/questions/blocks live under
 * — see content.ts's LEGACY_COURSE_ID on the server. */
const LEGACY_COURSE_ID = "legacy";

const STAGE_TITLES: Record<QuestionSet, string> = {
  minitest: "Мини-тест",
  practice: "Практика",
  review: "Закрепление",
};

/**
 * Full admin editor for one of the two lessons that predate the course
 * builder (lesson1/lesson2 — file-based material/video/audio, with an
 * optional DB override layer). Deliberately reuses the exact same editing
 * components the builder uses for brand-new courses
 * (BuilderVocabularyEditor, BuilderBlockEditor, LessonMediaEditor) — see
 * courses.ts's ownedLesson() helper, which is what lets those components'
 * mutations target courseId="legacy" without a Course/CourseLesson row to
 * back them. Nothing is copied into the builder's tables; the file +
 * override layer stays the single source of truth, exactly as before.
 */
export default function AdminLessonEditPage() {
  const { lessonId = "" } = useParams();

  const [lesson, setLesson] = useState<LessonContent | null>(null);
  const [materialText, setMaterialText] = useState("");
  const [openKey, setOpenKey] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    invalidateLessonCache(lessonId);

    // The vocabulary override replaces the file's word list wholesale, not
    // by merging (same as materialText) — see content/loader.ts. That's fine
    // for a bulk save, but the per-word add/edit/delete this page uses only
    // ever inserts/touches one row, so the very first such edit would
    // otherwise make every other file-based word invisible. Seed the DB with
    // the file's current words once, before that can happen, using the same
    // JSON-import path the "Импортировать JSON" button uses — nothing new.
    const overrides = await fetchContentOverrides(lessonId);
    if (overrides.vocabulary.length === 0) {
      const fileOnly = await loadLesson(lessonId);
      if (fileOnly.vocabulary.length > 0) {
        try {
          await builderApi.importVocabulary(
            LEGACY_COURSE_ID,
            lessonId,
            fileOnly.vocabulary.map((v) => ({
              original: v.german,
              transcription: v.pronunciation?.trim() || v.german,
              translation: v.translation,
            })),
          );
          invalidateLessonCache(lessonId);
        } catch {
          // If this fails the page still works — it just falls back to
          // showing the file's words read-only until it succeeds on a
          // later load (e.g. after the admin fixes a network issue).
        }
      }
    }

    const content = await loadLesson(lessonId);
    setLesson(content);
    setMaterialText(content.materialText);
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lessonId]);

  const flash = (key: string) => {
    setSaved(key);
    setTimeout(() => setSaved((s) => (s === key ? null : s)), 2500);
  };

  /** Same contract as the builder's onRun: perform the mutation, then reload
   * this page's own view of the lesson. */
  const run = async (key: string, action: () => Promise<unknown>) => {
    setError(null);
    setBusy(key);
    try {
      await action();
      await load();
      flash(key);
    } catch (err) {
      setError(err instanceof ApiError || err instanceof Error ? err.message : "Не удалось сохранить");
    } finally {
      setBusy(null);
    }
  };

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
  const blocksOf = (stage: QuestionSet) =>
    lesson.blocks.filter((b) => b.stage === stage).sort((a, b) => a.position - b.position);

  const addBlock = (stage: QuestionSet) => {
    const n = blocksOf(stage).length + 1;
    run(`add-${stage}`, () => builderApi.addBlock(LEGACY_COURSE_ID, lessonId, stage, `${STAGE_TITLES[stage]} ${n}`));
  };

  const moveBlock = (stage: QuestionSet, index: number, delta: number) => {
    const ids = blocksOf(stage).map((b) => b.id);
    const target = index + delta;
    if (target < 0 || target >= ids.length) return;
    [ids[index], ids[target]] = [ids[target], ids[index]];
    run(`reorder-${stage}`, () => builderApi.reorderBlocks(LEGACY_COURSE_ID, lessonId, stage, ids));
  };

  const stageSummary = (stage: QuestionSet) => {
    const blocks = blocksOf(stage);
    const questions = blocks.reduce((n, b) => n + b.questions.length, 0);
    if (blocks.length === 0) return "нет блоков — вопросы генерируются автоматически";
    return `${blocks.length} блок(ов) · ${questions} вопросов`;
  };

  return (
    <div className="app-shell">
      <AdminTopNav back={{ label: "← К урокам курса", to: "/admin/courses/legacy" }} />

      <main className="home-main">
        <div className="admin-layout">
          <Breadcrumbs
            items={[
              { label: "Курсы", to: "/admin/courses" },
              { label: "Немецкий с нуля", to: "/admin/courses/legacy" },
              { label: displayTitle },
            ]}
          />

          {error && <div className="exercise-feedback incorrect">{error}</div>}

          <section className="profile-card">
            <h1 className="stage-title" style={{ fontSize: 22 }}>
              {displayTitle}
            </h1>
            <p className="stage-subtitle">
              Полный доступ к редактированию этого урока — тот же редактор, что и в конструкторе курсов. Материал,
              словарь, видео, аудио и все вопросы редактируются здесь напрямую; ничего не копируется в конструктор.
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
                      summary={`${lesson.vocabulary.length} слов`}
                      editable
                      open={open}
                      onToggle={toggle}
                    >
                      <BuilderVocabularyEditor
                        courseId={LEGACY_COURSE_ID}
                        lessonId={lessonId}
                        words={lesson.vocabulary.map((v) => ({
                          id: v.id,
                          german: v.german,
                          translation: v.translation,
                          pronunciation: v.pronunciation ?? null,
                          audioUrl: v.audioUrl ?? null,
                        }))}
                        busy={busy}
                        saved={saved}
                        onRun={run}
                      />
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
                      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
                        Текст урока в том же формате, что и раньше — заголовок, строки «Шаг 1. …» и пары «Hallo!
                        [ха́лло] — Привет!». Он разбирается тем же способом, что и файл урока: добавить/удалить/
                        переставить блок значит добавить/удалить/переставить строку.
                      </p>
                      <MaterialFormatGuide />
                      <textarea
                        className="admin-textarea"
                        rows={16}
                        value={materialText}
                        onChange={(e) => setMaterialText(e.target.value)}
                      />
                      <div className="stage-footer">
                        {saved === "material" && <span className="admin-saved">Сохранено</span>}
                        <button
                          type="button"
                          className="btn btn-primary"
                          disabled={busy === "material"}
                          onClick={() => run("material", () => api.put(`/api/admin/content/${encodeURIComponent(lessonId)}`, { materialText }))}
                        >
                          {busy === "material" ? "Сохраняем…" : "Сохранить материал"}
                        </button>
                      </div>
                    </ChainItem>
                  );
                }

                if (step.key === "video" || step.key === "audio") {
                  const kind = step.key as "video" | "audio";
                  const url = kind === "video" ? (lesson.assets.video?.url ?? null) : (lesson.assets.audio?.url ?? null);
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
                      <LessonMediaEditor
                        kind={kind}
                        url={url}
                        busy={busy === `media-${kind}`}
                        onUpload={(file) => run(`media-${kind}`, () => legacyMediaApi.upload(lessonId, kind, file))}
                        onRemove={() => run(`media-${kind}`, () => legacyMediaApi.remove(lessonId, kind))}
                      />
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
                      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
                        Этап может содержать несколько блоков — например «{STAGE_TITLES[stage]} 1» и «
                        {STAGE_TITLES[stage]} 2». Пока блоков нет, ученик видит вопросы, сгенерированные автоматически
                        из словаря — как и раньше.
                      </p>

                      {blocksOf(stage).map((block, bi) => (
                        <BuilderBlockEditor
                          key={block.id}
                          courseId={LEGACY_COURSE_ID}
                          lessonId={lessonId}
                          block={block}
                          index={bi}
                          total={blocksOf(stage).length}
                          busy={busy}
                          saved={saved}
                          onRun={run}
                          onMove={(delta) => moveBlock(stage, bi, delta)}
                        />
                      ))}

                      <div className="stage-footer">
                        <button type="button" className="btn btn-secondary" onClick={() => addBlock(stage)}>
                          + Добавить {STAGE_TITLES[stage].toLowerCase()}
                        </button>
                      </div>
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
          </section>
        </div>
      </main>
    </div>
  );
}
