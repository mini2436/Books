"use client";

const STORAGE_KEY = "private-reader-session";

export type AuthUser = {
  id: number;
  username: string;
  role: string;
};

export type AuthSession = {
  accessToken: string;
  refreshToken: string;
  user: AuthUser;
};

function isAuthSession(value: unknown): value is AuthSession {
  if (!value || typeof value !== "object") {
    return false;
  }

  const session = value as Partial<AuthSession>;
  const user = session.user as Partial<AuthUser> | undefined;

  return (
    typeof session.accessToken === "string" &&
    typeof session.refreshToken === "string" &&
    !!user &&
    typeof user.id === "number" &&
    typeof user.username === "string" &&
    typeof user.role === "string"
  );
}

export function getStoredSession(): AuthSession | null {
  if (typeof window === "undefined") {
    return null;
  }

  const raw = window.localStorage.getItem(STORAGE_KEY);
  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw) as unknown;
    if (isAuthSession(parsed)) {
      return parsed;
    }
  } catch {
    // Ignore malformed local storage and clear it below.
  }

  window.localStorage.removeItem(STORAGE_KEY);
  return null;
}

export function setStoredSession(session: AuthSession | null) {
  if (typeof window === "undefined") {
    return;
  }

  if (session) {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
    return;
  }

  window.localStorage.removeItem(STORAGE_KEY);
}
