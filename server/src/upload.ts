import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import multer from "multer";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const AVATARS_DIR = path.join(__dirname, "..", "uploads", "avatars");
export const WORD_AUDIO_DIR = path.join(__dirname, "..", "uploads", "words");
/** Video, audio and cover images for courses built in the admin panel. */
export const COURSE_MEDIA_DIR = path.join(__dirname, "..", "uploads", "courses");

// A freshly mounted persistent disk starts out empty, so the directory has
// to be (re)created at boot or the first upload fails with ENOENT.
fs.mkdirSync(AVATARS_DIR, { recursive: true });
fs.mkdirSync(WORD_AUDIO_DIR, { recursive: true });
fs.mkdirSync(COURSE_MEDIA_DIR, { recursive: true });

const ALLOWED_MIME: Record<string, string> = {
  "image/jpeg": ".jpg",
  "image/png": ".png",
  "image/webp": ".webp",
};

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, AVATARS_DIR),
  filename: (_req, file, cb) => {
    const ext = ALLOWED_MIME[file.mimetype] ?? "";
    cb(null, `${randomUUID()}${ext}`);
  },
});

export const uploadAvatar = multer({
  storage,
  limits: { fileSize: 3 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED_MIME[file.mimetype]) {
      cb(new Error("Разрешены только изображения JPEG, PNG или WebP"));
      return;
    }
    cb(null, true);
  },
});

const ALLOWED_AUDIO: Record<string, string> = {
  "audio/mpeg": ".mp3",
  "audio/mp3": ".mp3",
  "audio/wav": ".wav",
  "audio/x-wav": ".wav",
  "audio/webm": ".webm",
  "audio/ogg": ".ogg",
  "audio/mp4": ".m4a",
  "audio/x-m4a": ".m4a",
};

const wordAudioStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, WORD_AUDIO_DIR),
  filename: (_req, file, cb) => cb(null, `${randomUUID()}${ALLOWED_AUDIO[file.mimetype] ?? ""}`),
});

export const uploadWordAudio = multer({
  storage: wordAudioStorage,
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED_AUDIO[file.mimetype]) {
      cb(new Error("Разрешены только аудиофайлы MP3, WAV, OGG, M4A или WebM"));
      return;
    }
    cb(null, true);
  },
});

const COURSE_MEDIA_MIME: Record<string, string> = {
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
};

const courseMediaStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, COURSE_MEDIA_DIR),
  filename: (_req, file, cb) => cb(null, `${randomUUID()}${COURSE_MEDIA_MIME[file.mimetype] ?? ""}`),
});

/** Lesson video/audio and course covers. Videos dominate the size limit. */
export const uploadCourseMedia = multer({
  storage: courseMediaStorage,
  limits: { fileSize: 200 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!COURSE_MEDIA_MIME[file.mimetype]) {
      cb(new Error("Неподдерживаемый формат файла"));
      return;
    }
    cb(null, true);
  },
});
