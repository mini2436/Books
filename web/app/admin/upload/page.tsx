"use client";

import { useEffect, useState } from "react";
import { AdminShell } from "../../../components/admin-shell";
import { ApiClient, type BookDetail, type ImportJob } from "../../../lib/api";
import { useAuth } from "../../../lib/auth";
import { useI18n } from "../../../lib/i18n";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

function formatDate(value: string): string {
  return new Date(value).toLocaleString();
}

export default function AdminUploadPage() {
  const { t } = useI18n();
  const { session } = useAuth();
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadedBook, setUploadedBook] = useState<BookDetail | null>(null);
  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [uploadInputKey, setUploadInputKey] = useState(0);

  useEffect(() => {
    if (!session) {
      setJobs([]);
      return;
    }

    let cancelled = false;
    async function loadJobs() {
      try {
        const nextJobs = await api.listImportJobs();
        if (!cancelled) {
          setJobs(nextJobs);
        }
      } catch {
        if (!cancelled) {
          setJobs([]);
        }
      }
    }

    void loadJobs();
    return () => {
      cancelled = true;
    };
  }, [session]);

  async function handleUpload(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!uploadFile) {
      setError(t("admin.selectFileFirst"));
      return;
    }

    setUploading(true);
    setError(null);
    setNotice(null);

    try {
      const detail = await api.uploadBook(uploadFile);
      const nextJobs = await api.listImportJobs();
      setUploadedBook(detail);
      setJobs(nextJobs);
      setUploadFile(null);
      setUploadInputKey((value) => value + 1);
      setNotice(`${t("admin.uploadSuccess")}: ${detail.title}`);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("admin.uploadFailed"));
    } finally {
      setUploading(false);
    }
  }

  return (
    <AdminShell title={t("admin.uploadTitle")} subtitle={t("admin.uploadPageBody")}>
      {notice ? <p className="notice">{notice}</p> : null}
      {error ? <p className="notice error">{error}</p> : null}

      <section className="admin-dashboard-grid admin-two-column">
        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.uploadTitle")}</h2>
              <p className="muted compact">{t("admin.uploadBody")}</p>
            </div>
          </div>
          <form className="form-grid" onSubmit={handleUpload}>
            <label className="field">
              <span>{t("admin.uploadField")}</span>
              <input
                key={uploadInputKey}
                className="input"
                type="file"
                accept=".epub,.pdf,.txt"
                onChange={(event) => setUploadFile(event.target.files?.[0] ?? null)}
              />
            </label>
            <div className="toolbar">
              <button className="button" type="submit" disabled={uploading}>
                {uploading ? t("admin.uploading") : t("admin.uploadAction")}
              </button>
            </div>
          </form>

          {uploadedBook ? (
            <div className="result-panel">
              <h3>{t("admin.lastUploaded")}</h3>
              <div className="reader-meta-grid">
                <div className="reader-meta-pill">{`${t("admin.uploadedFormat")}: ${uploadedBook.format}`}</div>
                <div className="reader-meta-pill">{`${t("admin.uploadedPlugin")}: ${uploadedBook.pluginId}`}</div>
                <div className="reader-meta-pill">{`${t("admin.uploadedSource")}: ${uploadedBook.sourceType}`}</div>
              </div>
              <p className="muted">{uploadedBook.description ?? t("common.notAvailable")}</p>
            </div>
          ) : null}
        </article>

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
              {jobs.slice(0, 8).map((job) => (
                <div key={job.id} className="admin-list-row">
                  <div>
                    <strong>{`${t("admin.tableJobBookId")}: ${job.bookId}`}</strong>
                    <p className="muted compact">{job.message ?? t("common.notAvailable")}</p>
                  </div>
                  <div className="admin-job-meta">
                    <span className="reader-meta-pill">{job.status}</span>
                    <small className="muted">{formatDate(job.createdAt)}</small>
                  </div>
                </div>
              ))}
            </div>
          )}
        </article>
      </section>
    </AdminShell>
  );
}
