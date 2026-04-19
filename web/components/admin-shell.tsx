"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useAuth } from "../lib/auth";
import { useI18n } from "../lib/i18n";

export function canAccessAdmin(role: string | undefined): boolean {
  return role === "SUPER_ADMIN" || role === "LIBRARIAN";
}

type AdminShellProps = {
  title: string;
  subtitle: string;
  summary?: ReactNode;
  toolbar?: ReactNode;
  children: ReactNode;
};

const sections = [
  { href: "/admin", key: "overview" },
  { href: "/admin/upload", key: "upload" },
  { href: "/admin/library", key: "library" },
  { href: "/admin/access", key: "access" },
  { href: "/admin/catalog", key: "catalog" },
  { href: "/admin/plugins", key: "plugins" },
] as const;

export function AdminShell({ title, subtitle, summary, toolbar, children }: AdminShellProps) {
  const pathname = usePathname();
  const { session, status } = useAuth();
  const { t } = useI18n();

  if (status === "loading") {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{title}</h1>
          <p className="muted">{t("common.loading")}</p>
        </section>
      </main>
    );
  }

  if (!session) {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{title}</h1>
          <p className="muted">{subtitle}</p>
        </section>
        <section className="card auth-card">
          <h2>{t("auth.loginRequired")}</h2>
          <p className="muted">{t("auth.adminLoginHint")}</p>
          <div className="toolbar">
            <Link className="button" href={{ pathname: "/login", query: { next: pathname ?? "/admin" } }}>
              {t("auth.openLogin")}
            </Link>
          </div>
        </section>
      </main>
    );
  }

  if (!canAccessAdmin(session.user.role)) {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{title}</h1>
          <p className="muted">{subtitle}</p>
        </section>
        <section className="card auth-card">
          <h2>{t("auth.roleRestrictedTitle")}</h2>
          <p className="muted">{t("auth.roleRestrictedBody")}</p>
        </section>
      </main>
    );
  }

  return (
    <main className="admin-shell-page">
      <section className="hero admin-hero">
        <div>
          <div className="eyebrow">{t("admin.eyebrow")}</div>
          <h1>{title}</h1>
          <p className="muted">{subtitle}</p>
        </div>
        {toolbar ? <div className="toolbar admin-toolbar">{toolbar}</div> : null}
        {summary ? <div className="admin-summary-grid">{summary}</div> : null}
      </section>

      <section className="admin-frame">
        <aside className="card admin-sidebar">
          <div className="admin-sidebar-head">
            <strong>{t("admin.navigationTitle")}</strong>
            <span className="muted compact">{session.user.username}</span>
          </div>
          <nav className="admin-nav">
            {sections.map((section) => {
              const active = pathname === section.href;
              return (
                <Link
                  key={section.href}
                  className={`admin-nav-link${active ? " active" : ""}`}
                  href={section.href}
                >
                  <span>{t(`admin.nav.${section.key}.title`)}</span>
                  <small>{t(`admin.nav.${section.key}.body`)}</small>
                </Link>
              );
            })}
          </nav>
        </aside>

        <section className="admin-content">{children}</section>
      </section>
    </main>
  );
}
