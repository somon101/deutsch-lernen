import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import multer from "multer";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const AVATARS_DIR = path.join(__dirname, "..", "uploads", "avatars");

// A freshly mounted persistent disk starts out empty, so the directory has
// to be (re)created at boot or the first upload fails with ENOENT.
fs.mkdirSync(AVATARS_DIR, { recursive: true });

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
