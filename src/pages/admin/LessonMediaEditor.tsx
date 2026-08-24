import { useState } from "react";
import { MediaLibraryEntry, builderApi } from "../../admin/builderApi";

/**
 * Video/audio replace-or-remove UI, shared between a builder course lesson
 * and a legacy lesson's media override — the caller supplies the already-
 * resolved URL and the upload/remove/reuse actions, so this component knows
 * nothing about where the file actually lives. "Reuse" points this lesson
 * at a file already attached to some other lesson instead of uploading a
 * duplicate — see listMediaLibrary/reuseLessonMedia on the server.
 */
export default function LessonMediaEditor({
  kind,
  url,
  busy,
  onUpload,
  onRemove,
  onReuse,
}: {
  kind: "video" | "audio";
  url: string | null;
  busy: boolean;
  onUpload: (file: File) => void;
  onRemove: () => void;
  onReuse: (url: string) => void;
}) {
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [library, setLibrary] = useState<MediaLibraryEntry[] | null>(null);

  const openLibrary = async () => {
    setLibraryOpen(true);
    if (library === null) {
      const items = await builderApi.listMediaLibrary(kind).catch(() => []);
      setLibrary(items.filter((entry) => entry.url !== url));
    }
  };

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
        <button type="button" className="btn btn-ghost" disabled={busy} onClick={() => (libraryOpen ? setLibraryOpen(false) : openLibrary())}>
          {libraryOpen ? "Скрыть библиотеку" : "Выбрать уже загруженный"}
        </button>
        {url && (
          <button type="button" className="btn btn-ghost admin-row__remove" disabled={busy} onClick={onRemove}>
            Удалить файл
          </button>
        )}
      </div>

      {libraryOpen && (
        <div className="builder-media-library">
          {library === null && <p className="stage-subtitle">Загрузка…</p>}
          {library !== null && library.length === 0 && (
            <p className="stage-subtitle">Других {kind === "video" ? "видео" : "аудио"} файлов пока нет.</p>
          )}
          {library !== null &&
            library.map((entry) => (
              <button
                type="button"
                key={entry.url}
                className="builder-media-library__item"
                disabled={busy}
                onClick={() => {
                  onReuse(entry.url);
                  setLibraryOpen(false);
                }}
              >
                {entry.label}
              </button>
            ))}
        </div>
      )}
    </>
  );
}
