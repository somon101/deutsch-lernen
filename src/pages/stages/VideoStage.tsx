import { useRef, useState } from "react";
import { LessonContent } from "../../content/types";

export default function VideoStage({
  content,
  onComplete,
}: {
  content: LessonContent;
  onComplete: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [watched, setWatched] = useState(false);

  if (!content.assets.video) {
    return (
      <div className="stage-panel">
        <div className="stage-eyebrow">Видеоурок</div>
        <h1 className="stage-title">Видео не найдено</h1>
        <div className="empty-state">
          <h3>Не хватает материала</h3>
          <p>Добавьте видеофайл (.mp4/.webm) в папку урока — он появится на этом этапе автоматически.</p>
        </div>
        <div className="stage-footer">
          <button className="btn btn-primary" onClick={onComplete}>
            Пропустить и продолжить
          </button>
        </div>
      </div>
    );
  }

  const handleTimeUpdate = () => {
    const v = videoRef.current;
    if (!v || !v.duration) return;
    if (v.currentTime / v.duration >= 0.9) setWatched(true);
  };

  return (
    <div className="stage-panel">
      <div className="stage-eyebrow">Видеоурок</div>
      <h1 className="stage-title">Посмотрите видео</h1>
      <p className="stage-subtitle">{content.assets.video.name}</p>

      <div className="video-frame">
        <video
          ref={videoRef}
          src={content.assets.video.url}
          controls
          onEnded={() => setWatched(true)}
          onTimeUpdate={handleTimeUpdate}
        />
      </div>

      <div className={`video-status ${watched ? "done" : ""}`}>
        {watched ? "✓ Видео просмотрено" : "Досмотрите видео до конца, чтобы продолжить"}
      </div>

      <div className="stage-footer">
        <button className="btn btn-primary" onClick={onComplete} disabled={!watched}>
          Перейти к мини-тесту →
        </button>
      </div>
    </div>
  );
}
