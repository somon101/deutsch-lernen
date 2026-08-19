import { useEffect, useMemo, useState } from "react";
import { Navigate, useNavigate, useParams } from "react-router-dom";
import LessonLayout from "../components/LessonLayout";
import { buildBuilderLessonExercises, toLessonContent } from "../content/builderExercises";
import { LessonExerciseSets } from "../content/exercises";
import { BuilderCourse, loadBuilderCourse } from "../content/learnerCourses";
import { LessonContent } from "../content/types";
import { useLessonProgress, useProgressStore } from "../progress/ProgressContext";
import { STAGE_LABELS, STAGE_ORDER, StageId, isStageUnlocked, nextIncompleteStage } from "../progress/types";
import Breadcrumbs from "../components/admin/Breadcrumbs";
import VocabularyStage from "./stages/VocabularyStage";
import MaterialStage from "./stages/MaterialStage";
import VideoStage from "./stages/VideoStage";
import MiniTestStage from "./stages/MiniTestStage";
import AudioStage from "./stages/AudioStage";
import PracticeStage from "./stages/PracticeStage";
import ReviewStage from "./stages/ReviewStage";
import CompleteStage from "./stages/CompleteStage";

const VALID_STAGES = new Set<string>(STAGE_ORDER);

/**
 * Learner runner for a course built in the admin construсtor. Structurally
 * mirrors LessonPage.tsx (same stage gating/progress logic, imported
 * unchanged) — the only difference is where the lesson's content comes from
 * and where "back"/stepper links point, since a builder lesson lives under
 * its own course rather than at the top level.
 */
export default function BuilderLessonPage() {
  const { courseId = "", lessonId = "", stage = "" } = useParams();
  const navigate = useNavigate();
  const progress = useLessonProgress(lessonId);
  const { markStageComplete, isLoaded: progressLoaded } = useProgressStore();

  const [course, setCourse] = useState<BuilderCourse | null>(null);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    let cancelled = false;
    loadBuilderCourse(courseId)
      .then((c) => {
        if (!cancelled) setCourse(c);
      })
      .catch(() => {
        if (!cancelled) setNotFound(true);
      });
    return () => {
      cancelled = true;
    };
  }, [courseId]);

  const lesson = course?.lessons.find((l) => l.id === lessonId) ?? null;

  const content: LessonContent | null = useMemo(() => (lesson ? toLessonContent(lesson) : null), [lesson]);
  const exercises: LessonExerciseSets | null = useMemo(() => (lesson ? buildBuilderLessonExercises(lesson) : null), [lesson]);

  const stageId = VALID_STAGES.has(stage) ? (stage as StageId) : ("vocabulary" as StageId);
  const stagePath = (s: StageId) => `/courses/${courseId}/lesson/${lessonId}/${s}`;

  if (notFound || (course && !lesson)) {
    return <Navigate to={`/courses/${courseId}`} replace />;
  }

  if (!progressLoaded || !course) {
    return (
      <LessonLayout lessonId={lessonId} lessonTitle="Загрузка…" currentStage={stageId} exitTo={`/courses/${courseId}`} stagePath={stagePath}>
        <div className="stage-panel">
          <p className="stage-subtitle">Загружаем урок…</p>
        </div>
      </LessonLayout>
    );
  }

  if (!VALID_STAGES.has(stage)) {
    return <Navigate to={stagePath(nextIncompleteStage(progress))} replace />;
  }

  if (!isStageUnlocked(progress, stageId)) {
    return <Navigate to={stagePath(nextIncompleteStage(progress))} replace />;
  }

  if (!content || !exercises) {
    return (
      <LessonLayout lessonId={lessonId} lessonTitle="Загрузка…" currentStage={stageId} exitTo={`/courses/${courseId}`} stagePath={stagePath}>
        <div className="stage-panel">
          <p className="stage-subtitle">Загружаем материалы урока…</p>
        </div>
      </LessonLayout>
    );
  }

  const goToStage = (next: StageId) => navigate(stagePath(next));

  const advanceFrom = (current: StageId) => {
    markStageComplete(lessonId, current);
    const idx = STAGE_ORDER.indexOf(current);
    const next = STAGE_ORDER[idx + 1] ?? "complete";
    goToStage(next);
  };

  return (
    <LessonLayout
      lessonId={lessonId}
      lessonTitle={content.title}
      currentStage={stageId}
      exitTo={`/courses/${courseId}`}
      stagePath={stagePath}
      breadcrumb={
        <Breadcrumbs
          items={[
            { label: "Курсы", to: "/courses" },
            { label: course.title, to: `/courses/${courseId}` },
            { label: content.title },
            { label: STAGE_LABELS[stageId] },
          ]}
        />
      }
    >
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
      {stageId === "complete" && (
        <CompleteStage lessonId={lessonId} content={content} homeTo={`/courses/${courseId}`} homeLabel="К урокам курса" />
      )}
    </LessonLayout>
  );
}
