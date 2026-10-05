"""Server-side text-to-speech for the video-lesson constructor, via the
`edge-tts` package (Microsoft Edge neural voices). Returns MP3 bytes plus
per-word timings (WordBoundary), which make the speech timeline exact.

edge-tts talks to an unofficial free endpoint: if Microsoft changes it the
call fails, and the error is reported to the teacher instead of crashing."""

from __future__ import annotations

# Curated per studied language; the first of each is the default.
VOICES: list[dict] = [
    {"id": "de-DE-KatjaNeural", "label": "Немецкий — Katja (жен.)", "lang": "de"},
    {"id": "de-DE-ConradNeural", "label": "Немецкий — Conrad (муж.)", "lang": "de"},
    {"id": "de-DE-AmalaNeural", "label": "Немецкий — Amala (жен.)", "lang": "de"},
    {"id": "en-US-JennyNeural", "label": "Английский — Jenny (жен.)", "lang": "en"},
    {"id": "en-US-GuyNeural", "label": "Английский — Guy (муж.)", "lang": "en"},
    {"id": "en-GB-SoniaNeural", "label": "Английский (UK) — Sonia (жен.)", "lang": "en"},
    {"id": "ru-RU-SvetlanaNeural", "label": "Русский — Светлана (жен.)", "lang": "ru"},
    {"id": "ru-RU-DmitryNeural", "label": "Русский — Дмитрий (муж.)", "lang": "ru"},
    {"id": "zh-CN-XiaoxiaoNeural", "label": "Китайский — Xiaoxiao (жен.)", "lang": "zh"},
    {"id": "zh-CN-YunxiNeural", "label": "Китайский — Yunxi (муж.)", "lang": "zh"},
]
VOICE_IDS = {v["id"] for v in VOICES}
MAX_TEXT_CHARS = 5000


class TtsError(Exception):
    pass


async def synthesize(text: str, voice: str) -> tuple[bytes, list[dict]]:
    """(mp3 bytes, [{"text", "start", "end"} in ms])."""
    try:
        import edge_tts
    except ImportError as e:  # pragma: no cover - deployment issue
        raise TtsError("Озвучка недоступна на сервере (не установлен edge-tts)") from e
    if voice not in VOICE_IDS:
        raise TtsError("Неизвестный голос")
    text = text.strip()
    if not text:
        raise TtsError("Введите текст для озвучки")
    if len(text) > MAX_TEXT_CHARS:
        raise TtsError(f"Текст слишком длинный — не больше {MAX_TEXT_CHARS} символов")

    try:
        communicate = edge_tts.Communicate(text, voice, boundary="WordBoundary")
    except TypeError:  # older edge-tts emits word boundaries by default
        communicate = edge_tts.Communicate(text, voice)

    audio = bytearray()
    words: list[dict] = []
    try:
        async for chunk in communicate.stream():
            kind = chunk.get("type")
            if kind == "audio":
                audio.extend(chunk["data"])
            elif kind == "WordBoundary":
                start = int(chunk["offset"]) // 10_000  # 100-ns ticks -> ms
                end = start + int(chunk["duration"]) // 10_000
                words.append({"text": chunk.get("text", ""), "start": start, "end": end})
    except Exception as e:  # noqa: BLE001 - network/protocol errors from the service
        raise TtsError(f"Сервис озвучки не ответил: {e}") from e
    if not audio:
        raise TtsError("Сервис озвучки вернул пустой результат")
    return bytes(audio), words
