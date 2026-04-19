"use client";

import { useEffect, useState } from "react";
import { AdminShell } from "../../../components/admin-shell";
import { ApiClient, type ImportJob, type LibrarySource } from "../../../lib/api";
import { useAuth } from "../../../lib/auth";
import { useI18n } from "../../../lib/i18n";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

function formatDate(value: string | null, fallback: string): string {
  if (!value) {
    return fallback;
  }
  return new Date(value).toLocaleString();
}

export default function AdminLibraryPage() {
  const { t } = useI18n();
  const { session } = useAuth();
  const [sources, setSources] = useState<LibrarySource[]>([]);
  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [sourceName, setSourceName] = useState("");
  const [sourcePath, setSourcePath] = useState("");
  const [sourceEnabled, setSourceEnabled] = useState(true);
  const [creatingSource, setCreatingSource] = useState(false);
  const [rescanSourceId, setRescanSourceId] = useState<number | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function refreshData() {
    if (!session) {
      return;
    }

    const [nextSources, nextJobs] = await Promise.all([
      api.listLibrarySources(),
      api.listImportJobs(),
    ]);
    setSources(nextSources);
    setJobs(nextJobs);
  }

  useEffect(() => {
    if (!session) {
      setSources([]);
      setJobs([]);
      return;
    }

    let cancelled = false;

    async function loadInitialData() {
      try {
        const [nextSources, nextJobs] = await Promise.all([
          api.listLibrarySources(),
          api.listImportJobs(),
        ]);
        if (!cancelled) {
          setSources(nextSources);
          setJobs(nextJobs);
        }
      } catch {
        if (!cancelled) {
          setSources([]);
          setJobs([]);
        }
      }
    }

    void loadInitialData();

    return () => {
      cancelled = true;
    };
  }, [session]);

  async function handleCreateSource(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCreatingSource(true);
    setError(null);
    setNotice(null);

    try {
      const source = await api.createLibrarySource({
        name: sourceName,
        rootPath: sourcePath,
        enabled: sourceEnabled,
      });
      setSourceName("");
      setSourcePath("");
      setSourceEnabled(true);
      await refreshData();
      setNotice(`${t("admin.sourceCreated")}: ${source.name}`);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("admin.createSourceFailed"));
    } finally {
      setCreatingSource(false);
    }
  }

  async function handleRescan(sourceId: number) {
    setRescanSourceId(sourceId);
    setError(null);
    setNotice(null);

    try {
      const result = await api.rescanLibrarySource(sourceId);
      await refreshData();
      setNotice(
        `${t("admin.rescanSuccess")}: ${t("admin.rescanImported")} ${result.imported}, ${t("admin.rescanMissing")} ${result.missingMarked}`,
      );
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("admin.rescanFailed"));
    } finally {
      setRescanSourceId(null);
    }
  }

  return (
    <AdminShell title={t("admin.nav.library.title")} subtitle={t("admin.libraryPageBody")}>
      {notice ? <p className="notice">{notice}</p> : null}
      {error ? <p className="notice error">{error}</p> : null}

      <section className="admin-dashboard-grid admin-two-column">
        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.sourcesTitle")}</h2>
              <p className="muted compact">{t("admin.sourcesBody")}</p>
            </div>
          </div>
          <form className="form-grid" onSubmit={handleCreateSource}>
            <label className="field">
              <span>{t("admin.sourceName")}</span>
              <input className="input" value={sourceName} onChange={(event) => setSourceName(event.target.value)} />
            </label>
            <label className="field">
              <span>{t("admin.sourceRootPath")}</span>
              <input
                className="input"
                placeholder="Z:\\ebooks"
                value={sourcePath}
                onChange={(event) => setSourcePath(event.target.value)}
              />
            </label>
            <label className="checkbox-row">
              <input
                type="checkbox"
                checked={sourceEnabled}
                onChange={(event) => setSourceEnabled(event.target.checked)}
              />
              <span>{t("admin.sourceEnabled")}</span>
            </label>
            <div className="toolbar">
              <button className="button" type="submit" disabled={creatingSource}>
                {creatingSource ? t("admin.creatingSource") : t("admin.createSource")}
              </button>
            </div>
          </form>
        </article>

        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.sourcesListTitle")}</h2>
              <p className="muted compact">{t("admin.sourcesListBody")}</p>
            </div>
          </div>
          {sources.length === 0 ? (
            <p className="muted">{t("admin.noSources")}</p>
          ) : (
            <div className="admin-list">
              {sources.map((source) => (
                <div key={source.id} className="admin-list-row">
                  <div>
                    <strong>{source.name}</strong>
                    <p className="muted compact">{source.rootPath}</p>
                  </div>
                  <div className="admin-job-meta">
                    <span className="reader-meta-pill">
                      {formatDate(source.lastScanAt, t("admin.neverScanned"))}
                    </span>
                    <button
                      className="button secondary"
                      type="button"
                      onClick={() => void handleRescan(source.id)}
                      disabled={rescanSourceId === source.id}
                    >
                      {rescanSourceId === source.id ? t("admin.rescanning") : t("admin.rescanAction")}
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </article>
      </section>

      <article className="card admin-panel">
        <div className="section-header">
          <div>
            <h2>{t("admin.importJobsTitle")}</h2>
            <p className="muted compact">{t("admin.importJobsBody")}</p>
          </div>
        </div>
        {jobs.length === 0 ? (
          <p className="muted">{t("admin.noImportJobs")}</p>
        ) : (
          <div className="admin-list">
            {jobs.slice(0, 12).map((job) => (
              <div key={job.id} className="admin-list-row">
                <div>
                  <strong>{`${t("admin.tableJobBookId")}: ${job.bookId}`}</strong>
                  <p className="muted compact">{job.message ?? t("common.notAvailable")}</p>
                </div>
                <div className="admin-job-meta">
                  <span className="reader-meta-pill">{job.status}</span>
                  <small className="muted">{formatDate(job.createdAt, t("common.notAvailable"))}</small>
                </div>
              </div>
            ))}
          </div>
        )}
      </article>
    </AdminShell>
  );
}
