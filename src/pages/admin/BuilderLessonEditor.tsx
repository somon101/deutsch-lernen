import { useEffect, useState } from "react";
import { assetUrl } from "../../auth/api";
import { BuilderLesson, builderApi, builderMedia, uploadLessonMedia } from "../../admin/builderApi";
import LessonChainEditor from "./LessonChainEditor";
import { asCanvasLayout } from "./LessonFlowCanvas";

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
  onRun: (key: string, action: () => Promise<unknown>) => Promise<void>;
}) {
  const [title, setTitle] = useState(lesson.title);
  const [description, setDescription] = useState(lesson.description);
  const [materialText, setMaterialText] = useState(lesson.materialText);

  useEffect(() => {
    setTitle(lesson.title);
    setDescription(lesson.description);
    setMaterialText(lesson.materialText);
  }, [lesson]);

  const key = (name: string) => `${name}-${lesson.id}`;

  return (
    <div className="builder-lesson-editor">
      {/* ---------- Lesson name ---------- */}
      <section className="profile-card">
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
      </section>

      <h4 className="builder-section-title">Цепочка урока</h4>
      <p className="stage-subtitle" style={{ fontSize: 13.5 }}>
        Порядок этапов задан методикой курса и одинаков для всех уроков. Нажмите на узел, чтобы отредактировать его.
      </p>

      <LessonChainEditor
        lessonId={lesson.id}
        courseId={courseId}
        vocabulary={lesson.vocabulary}
        materialText={materialText}
        onMaterialChange={setMaterialText}
        saveMaterial={() => builderApi.updateLesson(courseId, lesson.id, { materialText })}
        videoUrl={assetUrl(lesson.videoUrl) ?? null}
        audioUrl={assetUrl(lesson.audioUrl) ?? null}
        uploadMedia={(kind, file) => uploadLessonMedia(courseId, lesson.id, kind, file)}
        removeMedia={(kind) => builderMedia.removeMedia(courseId, lesson.id, kind)}
        blocks={lesson.blocks}
        addBlock={(stage) => {
          const n = lesson.blocks.filter((b) => b.stage === stage).length + 1;
          const stageTitle = { minitest: "Мини-тест", practice: "Практика", review: "Закрепление" }[stage];
          return builderApi.addBlock(courseId, lesson.id, stage, `${stageTitle} ${n}`);
        }}
        reorderBlocks={(stage, ids) => builderApi.reorderBlocks(courseId, lesson.id, stage, ids)}
        canvasLayout={asCanvasLayout(lesson.canvasLayout)}
        // Deliberately not routed through onRun: a layout save is frequent
        // (debounced drag/connect edits) and purely visual, so it shouldn't
        // trigger the parent's full-course refetch + re-render on every one
        // — LessonFlowCanvas shows its own "Черновик сохранён" instead.
        saveLayout={(layout) => builderApi.updateLesson(courseId, lesson.id, { canvasLayout: layout })}
        busy={busy}
        saved={saved}
        onRun={onRun}
      />
    </div>
  );
}
