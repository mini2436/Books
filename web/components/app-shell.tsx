"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useAuth } from "../lib/auth";
import { useI18n } from "../lib/i18n";
import { LanguageSwitcher } from "./language-switcher";

function resolveLoginNext(pathname: string | null): "/" | "/app" | "/admin" {
  if (pathname === "/" || pathname === "/app" || pathname === "/admin") {
    return pathname;
  }
  return "/app";
}

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { session, logout, status } = useAuth();
  const { t } = useI18n();
  const loginNext = resolveLoginNext(pathname);

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner">
          <div className="topbar-brand">Private Reader</div>
          <div className="topbar-actions">
            {status === "authenticated" && session ? (
              <>
                <div className="user-badge">
                  <strong>{session.user.username}</strong>
                  <span className="muted code">{session.user.role}</span>
                </div>
                <button
                  type="button"
                  className="button secondary"
                  onClick={() => {
                    void logout();
                  }}
                >
                  {t("auth.signOut")}
                </button>
              </>
            ) : pathname === "/login" ? null : (
              <Link
                className="button secondary"
                href={{ pathname: "/login", query: { next: loginNext } }}
              >
                {t("auth.signIn")}
              </Link>
            )}
            <LanguageSwitcher />
          </div>
        </div>
      </header>
      {children}
    </>
  );
}
