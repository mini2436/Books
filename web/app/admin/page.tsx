"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { AdminShell } from "../../components/admin-shell";
import { ApiClient, type AdminBookSummary, type ImportJob, type LibrarySource, type PluginSummary, type UserSummary } from "../../lib/api";
import { useAuth } from "../../lib/auth";
import { useI18n } from "../../lib/i18n";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

function formatDate(value: string | null, fallback: string): string {
  if (!value) {
    return fallback;
  }
  return new Date(value).toLocaleString();
}

export default function AdminOverviewPage() {
  const { t } = useI18n();
  const { session } = useAuth();
  const [plugins, setPlugins] = useState<PluginSummary[]>([]);
  const [books, setBooks] = useState<AdminBookSummary[]>([]);
  const [sources, setSources] = useState<LibrarySource[]>([]);
  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [users, setUsers] = useState<UserSummary[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!session) {
      setPlugins([]);
      setBooks([]);
      setSources([]);
      setJobs([]);
      setUsers([]);
      return;
    }

    let cancelled = false;
    const currentRole = session.user.role;

    async function loadData() {
      setLoading(true);
      setError(null);
      try {
        const [nextPlugins, nextBooks, nextSources, nextJobs, nextUsers] = await Promise.all([
          api.listPlugins(),
          api.listAdminBooks(),
          api.listLibrarySources(),
          api.listImportJobs(),
          currentRole === "SUPER_ADMIN" ? api.listUsers() : Promise.resolve([]),
        ]);
        if (cancelled) {
          return;
        }
        setPlugins(nextPlugins);
        setBooks(nextBooks);
        setSources(nextSources);
        setJobs(nextJobs);
        setUsers(nextUsers.filter((user) => user.enabled));
      } catch (reason) {
        if (!cancelled) {
          setError(reason instanceof Error ? reason.message : t("admin.loadPluginsFailed"));
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void loadData();

    return () => {
      cancelled = true;
    };
  }, [session, t]);

  return (
    <AdminShell
      title={t("admin.title")}
      subtitle={t("admin.subtitle")}
      toolbar={
        <button className="button secondary" type="button" onClick={() => window.location.reload()} disabled={loading}>
          {loading ? t("admin.refreshing") : t("admin.refreshData")}
        </button>
      }
      summary={
        <>
          <article className="admin-summary-card">
            <span>{t("admin.summaryPlugins")}</span>
            <strong>{plugins.length}</strong>
          </article>
          <article className="admin-summary-card">
            <span>{t("admin.summarySources")}</span>
            <strong>{sources.length}</strong>
          </article>
          <article className="admin-summary-card">
            <span>{t("admin.summaryJobs")}</span>
            <strong>{jobs.length}</strong>
          </article>
          <article className="admin-summary-card">
            <span>{t("admin.summaryUsers")}</span>
            <strong>{users.length}</strong>
          </article>
        </>
      }
    >
      {error ? <p className="notice error">{error}</p> : null}

      <section className="admin-dashboard-grid">
        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.nav.upload.title")}</h2>
              <p className="muted compact">{t("admin.nav.upload.body")}</p>
            </div>
            <Link className="button secondary" href="/admin/upload">
              {t("admin.openSection")}
            </Link>
          </div>
          <p className="muted">{t("admin.uploadBody")}</p>
          <div className="admin-chip-row">
            <span className="reader-meta-pill">EPUB</span>
            <span className="reader-meta-pill">PDF</span>
            <span className="reader-meta-pill">TXT</span>
          </div>
        </article>

        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.nav.library.title")}</h2>
              <p className="muted compact">{t("admin.nav.library.body")}</p>
            </div>
            <Link className="button secondary" href="/admin/library">
              {t("admin.openSection")}
            </Link>
          </div>
          {sources.length === 0 ? (
            <p className="muted">{t("admin.noSources")}</p>
          ) : (
            <div className="admin-list">
              {sources.slice(0, 3).map((source) => (
                <div key={source.id} className="admin-list-row">
                  <div>
                    <strong>{source.name}</strong>
                    <p className="muted compact">{source.rootPath}</p>
                  </div>
                  <span className="reader-meta-pill">
                    {formatDate(source.lastScanAt, t("admin.neverScanned"))}
                  </span>
                </div>
              ))}
            </div>
          )}
        </article>

        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.nav.access.title")}</h2>
              <p className="muted compact">{t("admin.nav.access.body")}</p>
            </div>
            <Link className="button secondary" href="/admin/access">
              {t("admin.openSection")}
            </Link>
          </div>
          <div className="admin-list">
            {books.slice(0, 3).map((book) => (
              <div key={book.id} className="admin-list-row">
                <div>
                  <strong>{book.title}</strong>
                  <p className="muted compact">{book.author ?? t("common.notAvailable")}</p>
                </div>
                <span className="code">{book.format}</span>
              </div>
            ))}
          </div>
        </article>

        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.importJobsTitle")}</h2>
              <p className="muted compact">{t("admin.importJobsBody")}</p>
            </div>
            <Link className="button secondary" href="/admin/catalog">
              {t("admin.openSection")}
            </Link>
          </div>
          {jobs.length === 0 ? (
            <p className="muted">{t("admin.noImportJobs")}</p>
          ) : (
            <div className="admin-list">
              {jobs.slice(0, 4).map((job) => (
                <div key={job.id} className="admin-list-row">
                  <div>
                    <strong>{`${t("admin.tableJobBookId")}: ${job.bookId}`}</strong>
                    <p className="muted compact">{job.message ?? t("common.notAvailable")}</p>
                  </div>
                  <span className="reader-meta-pill">{job.status}</span>
                </div>
              ))}
            </div>
          )}
        </article>
      </section>
    </AdminShell>
  );
}
