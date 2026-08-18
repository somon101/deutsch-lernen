import { Router } from "express";
import { z } from "zod";
import { Prisma } from "@prisma/client";
import { prisma } from "../db.js";
import { requireAdmin, requireAuth } from "../auth/middleware.js";
import { hashPassword } from "../auth/hash.js";
import { publicUser } from "../serialize.js";
import { getProgressSummaryForUser } from "../progress.js";

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
  username: z.string().min(3),
  password: z.string().min(6),
  role: z.enum(["ADMIN", "USER"]).default("USER"),
  canEditProfile: z.boolean().default(true),
});

adminRouter.post("/users", async (req, res) => {
  const parsed = createUserSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Некорректные данные пользователя" });
  const { password, ...rest } = parsed.data;

  try {
    const user = await prisma.user.create({
      data: { ...rest, passwordHash: await hashPassword(password) },
    });
    res.status(201).json({ user: publicUser(user) });
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
      return res.status(409).json({ error: "Email или логин уже заняты" });
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
  username: z.string().min(3).optional(),
  role: z.enum(["ADMIN", "USER"]).optional(),
  status: z.enum(["ACTIVE", "BLOCKED"]).optional(),
  canEditProfile: z.boolean().optional(),
});

adminRouter.patch("/users/:id", async (req, res) => {
  const parsed = updateUserSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Некорректные данные пользователя" });

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
      data: parsed.data,
    });
    res.json({ user: publicUser(user) });
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2025") {
      return res.status(404).json({ error: "Пользователь не найден" });
    }
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") {
      return res.status(409).json({ error: "Email или логин уже заняты" });
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
