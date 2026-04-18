"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  getStoredSession,
  setStoredSession,
  type AuthSession,
  type AuthUser,
} from "./auth-storage";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080";

type LoginInput = {
  username: string;
  password: string;
};

type AuthContextValue = {
  session: AuthSession | null;
  status: "loading" | "authenticated" | "anonymous";
  login: (input: LoginInput) => Promise<void>;
  logout: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

async function readErrorMessage(response: Response): Promise<string> {
  const contentType = response.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    const payload = (await response.json()) as { error?: string; message?: string };
    return payload.error ?? payload.message ?? `Request failed: ${response.status}`;
  }

  const text = (await response.text()).trim();
  return text || `Request failed: ${response.status}`;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<AuthSession | null>(null);
  const [status, setStatus] = useState<AuthContextValue["status"]>("loading");

  useEffect(() => {
    const stored = getStoredSession();
    setSession(stored);
    setStatus(stored ? "authenticated" : "anonymous");
  }, []);

  useEffect(() => {
    const handleStorage = () => {
      const stored = getStoredSession();
      setSession(stored);
      setStatus(stored ? "authenticated" : "anonymous");
    };

    window.addEventListener("storage", handleStorage);
    return () => window.removeEventListener("storage", handleStorage);
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      session,
      status,
      async login(input: LoginInput) {
        const response = await fetch(`${API_BASE_URL}/api/auth/login`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(input),
        });

        if (!response.ok) {
          throw new Error(await readErrorMessage(response));
        }

        const nextSession = (await response.json()) as AuthSession;
        setStoredSession(nextSession);
        setSession(nextSession);
        setStatus("authenticated");
      },
      async logout() {
        const currentSession = getStoredSession();

        if (currentSession) {
          try {
            await fetch(`${API_BASE_URL}/api/auth/logout`, {
              method: "POST",
              headers: {
                Authorization: `Bearer ${currentSession.accessToken}`,
              },
            });
          } catch {
            // Clearing local state is more important than surfacing logout failures.
          }
        }

        setStoredSession(null);
        setSession(null);
        setStatus("anonymous");
      },
    }),
    [session, status],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used inside AuthProvider");
  }
  return context;
}
