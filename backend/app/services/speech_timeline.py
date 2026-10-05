"""Speech timeline for the video-lesson constructor: where in an audio file
someone is speaking and how loud, so the character's mouth moves only while
there is speech and stays closed in pauses.

Format (version 1) — consumed by the Flutter preview, and deliberately
extensible:
    {"version": 1, "frameMs": 20, "durationMs": N,
     "envelope": [0..100 per frame, 0 outside speech],
     "segments": [{"start": ms, "end": ms}, ...],
     "words": [{"text", "start", "end"}, ...] | [],
     "visemes": [{"start", "end", "shape"}, ...],   # mouth shapes A-H, X
     "visemeSource": "rhubarb" | "envelope"}

Visemes come from Rhubarb Lip Sync (phonetic recognizer, language
independent) when its binary is available (RHUBARB_PATH or `rhubarb` on
PATH); otherwise they are derived from loudness, so the preview still
works, just with fewer distinct mouth shapes.

Decoding: WAV through the standard `wave` module; anything else (mp3, m4a,
ogg, webm) through ffmpeg to 16 kHz mono PCM. Pure Python RMS — no numpy.
"""

from __future__ import annotations

import array
import io
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

FRAME_MS = 20
SAMPLE_RATE = 16000
HANGOVER_FRAMES = 6  # keep the mouth open ~120 ms after the voice drops
MIN_GAP_FRAMES = 8  # pauses shorter than ~160 ms are breaths inside speech
MIN_SPEECH_FRAMES = 4  # blips shorter than ~80 ms are clicks, not speech


class SpeechAnalysisError(Exception):
    """A message a teacher can act on (bad file, no speech, no decoder)."""


def _wav_to_samples(data: bytes) -> tuple[list[float], int]:
    try:
        with wave.open(io.BytesIO(data)) as w:
            channels, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(n)
    except (wave.Error, EOFError) as e:
        raise SpeechAnalysisError(f"Не удалось прочитать WAV-файл: {e}") from e
    if width == 1:
        values = [(b - 128) / 128.0 for b in raw]
    elif width == 2:
        a = array.array("h"); a.frombytes(raw[: len(raw) - len(raw) % 2])
        if sys.byteorder == "big":
            a.byteswap()
        values = [v / 32768.0 for v in a]
    elif width == 3:
        values = [int.from_bytes(raw[i : i + 3], "little", signed=True) / 8388608.0 for i in range(0, len(raw) - 2, 3)]
    elif width == 4:
        a = array.array("i"); a.frombytes(raw[: len(raw) - len(raw) % 4])
        if sys.byteorder == "big":
            a.byteswap()
        values = [v / 2147483648.0 for v in a]
    else:
        raise SpeechAnalysisError("Неподдерживаемый формат WAV")
    if channels > 1:
        values = [sum(values[i : i + channels]) / channels for i in range(0, len(values) - channels + 1, channels)]
    return values, rate


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def _ffmpeg_to_samples(data: bytes) -> tuple[list[float], int]:
    if not ffmpeg_available():
        raise SpeechAnalysisError("На сервере нет декодера для этого формата (ffmpeg). Загрузите WAV или обратитесь к администратору.")
    try:
        proc = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "s16le", "-ac", "1", "-ar", str(SAMPLE_RATE), "pipe:1"],
            input=data,
            capture_output=True,
            timeout=120,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        raise SpeechAnalysisError("Аудио обрабатывается слишком долго — попробуйте файл короче") from e
    if proc.returncode != 0 or not proc.stdout:
        raise SpeechAnalysisError("Не удалось прочитать аудиофайл — он повреждён или в неизвестном формате")
    a = array.array("h"); a.frombytes(proc.stdout[: len(proc.stdout) - len(proc.stdout) % 2])
    if sys.byteorder == "big":
        a.byteswap()
    return [v / 32768.0 for v in a], SAMPLE_RATE


def decode_audio(data: bytes) -> tuple[list[float], int]:
    if not data:
        raise SpeechAnalysisError("Файл пустой")
    if data[:4] == b"RIFF" and data[8:12] == b"WAVE":
        return _wav_to_samples(data)
    return _ffmpeg_to_samples(data)


def _percentile(sorted_values: list[float], q: float) -> float:
    if not sorted_values:
        return 0.0
    i = min(len(sorted_values) - 1, max(0, int(round(q * (len(sorted_values) - 1)))))
    return sorted_values[i]


def _segments_from_flags(flags: list[bool]) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    start = None
    for i, f in enumerate(flags):
        if f and start is None:
            start = i
        elif not f and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(flags)))
    return out


def analyze_samples(samples: list[float], rate: int, words: list[dict] | None = None) -> dict:
    frame = max(1, int(rate * FRAME_MS / 1000))
    n_frames = len(samples) // frame
    duration_ms = int(len(samples) * 1000 / rate) if rate else 0
    if n_frames == 0:
        raise SpeechAnalysisError("Аудио слишком короткое")

    db: list[float] = []
    for f in range(n_frames):
        chunk = samples[f * frame : (f + 1) * frame]
        rms = math.sqrt(sum(s * s for s in chunk) / len(chunk))
        db.append(20 * math.log10(rms + 1e-9))

    ordered = sorted(db)
    floor = _percentile(ordered, 0.10)
    peak = _percentile(ordered, 0.98)
    if peak < -50 or peak - floor < 8:
        return _timeline(duration_ms, [0] * n_frames, [], words)

    threshold = floor + max(6.0, 0.30 * (peak - floor))
    flags = [d > threshold for d in db]

    # hangover: the mouth closes a moment after the voice, not instantly
    held = flags[:]
    last = -10**9
    for i, f in enumerate(flags):
        if f:
            last = i
        elif i - last <= HANGOVER_FRAMES:
            held[i] = True

    segs = _segments_from_flags(held)
    merged: list[list[int]] = []
    for s, e in segs:
        if merged and s - merged[-1][1] < MIN_GAP_FRAMES:
            merged[-1][1] = e
        else:
            merged.append([s, e])
    merged = [[s, e] for s, e in merged if e - s >= MIN_SPEECH_FRAMES]

    span = max(1e-6, peak - threshold)
    envelope = [0] * n_frames
    for s, e in merged:
        for i in range(s, e):
            level = (db[i] - threshold) / span
            envelope[i] = int(round(100 * min(1.0, max(0.0, level))))

    segments = [{"start": s * FRAME_MS, "end": min(duration_ms, e * FRAME_MS)} for s, e in merged]
    return _timeline(duration_ms, envelope, segments, words)


def _timeline(duration_ms: int, envelope: list[int], segments: list[dict], words: list[dict] | None) -> dict:
    return {
        "version": 2,
        "frameMs": FRAME_MS,
        "durationMs": duration_ms,
        "envelope": envelope,
        "segments": segments,
        "words": words or [],
        "visemes": _visemes_from_envelope(envelope, segments),
        "visemeSource": "envelope",
    }


def _visemes_from_envelope(envelope: list[int], segments: list[dict]) -> list[dict]:
    """Loudness-only fallback: louder -> more open shape (B < C < D), with
    a short closed shape between syllables. X (rest) outside speech."""
    out: list[dict] = []

    def push(start: int, end: int, shape: str) -> None:
        if end <= start:
            return
        if out and out[-1]["shape"] == shape and out[-1]["end"] == start:
            out[-1]["end"] = end
        else:
            out.append({"start": start, "end": end, "shape": shape})

    cursor = 0
    for seg in segments:
        push(cursor, seg["start"], "X")
        for i in range(seg["start"] // FRAME_MS, max(seg["start"] // FRAME_MS, seg["end"] // FRAME_MS)):
            level = envelope[i] if i < len(envelope) else 0
            shape = "A" if level < 12 else "B" if level < 40 else "C" if level < 70 else "D"
            push(i * FRAME_MS, (i + 1) * FRAME_MS, shape)
        cursor = seg["end"]
    total = len(envelope) * FRAME_MS
    push(cursor, total, "X")
    return out


def rhubarb_path() -> str | None:
    configured = os.environ.get("RHUBARB_PATH")
    if configured and os.path.exists(configured):
        return configured
    return shutil.which("rhubarb")


def _wav_bytes(samples: list[float], rate: int) -> bytes:
    a = array.array("h", (int(max(-1.0, min(1.0, v)) * 32767) for v in samples))
    if sys.byteorder == "big":
        a.byteswap()
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(a.tobytes())
    return buf.getvalue()


def rhubarb_visemes(samples: list[float], rate: int) -> list[dict] | None:
    """Phoneme-based mouth cues from Rhubarb, or None if it isn't installed
    or fails (the caller then keeps the loudness-based visemes)."""
    exe = rhubarb_path()
    if not exe:
        return None
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "speech.wav")
        out_path = os.path.join(tmp, "cues.json")
        with open(wav_path, "wb") as f:
            f.write(_wav_bytes(samples, rate))
        try:
            proc = subprocess.run(
                [exe, "-q", "-f", "json", "--recognizer", "phonetic", "-o", out_path, wav_path],
                capture_output=True,
                timeout=540,
                check=False,
            )
        except (subprocess.TimeoutExpired, OSError):
            return None
        if proc.returncode != 0 or not os.path.exists(out_path):
            return None
        try:
            with open(out_path, encoding="utf-8") as f:
                cues = json.load(f).get("mouthCues", [])
        except (OSError, ValueError):
            return None
    return [{"start": int(round(c["start"] * 1000)), "end": int(round(c["end"] * 1000)), "shape": c["value"]} for c in cues]


def analyze_audio(data: bytes, words: list[dict] | None = None) -> dict:
    samples, rate = decode_audio(data)
    timeline = analyze_samples(samples, rate, words)
    if timeline["segments"]:
        visemes = rhubarb_visemes(samples, rate)
        if visemes:
            timeline["visemes"] = visemes
            timeline["visemeSource"] = "rhubarb"
    return timeline


def timeline_from_words(words: list[dict], duration_ms: int | None = None) -> dict:
    """Fallback when the audio can't be decoded but word timings are known
    (TTS): speech segments are the words (short gaps merged), and the
    envelope rises and falls inside each word like syllables."""
    if not words:
        raise SpeechAnalysisError("Озвучка не вернула ни одного слова")
    end_ms = duration_ms or max(w["end"] for w in words) + 300
    n = max(1, end_ms // FRAME_MS)
    envelope = [0] * n
    segs: list[list[int]] = []
    for w in words:
        s, e = w["start"], w["end"]
        if segs and s - segs[-1][1] < MIN_GAP_FRAMES * FRAME_MS:
            segs[-1][1] = max(segs[-1][1], e)
        else:
            segs.append([s, e])
        length = max(1, (e - s) // FRAME_MS)
        syllables = max(1, round(len(w.get("text", "")) / 3))
        for k in range(length):
            i = s // FRAME_MS + k
            if 0 <= i < n:
                phase = (k / length) * syllables * math.pi
                envelope[i] = max(envelope[i], int(35 + 65 * abs(math.sin(phase))))
    return _timeline(end_ms, envelope, [{"start": s, "end": e} for s, e in segs], words)
