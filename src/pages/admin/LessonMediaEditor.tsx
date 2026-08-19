/**
 * Video/audio replace-or-remove UI, shared between a builder course lesson
 * and a legacy lesson's media override — the caller supplies the already-
 * resolved URL and the upload/remove actions, so this component knows
 * nothing about where the file actually lives.
 */
export default function LessonMediaEditor({
  kind,
  url,
  busy,
  onUpload,
  onRemove,
}: {
  kind: "video" | "audio";
  url: string | null;
  busy: boolean;
  onUpload: (file: File) => void;
  onRemove: () => void;
}) {
  return (
    <>
      {url ? (
        kind === "video" ? (
          <video className="builder-media-preview" src={url} controls preload="metadata" />
        ) : (
          <audio src={url} controls preload="none" />
        )
      ) : (
        <p className="stage-subtitle">Файл ещё не загружен.</p>
      )}
      <div className="profile-avatar-actions">
        <label className="btn btn-secondary">
          {url ? "Заменить файл" : "Загрузить файл"}
          <input
            type="file"
            accept={kind === "video" ? "video/mp4,video/webm,video/quicktime" : "audio/*"}
            hidden
            disabled={busy}
            onChange={(e) => {
              const file = e.target.files?.[0];
              e.target.value = "";
              if (file) onUpload(file);
            }}
          />
        </label>
        {url && (
          <button type="button" className="btn btn-ghost admin-row__remove" disabled={busy} onClick={onRemove}>
            Удалить файл
          </button>
        )}
      </div>
    </>
  );
}
