import { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";

// Client-side UX guard only — redirects so users aren't shown a broken admin
// screen. The actual enforcement is server-side (requireAuth/requireAdmin/
// requireStaff in server/src/auth/middleware.ts): a USER or TEACHER token
// can never read/write an ADMIN-only endpoint no matter what URL is typed
// here, and a plain USER token can never reach a staffOnly one either.
export default function ProtectedRoute({
  children,
  adminOnly = false,
  staffOnly = false,
}: {
  children: ReactNode;
  /** ADMIN only — user management, system settings. */
  adminOnly?: boolean;
  /** ADMIN or TEACHER — course/lesson content editing. */
  staffOnly?: boolean;
}) {
  const { user } = useAuth();
  const location = useLocation();

  if (!user) {
    return <Navigate to="/login" state={{ from: location.pathname }} replace />;
  }
  if (adminOnly && user.role !== "ADMIN") {
    return <Navigate to="/403" replace />;
  }
  if (staffOnly && user.role !== "ADMIN" && user.role !== "TEACHER") {
    return <Navigate to="/403" replace />;
  }
  return <>{children}</>;
}
