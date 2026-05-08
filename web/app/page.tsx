"use client";

import Link from "next/link";
import { useI18n } from "../lib/i18n";

export default function HomePage() {
  const { t } = useI18n();

  return (
    <main className="home-page">
      <section className="home-hero">
        <div className="home-hero-copy">
          <div className="home-pill-row">
            <div className="pill">{t("home.pillNative")}</div>
            <div className="pill">{t("home.pillSync")}</div>
            <div className="pill">{t("home.pillPlugin")}</div>
          </div>
          <div className="eyebrow">轻阅</div>
          <h1>{t("home.title")}</h1>
          <p className="muted home-hero-description">{t("home.description")}</p>
          <div className="toolbar home-toolbar">
            <Link className="button" href="/app">
              {t("home.openReader")}
            </Link>
            <Link className="button secondary" href="/admin">
              {t("home.openAdmin")}
            </Link>
          </div>
        </div>

        <div className="home-hero-stage">
          <article className="home-stage-panel home-stage-panel-primary">
            <span className="home-stage-label">{t("home.readerExperienceTitle")}</span>
            <strong>{t("home.openReader")}</strong>
            <p>{t("home.readerExperienceBody")}</p>
          </article>

          <div className="home-stage-stack">
            <article className="home-stage-panel">
              <span className="home-stage-label">{t("home.adminToolsTitle")}</span>
              <p>{t("home.adminToolsBody")}</p>
            </article>
            <article className="home-stage-panel">
              <span className="home-stage-label">{t("home.pluginsTitle")}</span>
              <p>{t("home.pluginsBody")}</p>
            </article>
          </div>
        </div>
      </section>

      <section className="home-detail-grid">
        <article className="home-detail">
          <div className="eyebrow">{t("home.pillNative")}</div>
          <h2>{t("home.readerExperienceTitle")}</h2>
          <p className="muted">{t("home.readerExperienceBody")}</p>
        </article>

        <article className="home-detail">
          <div className="eyebrow">{t("home.pillSync")}</div>
          <h2>{t("home.adminToolsTitle")}</h2>
          <p className="muted">{t("home.adminToolsBody")}</p>
        </article>

        <article className="home-detail">
          <div className="eyebrow">{t("home.pillPlugin")}</div>
          <h2>{t("home.pluginsTitle")}</h2>
          <p className="muted">{t("home.pluginsBody")}</p>
        </article>
      </section>
    </main>
  );
}
