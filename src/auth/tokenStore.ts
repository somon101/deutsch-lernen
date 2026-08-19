// Plain localStorage-backed accessor (no React context) so modules like
// ProgressContext can read the current auth token without depending on
// AuthProvider's position in the component tree.

export interface StoredAuthUser {
  id: string;
  firstName: string;
  lastName: string;
  email: string;
  phone: string | null;
  username: string;
  role: "ADMIN" | "USER";
  status: "ACTIVE" | "BLOCKED";
  avatarUrl: string | null;
  canEditProfile: boolean;
  lastLoginAt: string | null;
  /** Refreshed on every authenticated request the user makes, not just
   * login — see server/src/auth/middleware.ts. Admin pages derive an
   * "online now" badge from how recent this is. */
  lastActiveAt: string | null;
}

/** Admin-only view of a user, with the online/offline badge the server
 * derives from `lastActiveAt` (see withOnlineStatus in admin.routes.ts). */
export interface AdminUserSummary extends StoredAuthUser {
  online: boolean;
}

interface StoredAuth {
  token: string;
  user: StoredAuthUser;
}

const KEY = "deutsch-lernen:auth:v1";

export function loadAuth(): StoredAuth | null {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as StoredAuth) : null;
  } catch {
    return null;
  }
}

export function saveAuth(auth: StoredAuth): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(auth));
  } catch {
    // ignore (private mode / quota)
  }
}

export function clearAuth(): void {
  try {
    localStorage.removeItem(KEY);
  } catch {
    // ignore
  }
}

export function getAuthToken(): string | null {
  return loadAuth()?.token ?? null;
}
