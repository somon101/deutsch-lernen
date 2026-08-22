import { Router } from "express";
import { z } from "zod";
import { Prisma, type User } from "@prisma/client";
import { prisma } from "../db.js";
import { requireAdmin, requireAuth, requireStaff } from "../auth/middleware.js";
import { hashPassword } from "../auth/hash.js";
import { publicUser } from "../serialize.js";
import { getProgressSummaryForUser } from "../progress.js";
import {
  contentPayloadSchema,
  DuplicateWordError,
  getLessonContent,
  normalizeWord,
  saveLegacyCanvasLayout,
  saveLessonContent,
  setLegacyLessonMedia,
} from "../content.js";
import { uploadWordAudio, WORD_AUDIO_DIR, uploadCourseMedia, COURSE_MEDIA_DIR } from "../upload.js";
import fs from "node:fs/promises";
import path from "node:path";
import { normalizeUsername, usernameSchema } from "../username.js";

/** Surfaces the specific validation problem (e.g. why a login was rejected)
 * instead of a generic message the admin can't act on. */
function firstIssue(error: z.ZodError, fallback: string): string {
  return error.issues[0]?.message ?? fallback;
}

/**
 * Prisma reports P2002 without naming the constraint here, so work out
 * which field actually collided rather than guessing — telling an admin
 * "email is taken" when it was really the login is worse than useless.
 */
async function conflictMessage(
  email: string | undefined,
  usernameLower: string | undefined,
  excludeUserId?: string,
): Promise<string> {
  const [emailOwner, usernameOwner] = await Promise.all([
    email ? prisma.user.findUnique({ where: { email } }) : Promise.resolve(null),
    usernameLower ? prisma.user.findUnique({ where: { usernameLower } }) : Promise.resolve(null),
  ]);
  const emailTaken = Boolean(emailOwner && emailOwner.id !== excludeUserId);
  const usernameTaken = Boolean(usernameOwner && usernameOwner.id !== excludeUserId);

  if (emailTaken && usernameTaken) return "Email и логин уже заняты";
  if (usernameTaken) return "Такой логин уже занят (регистр букв не учитывается)";
  if (emailTaken) return "Email уже занят";
  return "Email или логин уже заняты";
}

export const adminRouter = Router();

// User management stays ADMIN-only (see each /users* route below); course
// content editing (mounted further down) is requireStaff — a TEACHER can
// reach that, but not this. Applied per-route rather than once here so the
// split is explicit and can't silently regress if a route is added later.
adminRouter.use(requireAuth);

// A user counts as "online" if lastActiveAt (refreshed on every authenticated
// request they make — see requireAuth) falls inside this window. Kept a bit
// wider than requireAuth's own write-throttle so the indicator doesn't flicker
// offline between two of a user's requests.
const ONLINE_WINDOW_MS = 5 * 60 * 1000; // 5 minutes

function withOnlineStatus(user: User) {
  const online = user.lastActiveAt !== null && Date.now() - user.lastActiveAt.getTime() <= ONLINE_WINDOW_MS;
  return { ...publicUser(user), online };
}

adminRouter.get("/users", requireAdmin, async (_req, res) => {
  const users = await prisma.user.findMany({ orderBy: { createdAt: "desc" } });
  res.json({ users: users.map(withOnlineStatus) });
});

const createUserSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email(),
  phone: z.string().optional(),
  username: usernameSchema,
  password: z.string().min(6),
  role: z.enum(["ADMIN", "TEACHER", "USER"]).default("USER"),
  canEditProfile: z.boolean().default(true),
});

adminRouter.post("/users", requireAdmin, async (req, res) => {
  const parsed = createUserSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные пользователя") });
  }
  const { password, ...rest } = parsed.data;

  try {
    const user = await prisma.user.create({
      data: {
        ...rest,
        usernameLower: normalizeUsername(rest.username),
        passwordHash: await hashPassword(password),
      },
    });
    res.status(201).json({ user: withOnlineStatus(user) });
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
      return res.status(409).json({
        error: await conflictMessage(rest.email, normalizeUsername(rest.username)),
      });
    }
    throw e;
  }
});

adminRouter.get("/users/:id", requireAdmin, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!user) return res.status(404).json({ error: "Пользователь не найден" });
  res.json({ user: withOnlineStatus(user) });
});

const updateUserSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  email: z.string().email().optional(),
  phone: z.string().optional(),
  username: usernameSchema.optional(),
  role: z.enum(["ADMIN", "TEACHER", "USER"]).optional(),
  status: z.enum(["ACTIVE", "BLOCKED"]).optional(),
  canEditProfile: z.boolean().optional(),
});

adminRouter.patch("/users/:id", requireAdmin, async (req, res) => {
  const parsed = updateUserSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные пользователя") });
  }

  // Locking yourself out is unrecoverable through the UI — an admin who
  // blocks or demotes their own account could only be restored directly in
  // the database, so both are refused here. Any role other than ADMIN counts
  // as a demotion (not just "USER") now that TEACHER also exists.
  const isSelf = req.params.id === req.user!.id;
  const isDemotion = parsed.data.role !== undefined && parsed.data.role !== "ADMIN";
  if (isSelf && parsed.data.status === "BLOCKED") {
    return res.status(400).json({ error: "Нельзя заблокировать собственную учётную запись" });
  }
  if (isSelf && isDemotion) {
    return res.status(400).json({ error: "Нельзя снять с себя роль администратора" });
  }

  // Likewise, the course must never be left without a working admin.
  if (!isSelf && (parsed.data.status === "BLOCKED" || isDemotion)) {
    const target = await prisma.user.findUnique({ where: { id: req.params.id } });
    if (target?.role === "ADMIN" && target.status === "ACTIVE") {
      const activeAdmins = await prisma.user.count({ where: { role: "ADMIN", status: "ACTIVE" } });
      if (activeAdmins <= 1) {
        return res.status(400).json({ error: "Это последний активный администратор — действие отменено" });
      }
    }
  }

  try {
    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: {
        ...parsed.data,
        // Keep the case-insensitive key in sync whenever the login changes.
        ...(parsed.data.username ? { usernameLower: normalizeUsername(parsed.data.username) } : {}),
      },
    });
    res.json({ user: withOnlineStatus(user) });
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2025") {
      return res.status(404).json({ error: "Пользователь не найден" });
    }
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
      return res.status(409).json({
        error: await conflictMessage(
          parsed.data.email,
          parsed.data.username ? normalizeUsername(parsed.data.username) : undefined,
          req.params.id,
        ),
      });
    }
    throw e;
  }
});

const resetPasswordSchema = z.object({
  newPassword: z.string().min(6),
});

adminRouter.post("/users/:id/reset-password", requireAdmin, async (req, res) => {
  const parsed = resetPasswordSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Пароль должен быть не короче 6 символов" });

  try {
    await prisma.user.update({
      where: { id: req.params.id },
      data: { passwordHash: await hashPassword(parsed.data.newPassword) },
    });
    res.json({ ok: true });
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2025") {
      return res.status(404).json({ error: "Пользователь не найден" });
    }
    throw e;
  }
});

adminRouter.get("/users/:id/progress", requireAdmin, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!user) return res.status(404).json({ error: "Пользователь не найден" });
  const summary = await getProgressSummaryForUser(user.id);
  res.json({ progress: summary });
});

// Newest-first login history — capped at 50 so a long-lived account's page
// never has to render an unbounded list.
adminRouter.get("/users/:id/logins", requireAdmin, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.params.id }, select: { id: true } });
  if (!user) return res.status(404).json({ error: "Пользователь не найден" });
  const logins = await prisma.loginEvent.findMany({
    where: { userId: user.id },
    orderBy: { createdAt: "desc" },
    take: 50,
    select: { id: true, createdAt: true },
  });
  res.json({ logins });
});

// ---------------------------------------------------------------------------
// Course content editing. requireStaff (ADMIN or TEACHER) rather than
// requireAdmin — a TEACHER has full access to lesson content, just not to
// user management above.
// ---------------------------------------------------------------------------

adminRouter.get("/content/:lessonId", requireStaff, async (req, res) => {
  res.json({ content: await getLessonContent(req.params.lessonId) });
});

// LessonFlowCanvas layout (node positions + edges) — accepted as opaque JSON,
// same reasoning as lessonInputSchema's canvasLayout in courses.ts.
adminRouter.put("/content/:lessonId/layout", requireStaff, async (req, res) => {
  const content = await saveLegacyCanvasLayout(req.params.lessonId, req.body?.layout ?? null);
  res.json({ content });
});

adminRouter.put("/content/:lessonId", requireStaff, async (req, res) => {
  const parsed = contentPayloadSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные урока") });
  }
  try {
    const content = await saveLessonContent(req.params.lessonId, parsed.data, req.user!.id);
    res.json({ content });
  } catch (e) {
    if (e instanceof DuplicateWordError) return res.status(409).json({ error: e.message });
    throw e;
  }
});

// ---- Video/audio override for a legacy lesson ------------------------------
// Null means "use the bundled file" — same override-if-present pattern as
// materialText/vocabulary above, just for the lesson's video/audio.

const legacyMediaKindSchema = z.enum(["video", "audio"]);

adminRouter.post(
  "/content/:lessonId/media",
  requireStaff,
  uploadCourseMedia.single("file"),
  async (req, res) => {
    const kind = legacyMediaKindSchema.safeParse(req.body?.kind);
    if (!kind.success) return res.status(400).json({ error: "Укажите тип файла: video или audio" });
    if (!req.file) return res.status(400).json({ error: "Файл не получен" });

    const existing = await getLessonContent(req.params.lessonId);
    const previousUrl = kind.data === "video" ? existing.videoUrl : existing.audioUrl;

    const content = await setLegacyLessonMedia(
      req.params.lessonId,
      kind.data,
      `/uploads/courses/${req.file.filename}`,
    );
    if (previousUrl) fs.unlink(path.join(COURSE_MEDIA_DIR, path.basename(previousUrl))).catch(() => {});
    res.json({ content });
  },
);

adminRouter.delete("/content/:lessonId/media", requireStaff, async (req, res) => {
  const kind = legacyMediaKindSchema.safeParse(req.query.kind);
  if (!kind.success) return res.status(400).json({ error: "Укажите тип файла: video или audio" });

  const existing = await getLessonContent(req.params.lessonId);
  const previousUrl = kind.data === "video" ? existing.videoUrl : existing.audioUrl;
  if (previousUrl) fs.unlink(path.join(COURSE_MEDIA_DIR, path.basename(previousUrl))).catch(() => {});

  const content = await setLegacyLessonMedia(req.params.lessonId, kind.data, null);
  res.json({ content });
});

// ---- Recorded pronunciation for a single word -----------------------------

/** Locates a word by its normalised form, so casing/punctuation don't matter. */
async function findWord(lessonId: string, german: string) {
  return prisma.vocabularyItem.findFirst({
    where: { lessonId, germanKey: normalizeWord(german) },
  });
}

adminRouter.post("/content/:lessonId/word-audio", requireStaff, uploadWordAudio.single("audio"), async (req, res) => {
  const german = String(req.body?.german ?? "");
  if (!german) return res.status(400).json({ error: "Не указано слово" });
  if (!req.file) return res.status(400).json({ error: "Файл не получен" });

  const word = await findWord(req.params.lessonId, german);
  if (!word) {
    await fs.unlink(path.join(WORD_AUDIO_DIR, req.file.filename)).catch(() => {});
    return res.status(404).json({ error: "Слово не найдено — сначала сохраните словарь" });
  }

  if (word.audioUrl) {
    fs.unlink(path.join(WORD_AUDIO_DIR, path.basename(word.audioUrl))).catch(() => {});
  }
  const updated = await prisma.vocabularyItem.update({
    where: { id: word.id },
    data: { audioUrl: `/uploads/words/${req.file.filename}` },
  });
  res.json({ german: updated.german, audioUrl: updated.audioUrl });
});

adminRouter.delete("/content/:lessonId/word-audio", requireStaff, async (req, res) => {
  const german = String(req.query.german ?? "");
  if (!german) return res.status(400).json({ error: "Не указано слово" });

  const word = await findWord(req.params.lessonId, german);
  if (!word) return res.status(404).json({ error: "Слово не найдено" });

  if (word.audioUrl) {
    fs.unlink(path.join(WORD_AUDIO_DIR, path.basename(word.audioUrl))).catch(() => {});
  }
  await prisma.vocabularyItem.update({ where: { id: word.id }, data: { audioUrl: null } });
  res.json({ german: word.german, audioUrl: null });
});
