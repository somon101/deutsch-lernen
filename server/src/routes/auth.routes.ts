import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db.js";
import { verifyPassword } from "../auth/hash.js";
import { signToken } from "../auth/jwt.js";
import { publicUser } from "../serialize.js";
import { requireAuth } from "../auth/middleware.js";
import { normalizeUsername } from "../username.js";

export const authRouter = Router();

const loginSchema = z.object({
  login: z.string().min(1), // username OR email
  password: z.string().min(1),
});

authRouter.post("/login", async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Укажите логин и пароль" });
  const { login, password } = parsed.data;

  // Login is accepted in any casing: "Ivan", "ivan" and "IVAN" all resolve
  // to the same account via the normalized column.
  const user = await prisma.user.findFirst({
    where: { OR: [{ usernameLower: normalizeUsername(login) }, { email: login }] },
  });
  if (!user) return res.status(401).json({ error: "Неверный логин или пароль" });
  if (user.status !== "ACTIVE") return res.status(403).json({ error: "Учётная запись заблокирована" });

  const ok = await verifyPassword(password, user.passwordHash);
  if (!ok) return res.status(401).json({ error: "Неверный логин или пароль" });

  const now = new Date();
  const [updated] = await prisma.$transaction([
    prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: now } }),
    prisma.loginEvent.create({ data: { userId: user.id, createdAt: now } }),
  ]);

  const token = signToken(user.id);
  res.json({ token, user: publicUser(updated) });
});

authRouter.get("/me", requireAuth, async (req, res) => {
  res.json({ user: publicUser(req.user!) });
});
