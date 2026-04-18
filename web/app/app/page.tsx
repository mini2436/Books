"use client";

import { useEffect, useState } from "react";
import { ApiClient, type BookSummary } from "../../lib/api";
import { useI18n } from "../../lib/i18n";
import { loadOfflineQueueStats } from "../../lib/offline-sync";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

export default function ReaderAppPage() {
  const { t } = useI18n();
  const [books, setBooks] = useState<BookSummary[]>([]);
  const [queueSize, setQueueSize] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadOfflineQueueStats().then((stats) => setQueueSize(stats.pending));
    api
      .listMyBooks()
      .then(setBooks)
      .catch((reason) => setError(reason instanceof Error ? reason.message : t("reader.loadBooksFailed")));
  }, [t]);

  return (
    <main className="grid">
      <section className="hero">
        <h1>{t("reader.title")}</h1>
        <p className="muted">{t("reader.subtitle")}</p>
        <p className="muted">
          {t("reader.queueSize")}: <strong>{queueSize}</strong>
        </p>
      </section>

      <section className="card">
        <h2>{t("reader.bookshelf")}</h2>
        {error ? <p>{error}</p> : null}
        <table className="table">
          <thead>
            <tr>
              <th>{t("reader.tableTitle")}</th>
              <th>{t("reader.tableFormat")}</th>
              <th>{t("reader.tablePlugin")}</th>
              <th>{t("reader.tableStatus")}</th>
            </tr>
          </thead>
          <tbody>
            {books.length === 0 ? (
              <tr>
                <td colSpan={4}>{t("reader.noBooks")}</td>
              </tr>
            ) : (
              books.map((book) => (
                <tr key={book.id}>
                  <td>{book.title}</td>
                  <td>{book.format}</td>
                  <td>{book.pluginId}</td>
                  <td>{book.sourceMissing ? t("reader.statusMissing") : t("reader.statusReady")}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>
    </main>
  );
}
