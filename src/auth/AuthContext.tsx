import React, { createContext, useCallback, useContext, useState } from "react";
import { api, ApiError } from "./api";
import { clearAuth, loadAuth, saveAuth, StoredAuthUser } from "./tokenStore";

interface AuthContextValue {
  user: StoredAuthUser | null;
  isLoading: boolean;
  login: (login: string, password: string) => Promise<void>;
  logout: () => void;
  refreshUser: () => Promise<void>;
  updateLocalUser: (user: StoredAuthUser) => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<StoredAuthUser | null>(() => loadAuth()?.user ?? null);
  const [isLoading, setIsLoading] = useState(false);

  const login = useCallback(async (loginValue: string, password: string) => {
    setIsLoading(true);
    try {
      const data = await api.post<{ token: string; user: StoredAuthUser }>("/api/auth/login", {
        login: loginValue,
        password,
      });
      saveAuth(data);
      setUser(data.user);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const logout = useCallback(() => {
    clearAuth();
    setUser(null);
  }, []);

  const refreshUser = useCallback(async () => {
    try {
      const data = await api.get<{ user: StoredAuthUser }>("/api/me");
      const token = loadAuth()?.token;
      if (token) saveAuth({ token, user: data.user });
      setUser(data.user);
    } catch (e) {
      if (e instanceof ApiError && (e.status === 401 || e.status === 403)) {
        clearAuth();
        setUser(null);
      }
    }
  }, []);

  const updateLocalUser = useCallback((nextUser: StoredAuthUser) => {
    const token = loadAuth()?.token;
    if (token) saveAuth({ token, user: nextUser });
    setUser(nextUser);
  }, []);

  return (
    <AuthContext.Provider value={{ user, isLoading, login, logout, refreshUser, updateLocalUser }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
