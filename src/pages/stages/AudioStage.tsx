import { ChangeEvent, useRef, useState } from "react";
import { LessonContent } from "../../content/types";

function formatTime(sec: number): string {
  if (!isFinite(sec)) return "0:00";
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export default function AudioStage({
  content,
  onComplete,
}: {
  content: LessonContent;
  onComplete: () => void;
}) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [current, setCurrent] = useState(0);
  const [duration, setDuration] = useState(0);
  const [rate, setRate] = useState(1);
  const [finished, setFinished] = useState(false);
  const [playError, setPlayError] = useState<string | null>(null);

  if (!content.assets.audio) {
    return (
      <div className="stage-panel">
        <div className="stage-eyebrow">Аудиопересказ</div>
        <h1 className="stage-title">Аудио не найдено</h1>
        <div className="empty-state">
          <h3>Не хватает материала</h3>
          <p>Добавьте аудиофайл (.mp3/.m4a) в папку урока — он появится на этом этапе автоматически.</p>
        </div>
        <div className="stage-footer">
          <button className="btn btn-primary" onClick={onComplete}>
            Пропустить и продолжить
          </button>
        </div>
      </div>
    );
  }

  const toggle = () => {
    const a = audioRef.current;
    if (!a) return;
    if (playing) {
      a.pause();
      return;
    }
    setPlayError(null);
    // play() returns a Promise that rejects (e.g. NotAllowedError, AbortError)
    // instead of throwing — without this catch, a rejection was silently
    // swallowed and the button appeared to do nothing.
    a.play().catch(() => {
      setPlayError("Не удалось запустить воспроизведение аудио. Проверьте, не отключён звук в браузере/на вкладке, и попробуйте ещё раз.");
    });
  };

  const onSeek = (e: ChangeEvent<HTMLInputElement>) => {
    const a = audioRef.current;
    if (!a) return;
    a.currentTime = Number(e.target.value);
    setCurrent(a.currentTime);
  };

  const setPlaybackRate = (r: number) => {
    setRate(r);
    if (audioRef.current) audioRef.current.playbackRate = r;
  };

  return (
    <div className="stage-panel">
      <div className="stage-eyebrow">Аудиопересказ</div>
      <h1 className="stage-title">Прослушайте аудио</h1>
      <p className="stage-subtitle">Послушайте запись и закрепите произношение фраз из урока.</p>

      <div className="audio-card">
        <div className="audio-icon">🎧</div>
        <div className="audio-name">{content.assets.audio.name}</div>

        <audio
          ref={audioRef}
          src={content.assets.audio.url}
          onPlay={() => setPlaying(true)}
          onPause={() => setPlaying(false)}
          onTimeUpdate={(e) => setCurrent(e.currentTarget.currentTime)}
          onLoadedMetadata={(e) => setDuration(e.currentTarget.duration)}
          onEnded={() => {
            setPlaying(false);
            setFinished(true);
          }}
          onError={() =>
            setPlayError("Не удалось загрузить аудиофайл. Проверьте, что файл существует и доступен, и попробуйте ещё раз.")
          }
        />

        <div className="audio-controls">
          <button className="audio-play-btn" onClick={toggle}>
            {playing ? "❚❚" : "▶"}
          </button>
          <input
            className="audio-seek"
            type="range"
            min={0}
            max={duration || 0}
            step={0.1}
            value={current}
            onChange={onSeek}
          />
          <span className="audio-time">
            {formatTime(current)} / {formatTime(duration)}
          </span>
        </div>

        <div className="audio-rate">
          {[0.75, 1, 1.25].map((r) => (
            <button key={r} className={rate === r ? "active" : ""} onClick={() => setPlaybackRate(r)}>
              {r}×
            </button>
          ))}
        </div>

        {playError && <div className="exercise-feedback incorrect">{playError}</div>}
      </div>

      <div className={`video-status ${finished ? "done" : ""}`}>
        {finished ? "✓ Запись прослушана" : "Прослушайте запись до конца, чтобы продолжить"}
      </div>

      <div className="stage-footer">
        <button className="btn btn-primary" onClick={onComplete} disabled={!finished}>
          Перейти к практике →
        </button>
      </div>
    </div>
  );
}
