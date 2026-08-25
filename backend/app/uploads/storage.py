"""Exact port of server/src/upload.ts's 3 multer configurations. Writes to
the SAME physical directory the Express server uses (server/uploads/), not
a separate copy — so a file uploaded through either backend during the
parallel-run migration period is immediately visible through the other,
and nothing needs to be synced/copied between them."""

import uuid
from pathlib import Path

from fastapi import UploadFile

from app.errors import ApiError

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
UPLOADS_ROOT = _REPO_ROOT / "server" / "uploads"
AVATARS_DIR = UPLOADS_ROOT / "avatars"
WORD_AUDIO_DIR = UPLOADS_ROOT / "words"
COURSE_MEDIA_DIR = UPLOADS_ROOT / "courses"

for _dir in (AVATARS_DIR, WORD_AUDIO_DIR, COURSE_MEDIA_DIR):
    _dir.mkdir(parents=True, exist_ok=True)

AVATAR_MIME = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}
AVATAR_MAX_BYTES = 3 * 1024 * 1024

WORD_AUDIO_MIME = {
    "audio/mpeg": ".mp3",
    "audio/mp3": ".mp3",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/webm": ".webm",
    "audio/ogg": ".ogg",
    "audio/mp4": ".m4a",
    "audio/x-m4a": ".m4a",
}
WORD_AUDIO_MAX_BYTES = 2 * 1024 * 1024

COURSE_MEDIA_MIME = {
    "video/mp4": ".mp4",
    "video/webm": ".webm",
    "video/quicktime": ".mov",
    "audio/mpeg": ".mp3",
    "audio/mp3": ".mp3",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/ogg": ".ogg",
    "audio/mp4": ".m4a",
    "audio/x-m4a": ".m4a",
    "audio/webm": ".webm",
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}
COURSE_MEDIA_MAX_BYTES = 200 * 1024 * 1024


async def _save(file: UploadFile, directory: Path, mime_map: dict[str, str], max_bytes: int, error_message: str) -> str:
    """Reads, validates, and writes the upload; returns the generated
    filename (not the full path — callers build the /uploads/... URL)."""
    ext = mime_map.get(file.content_type or "")
    if ext is None:
        raise ApiError(400, error_message)

    content = await file.read()
    if len(content) > max_bytes:
        raise ApiError(400, "Файл слишком большой")

    filename = f"{uuid.uuid4()}{ext}"
    (directory / filename).write_bytes(content)
    return filename


async def save_avatar(file: UploadFile) -> str:
    return await _save(file, AVATARS_DIR, AVATAR_MIME, AVATAR_MAX_BYTES, "Разрешены только изображения JPEG, PNG или WebP")


async def save_word_audio(file: UploadFile) -> str:
    return await _save(file, WORD_AUDIO_DIR, WORD_AUDIO_MIME, WORD_AUDIO_MAX_BYTES, "Разрешены только аудиофайлы MP3, WAV, OGG, M4A или WebM")


async def save_course_media(file: UploadFile) -> str:
    return await _save(file, COURSE_MEDIA_DIR, COURSE_MEDIA_MIME, COURSE_MEDIA_MAX_BYTES, "Неподдерживаемый формат файла")


def delete_file(directory: Path, filename_or_url: str) -> None:
    """Best-effort delete, mirroring the Node side's fs.unlink(...).catch(()
    => {}) — never raises."""
    try:
        name = filename_or_url.rsplit("/", 1)[-1]
        (directory / name).unlink(missing_ok=True)
    except OSError:
        pass
