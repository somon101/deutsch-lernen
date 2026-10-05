"""Video-lesson constructor API (staff): per-course list, speech source
(audio upload or TTS text), speech timeline."""

import asyncio

import httpx
from fastapi import APIRouter, Depends, File, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_staff
from app.db import get_db
from app.errors import ApiError
from app.models.course import Course
from app.models.video_lesson import VideoLesson
from app.services import speech_timeline, tts
from app.uploads.storage import COURSE_MEDIA_DIR, COURSE_MEDIA_MAX_BYTES, store_course_media_bytes
from app.utils import utcnow

router = APIRouter(prefix="/api/builder", tags=["video-lessons"], dependencies=[Depends(require_staff)])

AUDIO_MIME = {
    "audio/mpeg": ".mp3",
    "audio/mp3": ".mp3",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/wave": ".wav",
    "audio/ogg": ".ogg",
    "audio/mp4": ".m4a",
    "audio/x-m4a": ".m4a",
    "audio/webm": ".webm",
}
EXT_MIME = {".mp3": "audio/mpeg", ".wav": "audio/wav", ".ogg": "audio/ogg", ".m4a": "audio/mp4", ".webm": "audio/webm"}
CHARACTERS = {"cloud"}


class VideoLessonCreate(BaseModel):
    title: str = Field(default="Видеоурок", min_length=1, max_length=200)


class VideoLessonUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    sourceType: str | None = Field(default=None, pattern="^(audio|text)$")
    text: str | None = Field(default=None, max_length=tts.MAX_TEXT_CHARS)
    voice: str | None = None
    characterId: str | None = None
    animationSettings: dict | None = None


class TtsInput(BaseModel):
    text: str = Field(min_length=1, max_length=tts.MAX_TEXT_CHARS)
    voice: str


ANIMATION_NUMBERS = {"gestureIntensity", "headMotion", "expressiveness", "blinkRate"}


def _clean_settings(raw: dict | None) -> dict | None:
    """Only known knobs, numbers clamped to 0..2, so a client can't store junk."""
    if raw is None:
        return None
    out: dict = {}
    for key in ANIMATION_NUMBERS:
        value = raw.get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            out[key] = max(0.0, min(2.0, float(value)))
    if isinstance(raw.get("gestures"), bool):
        out["gestures"] = raw["gestures"]
    return out


def _dto(v: VideoLesson, *, with_timeline: bool = True) -> dict:
    out = {
        "id": v.id,
        "courseId": v.courseId,
        "title": v.title,
        "characterId": v.characterId,
        "sourceType": v.sourceType,
        "text": v.text,
        "voice": v.voice,
        "audioUrl": v.audioUrl,
        "durationMs": v.durationMs,
        "status": v.status,
        "error": v.error,
        "updatedAt": v.updatedAt.isoformat() if v.updatedAt else None,
    }
    out["animationSettings"] = v.animationSettings
    if with_timeline:
        out["timeline"] = v.timeline
    return out


async def _get(db: AsyncSession, course_id: str, video_id: str) -> VideoLesson:
    v = await db.get(VideoLesson, video_id)
    if not v or v.courseId != course_id:
        raise ApiError(404, "Видеоурок не найден")
    return v


def _apply_timeline(v: VideoLesson, timeline: dict) -> None:
    v.timeline = timeline
    v.durationMs = timeline.get("durationMs")
    if not timeline.get("segments"):
        v.status = "error"
        v.error = "В аудио не найдено речи — персонаж будет молчать. Проверьте файл или громкость записи."
    else:
        v.status = "ready"
        v.error = None


@router.get("/tts/voices")
async def list_voices():
    return {"voices": tts.VOICES}


@router.get("/courses/{course_id}/video-lessons")
async def list_video_lessons(course_id: str, db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(VideoLesson).where(VideoLesson.courseId == course_id).order_by(VideoLesson.createdAt))).scalars().all()
    return {"videoLessons": [_dto(v, with_timeline=False) for v in rows]}


@router.post("/courses/{course_id}/video-lessons", status_code=201)
async def create_video_lesson(course_id: str, body: VideoLessonCreate, db: AsyncSession = Depends(get_db)):
    if not await db.get(Course, course_id):
        raise ApiError(404, "Курс не найден")
    now = utcnow()
    v = VideoLesson(courseId=course_id, title=body.title.strip(), createdAt=now, updatedAt=now)
    db.add(v)
    await db.commit()
    await db.refresh(v)
    return {"videoLesson": _dto(v)}


@router.get("/courses/{course_id}/video-lessons/{video_id}")
async def get_video_lesson(course_id: str, video_id: str, db: AsyncSession = Depends(get_db)):
    return {"videoLesson": _dto(await _get(db, course_id, video_id))}


@router.patch("/courses/{course_id}/video-lessons/{video_id}")
async def update_video_lesson(course_id: str, video_id: str, body: VideoLessonUpdate, db: AsyncSession = Depends(get_db)):
    v = await _get(db, course_id, video_id)
    changes = body.model_dump(exclude_unset=True)
    if "characterId" in changes and changes["characterId"] not in CHARACTERS:
        raise ApiError(400, "Неизвестный персонаж")
    if "voice" in changes and changes["voice"] is not None and changes["voice"] not in tts.VOICE_IDS:
        raise ApiError(400, "Неизвестный голос")
    if "animationSettings" in changes:
        changes["animationSettings"] = _clean_settings(changes["animationSettings"])
    for key, value in changes.items():
        setattr(v, key, value.strip() if isinstance(value, str) and key == "title" else value)
    v.updatedAt = utcnow()
    await db.commit()
    await db.refresh(v)
    return {"videoLesson": _dto(v)}


@router.delete("/courses/{course_id}/video-lessons/{video_id}")
async def delete_video_lesson(course_id: str, video_id: str, db: AsyncSession = Depends(get_db)):
    v = await _get(db, course_id, video_id)
    await db.delete(v)
    await db.commit()
    return {"ok": True}


@router.post("/courses/{course_id}/video-lessons/{video_id}/audio")
async def upload_audio(course_id: str, video_id: str, audio: UploadFile = File(...), db: AsyncSession = Depends(get_db)):
    v = await _get(db, course_id, video_id)
    ext = AUDIO_MIME.get(audio.content_type or "")
    if ext is None:
        name = (audio.filename or "").lower()
        ext = next((e for e in EXT_MIME if name.endswith(e)), None)
    if ext is None:
        raise ApiError(400, "Разрешены только аудиофайлы MP3, WAV, OGG, M4A или WebM")
    content = await audio.read()
    if len(content) > COURSE_MEDIA_MAX_BYTES:
        raise ApiError(400, "Файл слишком большой")
    try:
        timeline = await asyncio.to_thread(speech_timeline.analyze_audio, content)
    except speech_timeline.SpeechAnalysisError as e:
        v.status, v.error = "error", str(e)
        v.updatedAt = utcnow()
        await db.commit()
        raise ApiError(400, str(e))
    v.audioUrl = await store_course_media_bytes(content, ext, EXT_MIME[ext])
    v.sourceType = "audio"
    _apply_timeline(v, timeline)
    v.updatedAt = utcnow()
    await db.commit()
    await db.refresh(v)
    return {"videoLesson": _dto(v)}


@router.post("/courses/{course_id}/video-lessons/{video_id}/tts")
async def synthesize_text(course_id: str, video_id: str, body: TtsInput, db: AsyncSession = Depends(get_db)):
    v = await _get(db, course_id, video_id)
    if body.voice not in tts.VOICE_IDS:
        raise ApiError(400, "Неизвестный голос")
    try:
        audio_bytes, words = await tts.synthesize(body.text, body.voice)
    except tts.TtsError as e:
        raise ApiError(502, str(e))
    # Real envelope when the mp3 can be decoded (ffmpeg); otherwise the
    # exact word timings from TTS still give a correct speech/silence map.
    try:
        timeline = await asyncio.to_thread(speech_timeline.analyze_audio, audio_bytes, words)
    except speech_timeline.SpeechAnalysisError:
        timeline = speech_timeline.timeline_from_words(words)
    v.audioUrl = await store_course_media_bytes(audio_bytes, ".mp3", "audio/mpeg")
    v.sourceType, v.text, v.voice = "text", body.text.strip(), body.voice
    _apply_timeline(v, timeline)
    v.updatedAt = utcnow()
    await db.commit()
    await db.refresh(v)
    return {"videoLesson": _dto(v)}


async def _read_stored_audio(url: str) -> bytes:
    if url.startswith("/uploads/"):
        path = COURSE_MEDIA_DIR / url.rsplit("/", 1)[-1]
        if not path.exists():
            raise ApiError(404, "Аудиофайл не найден")
        return path.read_bytes()
    async with httpx.AsyncClient(timeout=120) as client:
        response = await client.get(url)
    if response.status_code != 200:
        raise ApiError(502, "Не удалось загрузить сохранённое аудио")
    return response.content


@router.post("/courses/{course_id}/video-lessons/{video_id}/reanalyze")
async def reanalyze(course_id: str, video_id: str, db: AsyncSession = Depends(get_db)):
    """Rebuilds the timeline (incl. visemes) from the already stored audio —
    for lessons analysed before lip-sync existed, or after an upgrade."""
    v = await _get(db, course_id, video_id)
    if not v.audioUrl:
        raise ApiError(400, "Сначала загрузите аудио или озвучьте текст")
    data = await _read_stored_audio(v.audioUrl)
    words = (v.timeline or {}).get("words") or None
    try:
        timeline = await asyncio.to_thread(speech_timeline.analyze_audio, data, words)
    except speech_timeline.SpeechAnalysisError as e:
        if not words:
            raise ApiError(400, str(e))
        timeline = speech_timeline.timeline_from_words(words)
    _apply_timeline(v, timeline)
    v.updatedAt = utcnow()
    await db.commit()
    await db.refresh(v)
    return {"videoLesson": _dto(v)}
