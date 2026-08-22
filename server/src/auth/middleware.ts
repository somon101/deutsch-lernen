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

// How "online" is decided: lastActiveAt is refreshed on every authenticated
// request (below), throttled to at most once per this many ms so a user
// actively browsing the app doesn't cause a DB write on every single call.
// The admin UI's "в сети" indicator considers a user online within roughly
// this same window of their last request.
export const ACTIVITY_UPDATE_THROTTLE_MS = 2 * 60 * 1000; // 2 minutes

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

  // Fire-and-forget: this is "was the user just using the app", not
  // security-critical, so it must never slow down or fail the actual
  // request. Throttled — see ACTIVITY_UPDATE_THROTTLE_MS above.
  const msSinceActive = user.lastActiveAt ? Date.now() - user.lastActiveAt.getTime() : Infinity;
  if (msSinceActive > ACTIVITY_UPDATE_THROTTLE_MS) {
    prisma.user.update({ where: { id: user.id }, data: { lastActiveAt: new Date() } }).catch(() => {});
  }

  next();
}

export function requireRole(...roles: Role[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ error: "Не авторизован" });
    if (!roles.includes(req.user.role)) return res.status(403).json({ error: "Недостаточно прав" });
    next();
  };
}

export const requireAdmin = requireRole("ADMIN");
/** Course/lesson content editing — everything an ADMIN can do there, a
 * TEACHER can too (see server/src/routes/builder.routes.ts and the
 * /content/* routes in admin.routes.ts). User management and system
 * settings stay requireAdmin-only. */
export const requireStaff = requireRole("ADMIN", "TEACHER");
