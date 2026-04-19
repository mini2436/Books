"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { useAuth } from "../lib/auth";
import { useI18n } from "../lib/i18n";
import { LanguageSwitcher } from "./language-switcher";

function resolveLoginNext(pathname: string | null, search: string): string {
  if (!pathname || pathname === "/login") {
    return "/app";
  }
  const nextPath = `${pathname}${search}`;
  if (pathname.startsWith("/app")) {
    return nextPath;
  }
  if (pathname.startsWith("/admin")) {
    return nextPath;
  }
  return pathname === "/" ? "/" : "/app";
}

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { session, logout, status } = useAuth();
  const { t } = useI18n();
  const [search, setSearch] = useState("");
  useEffect(() => {
    setSearch(window.location.search);
  }, [pathname]);
  const loginNext = resolveLoginNext(pathname, search);
  const showAdminLink = session?.user.role === "SUPER_ADMIN" || session?.user.role === "LIBRARIAN";

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner">
          <div className="topbar-brand-row">
            <div className="topbar-brand-lockup">
              <div className="topbar-brand-mark">PR</div>
              <div className="topbar-brand">Private Reader</div>
            </div>
            <nav className="topbar-nav">
              <Link className={`topbar-link${pathname === "/" ? " active" : ""}`} href="/">
                {t("shell.home")}
              </Link>
              <Link className={`topbar-link${pathname?.startsWith("/app") ? " active" : ""}`} href="/app">
                {t("shell.reader")}
              </Link>
              {showAdminLink ? (
                <Link className={`topbar-link${pathname?.startsWith("/admin") ? " active" : ""}`} href="/admin">
                  {t("shell.admin")}
                </Link>
              ) : null}
            </nav>
          </div>
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
