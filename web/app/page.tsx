"use client";

import Link from "next/link";
import { useI18n } from "../lib/i18n";

export default function HomePage() {
  const { t } = useI18n();

  return (
    <main className="grid">
      <section className="hero">
        <div className="pill">{t("home.pillNative")}</div>
        <div className="pill">{t("home.pillSync")}</div>
        <div className="pill">{t("home.pillPlugin")}</div>
        <h1>{t("home.title")}</h1>
        <p className="muted">{t("home.description")}</p>
        <div className="toolbar">
          <Link className="button" href="/app">
            {t("home.openReader")}
          </Link>
          <Link className="button secondary" href="/admin">
            {t("home.openAdmin")}
          </Link>
        </div>
      </section>

      <section className="cards">
        <article className="card">
          <h2>{t("home.readerExperienceTitle")}</h2>
          <p className="muted">{t("home.readerExperienceBody")}</p>
        </article>
        <article className="card">
          <h2>{t("home.adminToolsTitle")}</h2>
          <p className="muted">{t("home.adminToolsBody")}</p>
        </article>
        <article className="card">
          <h2>{t("home.pluginsTitle")}</h2>
          <p className="muted">{t("home.pluginsBody")}</p>
        </article>
      </section>
    </main>
  );
}
