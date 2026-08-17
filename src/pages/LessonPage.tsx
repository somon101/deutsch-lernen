import { useEffect, useMemo, useState } from "react";
import { Navigate, useNavigate, useParams } from "react-router-dom";
import LessonLayout from "../components/LessonLayout";
import { buildLessonExercises } from "../content/exerciseGenerators";
import { LessonExerciseSets } from "../content/exercises";
import { loadLesson } from "../content/loader";
import { LessonContent } from "../content/types";
import { useLessonProgress, useProgressStore } from "../progress/ProgressContext";
import { STAGE_ORDER, StageId, isStageUnlocked, nextIncompleteStage } from "../progress/types";
import VocabularyStage from "./stages/VocabularyStage";
import MaterialStage from "./stages/MaterialStage";
import VideoStage from "./stages/VideoStage";
import MiniTestStage from "./stages/MiniTestStage";
import AudioStage from "./stages/AudioStage";
import PracticeStage from "./stages/PracticeStage";
import ReviewStage from "./stages/ReviewStage";
import CompleteStage from "./stages/CompleteStage";

const VALID_STAGES = new Set<string>(STAGE_ORDER);

export default function LessonPage() {
  const { lessonId = "", stage = "" } = useParams();
  const navigate = useNavigate();
  const progress = useLessonProgress(lessonId);
  const { markStageComplete } = useProgressStore();

  const [content, setContent] = useState<LessonContent | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    loadLesson(lessonId).then((c) => {
      if (!cancelled) {
        setContent(c);
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [lessonId]);

  const exercises: LessonExerciseSets | null = useMemo(
    () => (content ? buildLessonExercises(content) : null),
    [content],
  );

  if (!VALID_STAGES.has(stage)) {
    return <Navigate to={`/lesson/${lessonId}/${nextIncompleteStage(progress)}`} replace />;
  }

  const stageId = stage as StageId;

  if (!isStageUnlocked(progress, stageId)) {
    return <Navigate to={`/lesson/${lessonId}/${nextIncompleteStage(progress)}`} replace />;
  }

  if (loading || !content || !exercises) {
    return (
      <LessonLayout lessonId={lessonId} lessonTitle="Загрузка…" currentStage={stageId}>
        <div className="stage-panel">
          <p className="stage-subtitle">Загружаем материалы урока…</p>
        </div>
      </LessonLayout>
    );
  }

  const goToStage = (next: StageId) => navigate(`/lesson/${lessonId}/${next}`);

  const advanceFrom = (current: StageId) => {
    markStageComplete(lessonId, current);
    const idx = STAGE_ORDER.indexOf(current);
    const next = STAGE_ORDER[idx + 1] ?? "complete";
    goToStage(next);
  };

  return (
    <LessonLayout lessonId={lessonId} lessonTitle={content.title} currentStage={stageId}>
      {content.missing.length > 0 && stageId === "vocabulary" && (
        <div className="empty-state" style={{ maxWidth: 720, width: "100%" }}>
          <h3>В папке урока не хватает некоторых файлов</h3>
          <ul>
            {content.missing.map((m) => (
              <li key={m}>{m}</li>
            ))}
          </ul>
        </div>
      )}

      {stageId === "vocabulary" && (
        <VocabularyStage content={content} lessonId={lessonId} onComplete={() => advanceFrom("vocabulary")} />
      )}
      {stageId === "material" && <MaterialStage content={content} onComplete={() => advanceFrom("material")} />}
      {stageId === "video" && <VideoStage content={content} onComplete={() => advanceFrom("video")} />}
      {stageId === "minitest" && (
        <MiniTestStage lessonId={lessonId} exercises={exercises.miniTest} onComplete={() => advanceFrom("minitest")} />
      )}
      {stageId === "audio" && <AudioStage content={content} onComplete={() => advanceFrom("audio")} />}
      {stageId === "practice" && (
        <PracticeStage lessonId={lessonId} exercises={exercises.practice} onComplete={() => advanceFrom("practice")} />
      )}
      {stageId === "review" && (
        <ReviewStage lessonId={lessonId} exercises={exercises.review} onComplete={() => advanceFrom("review")} />
      )}
      {stageId === "complete" && <CompleteStage lessonId={lessonId} content={content} />}
    </LessonLayout>
  );
}
