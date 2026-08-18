import { Router } from "express";
import fs from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { prisma } from "../db.js";
import { requireAuth } from "../auth/middleware.js";
import { publicUser } from "../serialize.js";
import { AVATARS_DIR, uploadAvatar } from "../upload.js";
import { computeScore, getProgressSummaryForUser } from "../progress.js";
import { toDTO } from "../lessonState.js";

export const meRouter = Router();

meRouter.use(requireAuth);

meRouter.get("/", async (req, res) => {
  res.json({ user: publicUser(req.user!) });
});

const updateProfileSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  email: z.string().email().optional(),
  phone: z.string().optional(),
});

meRouter.patch("/", async (req, res) => {
  const user = req.user!;
  // Server-side enforcement of the admin-controlled edit permission — not
  // just hidden on the frontend.
  if (!user.canEditProfile) {
    return res.status(403).json({ error: "Редактирование профиля отключено администратором" });
  }

  const parsed = updateProfileSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Некорректные данные профиля" });

  const updated = await prisma.user.update({
    where: { id: user.id },
    data: parsed.data,
  });
  res.json({ user: publicUser(updated) });
});

meRouter.post("/avatar", uploadAvatar.single("avatar"), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: "Файл не получен" });
  const user = req.user!;

  const previousUrl = user.avatarUrl;
  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { avatarUrl: `/uploads/avatars/${req.file.filename}` },
  });

  if (previousUrl) {
    const previousPath = path.join(AVATARS_DIR, path.basename(previousUrl));
    fs.unlink(previousPath).catch(() => {});
  }

  res.json({ user: publicUser(updated) });
});

meRouter.delete("/avatar", async (req, res) => {
  const user = req.user!;
  if (user.avatarUrl) {
    const previousPath = path.join(AVATARS_DIR, path.basename(user.avatarUrl));
    fs.unlink(previousPath).catch(() => {});
  }
  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { avatarUrl: null },
  });
  res.json({ user: publicUser(updated) });
});

meRouter.get("/progress", async (req, res) => {
  const summary = await getProgressSummaryForUser(req.user!.id);
  res.json({ progress: summary });
});

// ---- Lesson state (replaces the old browser-localStorage progress) ----

const STAGE_IDS = [
  "vocabulary",
  "material",
  "video",
  "minitest",
  "audio",
  "practice",
  "review",
  "complete",
] as const;

const quizResultSchema = z.object({
  correct: z.number().int().min(0),
  total: z.number().int().min(0),
  completedAt: z.string().optional(),
});

const lessonStateSchema = z.object({
  completedStages: z.array(z.enum(STAGE_IDS)).default([]),
  vocabIndex: z.number().int().min(0).default(0),
  miniTestResult: quizResultSchema.optional(),
  practiceResult: quizResultSchema.optional(),
  reviewResult: quizResultSchema.optional(),
  startedAt: z.string().optional(),
  completedAt: z.string().optional(),
});

meRouter.get("/lesson-state", async (req, res) => {
  const states = await prisma.lessonState.findMany({ where: { userId: req.user!.id } });
  res.json({ states: states.map(toDTO) });
});

meRouter.put("/lesson-state/:lessonId", async (req, res) => {
  const parsed = lessonStateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Некорректное состояние урока" });

  const body = parsed.data;
  const lessonId = req.params.lessonId;
  const asDate = (value?: string) => (value ? new Date(value) : null);

  const data = {
    completedStages: body.completedStages,
    vocabIndex: body.vocabIndex,
    miniTestCorrect: body.miniTestResult?.correct ?? null,
    miniTestTotal: body.miniTestResult?.total ?? null,
    miniTestAt: asDate(body.miniTestResult?.completedAt),
    practiceCorrect: body.practiceResult?.correct ?? null,
    practiceTotal: body.practiceResult?.total ?? null,
    practiceAt: asDate(body.practiceResult?.completedAt),
    reviewCorrect: body.reviewResult?.correct ?? null,
    reviewTotal: body.reviewResult?.total ?? null,
    reviewAt: asDate(body.reviewResult?.completedAt),
    completedAt: asDate(body.completedAt),
  };

  // Always scoped to the authenticated user's id from the JWT — a client
  // cannot write into someone else's lesson state.
  const state = await prisma.lessonState.upsert({
    where: { userId_lessonId: { userId: req.user!.id, lessonId } },
    update: data,
    create: {
      ...data,
      userId: req.user!.id,
      lessonId,
      startedAt: asDate(body.startedAt) ?? new Date(),
    },
  });

  res.json({ state: toDTO(state) });
});

const attemptSchema = z.object({
  miniTestCorrect: z.number().int().min(0),
  miniTestTotal: z.number().int().min(0),
  practiceCorrect: z.number().int().min(0),
  practiceTotal: z.number().int().min(0),
  reviewCorrect: z.number().int().min(0),
  reviewTotal: z.number().int().min(0),
});

meRouter.post("/progress/:lessonId/attempts", async (req, res) => {
  const parsed = attemptSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Некорректные данные попытки" });

  const lessonId = req.params.lessonId;
  const score = computeScore(parsed.data);

  await prisma.lessonAttempt.create({
    data: { ...parsed.data, lessonId, score, userId: req.user!.id },
  });

  const summary = await getProgressSummaryForUser(req.user!.id);
  res.status(201).json({ progress: summary.find((s) => s.lessonId === lessonId) ?? null });
});
