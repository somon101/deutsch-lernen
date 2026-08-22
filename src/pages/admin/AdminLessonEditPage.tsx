import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { ApiError, api } from "../../auth/api";
import { invalidateLessonCache, loadLesson } from "../../content/loader";
import { fetchContentOverrides } from "../../content/overrides";
import { LessonContent } from "../../content/types";
import { builderApi } from "../../admin/builderApi";
import { legacyLayoutApi, legacyMediaApi } from "../../admin/legacyContentApi";
import AdminTopNav from "../../components/admin/AdminTopNav";
import Breadcrumbs from "../../components/admin/Breadcrumbs";
import LessonChainEditor from "./LessonChainEditor";
import { asCanvasLayout } from "./LessonFlowCanvas";

/** courseId all of lesson1/lesson2's vocabulary/questions/blocks live under
 * — see content.ts's LEGACY_COURSE_ID on the server. */
const LEGACY_COURSE_ID = "legacy";

/**
 * Full admin editor for one of the two lessons that predate the course
 * builder (lesson1/lesson2 — file-based material/video/audio, with an
 * optional DB override layer). Deliberately reuses the exact same
 * LessonChainEditor the builder uses for brand-new courses — see
 * courses.ts's ownedLesson() helper, which is what lets those components'
 * mutations target courseId="legacy" without a Course/CourseLesson row to
 * back them. Nothing is copied into the builder's tables; the file +
 * override layer stays the single source of truth, exactly as before.
 */
export default function AdminLessonEditPage() {
  const { lessonId = "" } = useParams();

  const [lesson, setLesson] = useState<LessonContent | null>(null);
  const [materialText, setMaterialText] = useState("");
  const [canvasLayout, setCanvasLayout] = useState<unknown>(null);
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

    // Fetched together and applied in one setState batch — LessonFlowCanvas
    // only reads its `savedLayout` prop on first mount, so if `lesson` (which
    // gates that mount) turned non-null before this had resolved, the canvas
    // would start from an empty layout and never notice the real one arrive.
    const [content, layout] = await Promise.all([loadLesson(lessonId), legacyLayoutApi.get(lessonId).catch(() => null)]);
    setLesson(content);
    setMaterialText(content.materialText);
    setCanvasLayout(layout);
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

  return (
    <div className="app-shell">
      <AdminTopNav back={{ label: "← К урокам курса", to: "/admin/courses/legacy" }} />

      <main className="home-main">
        <div className="admin-layout admin-layout--wide">
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
          </section>

          <LessonChainEditor
            lessonId={lessonId}
            courseId={LEGACY_COURSE_ID}
            vocabulary={lesson.vocabulary.map((v) => ({
              id: v.id,
              german: v.german,
              translation: v.translation,
              pronunciation: v.pronunciation ?? null,
              audioUrl: v.audioUrl ?? null,
            }))}
            materialText={materialText}
            onMaterialChange={setMaterialText}
            saveMaterial={() => api.put(`/api/admin/content/${encodeURIComponent(lessonId)}`, { materialText })}
            videoUrl={lesson.assets.video?.url ?? null}
            audioUrl={lesson.assets.audio?.url ?? null}
            uploadMedia={(kind, file) => legacyMediaApi.upload(lessonId, kind, file)}
            removeMedia={(kind) => legacyMediaApi.remove(lessonId, kind)}
            blocks={lesson.blocks}
            addBlock={(stage) => {
              const n = lesson.blocks.filter((b) => b.stage === stage).length + 1;
              const stageTitle = { minitest: "Мини-тест", practice: "Практика", review: "Закрепление" }[stage];
              return builderApi.addBlock(LEGACY_COURSE_ID, lessonId, stage, `${stageTitle} ${n}`);
            }}
            reorderBlocks={(stage, ids) => builderApi.reorderBlocks(LEGACY_COURSE_ID, lessonId, stage, ids)}
            canvasLayout={asCanvasLayout(canvasLayout)}
            // Not routed through `run` — same reasoning as the builder's
            // lesson editor: frequent, purely-visual, shouldn't trigger this
            // page's full reload (which also re-checks vocabulary seeding).
            saveLayout={(layout) => legacyLayoutApi.save(lessonId, layout)}
            busy={busy}
            saved={saved}
            onRun={run}
          />
        </div>
      </main>
    </div>
  );
}
