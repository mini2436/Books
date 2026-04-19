"use client";

import { useEffect, useState } from "react";
import { AdminShell } from "../../../components/admin-shell";
import { ApiClient, type AdminBookSummary, type ImportJob } from "../../../lib/api";
import { useAuth } from "../../../lib/auth";
import { useI18n } from "../../../lib/i18n";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

function formatDate(value: string): string {
  return new Date(value).toLocaleString();
}

export default function AdminCatalogPage() {
  const { t } = useI18n();
  const { session } = useAuth();
  const [books, setBooks] = useState<AdminBookSummary[]>([]);
  const [jobs, setJobs] = useState<ImportJob[]>([]);

  useEffect(() => {
    if (!session) {
      setBooks([]);
      setJobs([]);
      return;
    }

    let cancelled = false;

    async function loadData() {
      try {
        const [nextBooks, nextJobs] = await Promise.all([
          api.listAdminBooks(),
          api.listImportJobs(),
        ]);
        if (!cancelled) {
          setBooks(nextBooks);
          setJobs(nextJobs);
        }
      } catch {
        if (!cancelled) {
          setBooks([]);
          setJobs([]);
        }
      }
    }

    void loadData();
    return () => {
      cancelled = true;
    };
  }, [session]);

  return (
    <AdminShell title={t("admin.nav.catalog.title")} subtitle={t("admin.catalogPageBody")}>
      <section className="admin-dashboard-grid admin-two-column">
        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.booksTitle")}</h2>
              <p className="muted compact">{t("admin.booksBody")}</p>
            </div>
          </div>
          <div className="admin-table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>{t("admin.tableBookTitle")}</th>
                  <th>{t("admin.tableBookAuthor")}</th>
                  <th>{t("admin.tableBookFormat")}</th>
                  <th>{t("admin.tableBookSourceType")}</th>
                  <th>{t("admin.tableBookUpdatedAt")}</th>
                </tr>
              </thead>
              <tbody>
                {books.map((book) => (
                  <tr key={book.id}>
                    <td>{book.id}</td>
                    <td>{book.title}</td>
                    <td>{book.author ?? t("common.notAvailable")}</td>
                    <td>{`${book.format} / ${book.pluginId}`}</td>
                    <td>{book.sourceType}</td>
                    <td>{formatDate(book.updatedAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </article>

        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.importJobsTitle")}</h2>
              <p className="muted compact">{t("admin.importJobsBody")}</p>
            </div>
          </div>
          <div className="admin-table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>{t("admin.tableJobBookId")}</th>
                  <th>{t("admin.tableJobSourceId")}</th>
                  <th>{t("admin.tableJobStatus")}</th>
                  <th>{t("admin.tableJobMessage")}</th>
                  <th>{t("admin.tableJobCreatedAt")}</th>
                </tr>
              </thead>
              <tbody>
                {jobs.map((job) => (
                  <tr key={job.id}>
                    <td>{job.id}</td>
                    <td>{job.bookId}</td>
                    <td>{job.sourceId ?? t("common.notAvailable")}</td>
                    <td>{job.status}</td>
                    <td>{job.message ?? t("common.notAvailable")}</td>
                    <td>{formatDate(job.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </article>
      </section>
    </AdminShell>
  );
}
