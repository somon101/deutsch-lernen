import { Router } from "express";
import { z } from "zod";
import { Prisma } from "@prisma/client";
import { prisma } from "../db.js";
import { requireAdmin, requireAuth } from "../auth/middleware.js";
import { hashPassword } from "../auth/hash.js";
import { publicUser } from "../serialize.js";
import { getProgressSummaryForUser } from "../progress.js";
import {
  contentPayloadSchema,
  DuplicateWordError,
  getLessonContent,
  normalizeWord,
  saveLessonContent,
} from "../content.js";
import { uploadWordAudio, WORD_AUDIO_DIR } from "../upload.js";
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

adminRouter.use(requireAuth, requireAdmin);

adminRouter.get("/users", async (_req, res) => {
  const users = await prisma.user.findMany({ orderBy: { createdAt: "desc" } });
  res.json({ users: users.map(publicUser) });
});

const createUserSchema = z.object({
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  email: z.string().email(),
  phone: z.string().optional(),
  username: usernameSchema,
  password: z.string().min(6),
  role: z.enum(["ADMIN", "USER"]).default("USER"),
  canEditProfile: z.boolean().default(true),
});

adminRouter.post("/users", async (req, res) => {
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
    res.status(201).json({ user: publicUser(user) });
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
      return res.status(409).json({
        error: await conflictMessage(rest.email, normalizeUsername(rest.username)),
      });
    }
    throw e;
  }
});

adminRouter.get("/users/:id", async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!user) return res.status(404).json({ error: "Пользователь не найден" });
  res.json({ user: publicUser(user) });
});

const updateUserSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  email: z.string().email().optional(),
  phone: z.string().optional(),
  username: usernameSchema.optional(),
  role: z.enum(["ADMIN", "USER"]).optional(),
  status: z.enum(["ACTIVE", "BLOCKED"]).optional(),
  canEditProfile: z.boolean().optional(),
});

adminRouter.patch("/users/:id", async (req, res) => {
  const parsed = updateUserSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: firstIssue(parsed.error, "Некорректные данные пользователя") });
  }

  // Locking yourself out is unrecoverable through the UI — an admin who
  // blocks or demotes their own account could only be restored directly in
  // the database, so both are refused here.
  const isSelf = req.params.id === req.user!.id;
  if (isSelf && parsed.data.status === "BLOCKED") {
    return res.status(400).json({ error: "Нельзя заблокировать собственную учётную запись" });
  }
  if (isSelf && parsed.data.role === "USER") {
    return res.status(400).json({ error: "Нельзя снять с себя роль администратора" });
  }

  // Likewise, the course must never be left without a working admin.
  if (!isSelf && (parsed.data.status === "BLOCKED" || parsed.data.role === "USER")) {
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
    res.json({ user: publicUser(user) });
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

adminRouter.post("/users/:id/reset-password", async (req, res) => {
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

adminRouter.get("/users/:id/progress", async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!user) return res.status(404).json({ error: "Пользователь не найден" });
  const summary = await getProgressSummaryForUser(user.id);
  res.json({ progress: summary });
});

// ---------------------------------------------------------------------------
// Course content editing. Mounted on the admin router, so requireAuth +
// requireAdmin above already guard every route here — a USER token cannot
// reach these no matter what the frontend shows.
// ---------------------------------------------------------------------------

adminRouter.get("/content/:lessonId", async (req, res) => {
  res.json({ content: await getLessonContent(req.params.lessonId) });
});

adminRouter.put("/content/:lessonId", async (req, res) => {
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

// ---- Recorded pronunciation for a single word -----------------------------

/** Locates a word by its normalised form, so casing/punctuation don't matter. */
async function findWord(lessonId: string, german: string) {
  return prisma.vocabularyItem.findFirst({
    where: { lessonId, germanKey: normalizeWord(german) },
  });
}

adminRouter.post("/content/:lessonId/word-audio", uploadWordAudio.single("audio"), async (req, res) => {
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

adminRouter.delete("/content/:lessonId/word-audio", async (req, res) => {
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
