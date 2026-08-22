import { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";

// Client-side UX guard only — redirects so users aren't shown a broken admin
// screen. The actual enforcement is server-side (requireAuth/requireAdmin in
// server/src/auth/middleware.ts): a USER token can never read/write admin
// endpoints no matter what URL is typed here.
export default function ProtectedRoute({ children, adminOnly = false }: { children: ReactNode; adminOnly?: boolean }) {
  const { user } = useAuth();
  const location = useLocation();

  if (!user) {
    return <Navigate to="/login" state={{ from: location.pathname }} replace />;
  }
  if (adminOnly && user.role !== "ADMIN") {
    return <Navigate to="/profile" replace />;
  }
  return <>{children}</>;
}
