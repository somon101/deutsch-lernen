import { prisma } from "./db.js";
import { hashPassword } from "./auth/hash.js";
import { normalizeUsername } from "./username.js";

/**
 * Makes sure the first admin account exists on startup, so a fresh
 * deployment is usable without shell access to run a seed script.
 * Idempotent: an existing account is left untouched (password included).
 */
export async function ensureAdminExists(): Promise<void> {
  const email = process.env.ADMIN_EMAIL;
  const username = process.env.ADMIN_USERNAME;
  const password = process.env.ADMIN_PASSWORD;

  if (!email || !username || !password) return;

  const existing = await prisma.user.findFirst({
    where: { OR: [{ email }, { usernameLower: normalizeUsername(username) }] },
  });
  if (existing) return;

  await prisma.user.create({
    data: {
      firstName: process.env.ADMIN_FIRST_NAME || "Admin",
      lastName: process.env.ADMIN_LAST_NAME || "Admin",
      email,
      username,
      usernameLower: normalizeUsername(username),
      passwordHash: await hashPassword(password),
      role: "ADMIN",
      status: "ACTIVE",
      canEditProfile: true,
    },
  });
  console.log(`Created initial admin account: ${username}`);
}
