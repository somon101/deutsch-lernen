import { NextFunction, Request, Response } from "express";
import { prisma } from "../db.js";
import { verifyToken } from "./jwt.js";
import type { Role, User } from "@prisma/client";

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: User;
    }
  }
}

/**
 * Verifies the JWT and re-loads the user from the database on every request
 * (not just trusting the token's claims) so a role change or block takes
 * effect immediately, not only after the token expires.
 */
export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  const token = header?.startsWith("Bearer ") ? header.slice("Bearer ".length) : null;
  if (!token) return res.status(401).json({ error: "Не авторизован" });

  const payload = verifyToken(token);
  if (!payload) return res.status(401).json({ error: "Недействительный токен" });

  const user = await prisma.user.findUnique({ where: { id: payload.sub } });
  if (!user) return res.status(401).json({ error: "Пользователь не найден" });
  if (user.status !== "ACTIVE") return res.status(403).json({ error: "Учётная запись заблокирована" });

  req.user = user;
  next();
}

export function requireRole(role: Role) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ error: "Не авторизован" });
    if (req.user.role !== role) return res.status(403).json({ error: "Недостаточно прав" });
    next();
  };
}

export const requireAdmin = requireRole("ADMIN");
