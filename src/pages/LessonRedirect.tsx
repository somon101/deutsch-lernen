import { Navigate, useParams } from "react-router-dom";
import { useLessonProgress } from "../progress/ProgressContext";
import { nextIncompleteStage } from "../progress/types";

export default function LessonRedirect() {
  const { lessonId = "" } = useParams();
  const progress = useLessonProgress(lessonId);
  return <Navigate to={`/lesson/${lessonId}/${nextIncompleteStage(progress)}`} replace />;
}
