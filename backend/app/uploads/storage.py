"""Uploads for avatars, word audio, and course media.

Locally (and during the Express/FastAPI parallel-run period) files live in
server/uploads/. In production they go to a public Supabase Storage bucket
when SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are set — so the API can
run on Fly/Cloud Run without a persistent disk.
"""

import uuid
from pathlib import Path

import httpx
from fastapi import UploadFile

from app.config import settings
from app.errors import ApiError
from app.uploads.images import encode_if_smaller

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
UPLOADS_ROOT = _REPO_ROOT / "server" / "uploads"
AVATARS_DIR = UPLOADS_ROOT / "avatars"
WORD_AUDIO_DIR = UPLOADS_ROOT / "words"
# Same "words" folder as audio (§ word cards, 2026-08-31) - just a
# WORD_IMAGES_DIR subfolder under it rather than a new top-level uploads
# category, since both are per-word-card media.
WORD_IMAGES_DIR = WORD_AUDIO_DIR / "images"
COURSE_MEDIA_DIR = UPLOADS_ROOT / "courses"

for _dir in (AVATARS_DIR, WORD_AUDIO_DIR, WORD_IMAGES_DIR, COURSE_MEDIA_DIR):
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

# Same allowed types/size as avatars (§ word cards, 2026-08-31) - a word's
# photo is exactly the same kind of asset.
WORD_IMAGE_MIME = AVATAR_MIME
WORD_IMAGE_MAX_BYTES = AVATAR_MAX_BYTES

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


def _object_path(folder: str, filename: str) -> str:
    return f"{folder}/{filename}"


def public_url(folder: str, filename: str) -> str:
    if settings.supabase_storage_enabled:
        base = settings.supabase_url.rstrip("/")
        bucket = settings.supabase_storage_bucket
        return f"{base}/storage/v1/object/public/{bucket}/{_object_path(folder, filename)}"
    return f"/uploads/{folder}/{filename}"


def _storage_headers() -> dict[str, str]:
    key = settings.supabase_service_role_key
    return {"Authorization": f"Bearer {key}", "apikey": key}


async def ensure_storage_bucket() -> None:
    """Creates the public uploads bucket if it is missing. Safe to call on
    every boot — 409 (already exists) is ignored."""
    if not settings.supabase_storage_enabled:
        return
    base = settings.supabase_url.rstrip("/")
    bucket = settings.supabase_storage_bucket
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{base}/storage/v1/bucket",
            headers={**_storage_headers(), "Content-Type": "application/json"},
            json={"id": bucket, "name": bucket, "public": True},
        )
        if response.status_code not in (200, 201, 409):
            print(f"Supabase Storage bucket ensure failed: {response.status_code} {response.text}")


# Every uploaded object is named after a fresh uuid4 and is never rewritten
# in place, so a given URL always returns the same bytes — the exact case
# `immutable` exists for. Without this Supabase serves `cache-control:
# no-cache`, and a lesson re-downloaded its word photos in full on every
# single pass: around a megabyte per card, seconds of blank card each time
# (§ word photos appear late, 2026-09-02). A year is the conventional cap.
_UPLOAD_CACHE_CONTROL = "public, max-age=31536000, immutable"


async def _upload_bytes(folder: str, filename: str, content: bytes, content_type: str) -> None:
    base = settings.supabase_url.rstrip("/")
    bucket = settings.supabase_storage_bucket
    async with httpx.AsyncClient(timeout=300.0) as client:
        response = await client.post(
            f"{base}/storage/v1/object/{bucket}/{_object_path(folder, filename)}",
            headers={
                **_storage_headers(),
                "Content-Type": content_type,
                "x-upsert": "true",
                # Supabase reads the max-age from this header and serves it
                # back on every download of the object.
                "cache-control": _UPLOAD_CACHE_CONTROL,
            },
            content=content,
        )
        if response.status_code not in (200, 201):
            raise ApiError(500, "Не удалось сохранить файл")


async def _save(
    file: UploadFile,
    directory: Path,
    mime_map: dict[str, str],
    max_bytes: int,
    error_message: str,
    *,
    reencode_images: bool = False,
) -> str:
    """Reads and validates the upload; returns the URL stored on the user /
    course / word row (relative /uploads/... locally, or a public Supabase
    URL in production).

    `reencode_images` turns on the WebP conversion for the photo uploads
    (§ word photo weight, 2026-09-02). It never applies to audio or video,
    and even where it is on, an upload that would not get smaller is stored
    exactly as it arrived.
    """
    ext = mime_map.get(file.content_type or "")
    if ext is None:
        raise ApiError(400, error_message)

    content = await file.read()
    # The size limit is checked against what was UPLOADED, before any
    # re-encode — otherwise compression would quietly raise the real ceiling
    # and a 20 MB original would sneak through by becoming small.
    if len(content) > max_bytes:
        raise ApiError(400, "Файл слишком большой")

    content_type = file.content_type or "application/octet-stream"
    if reencode_images:
        converted = encode_if_smaller(content)
        if converted is not None:
            content, ext, content_type = converted

    filename = f"{uuid.uuid4()}{ext}"
    folder = directory.name
    if settings.supabase_storage_enabled:
        await _upload_bytes(folder, filename, content, content_type)
    else:
        (directory / filename).write_bytes(content)
    return public_url(folder, filename)


async def save_avatar(file: UploadFile) -> str:
    return await _save(
        file, AVATARS_DIR, AVATAR_MIME, AVATAR_MAX_BYTES, "Разрешены только изображения JPEG, PNG или WebP", reencode_images=True
    )


async def save_word_audio(file: UploadFile) -> str:
    return await _save(file, WORD_AUDIO_DIR, WORD_AUDIO_MIME, WORD_AUDIO_MAX_BYTES, "Разрешены только аудиофайлы MP3, WAV, OGG, M4A или WebM")


async def save_word_image(file: UploadFile) -> str:
    return await _save(
        file,
        WORD_IMAGES_DIR,
        WORD_IMAGE_MIME,
        WORD_IMAGE_MAX_BYTES,
        "Разрешены только изображения JPEG, PNG или WebP",
        reencode_images=True,
    )


async def save_course_media(file: UploadFile) -> str:
    return await _save(file, COURSE_MEDIA_DIR, COURSE_MEDIA_MIME, COURSE_MEDIA_MAX_BYTES, "Неподдерживаемый формат файла")


def delete_file(directory: Path, filename_or_url: str) -> None:
    """Best-effort delete, mirroring the Node side's fs.unlink(...).catch(()
    => {}) — never raises."""
    name = filename_or_url.rsplit("/", 1)[-1]
    if not name:
        return
    if settings.supabase_storage_enabled:
        try:
            base = settings.supabase_url.rstrip("/")
            bucket = settings.supabase_storage_bucket
            path = _object_path(directory.name, name)
            httpx.delete(
                f"{base}/storage/v1/object/{bucket}/{path}",
                headers=_storage_headers(),
                timeout=30.0,
            )
        except httpx.HTTPError:
            pass
        return
    try:
        (directory / name).unlink(missing_ok=True)
    except OSError:
        pass
