"use client";

import { useEffect, useState } from "react";
import { ApiClient, type BookSummary } from "../../lib/api";
import { loadOfflineQueueStats } from "../../lib/offline-sync";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

export default function ReaderAppPage() {
  const [books, setBooks] = useState<BookSummary[]>([]);
  const [queueSize, setQueueSize] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadOfflineQueueStats().then((stats) => setQueueSize(stats.pending));
    api
      .listMyBooks()
      .then(setBooks)
      .catch((reason) => setError(reason instanceof Error ? reason.message : "Failed to load books"));
  }, []);

  return (
    <main className="grid">
      <section className="hero">
        <h1>Reading App</h1>
        <p className="muted">
          This shell is ready to host the shared reader UI for Web and Capacitor.
        </p>
        <p className="muted">
          Offline sync queue size: <strong>{queueSize}</strong>
        </p>
      </section>

      <section className="card">
        <h2>Bookshelf</h2>
        {error ? <p>{error}</p> : null}
        <table className="table">
          <thead>
            <tr>
              <th>Title</th>
              <th>Format</th>
              <th>Plugin</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {books.length === 0 ? (
              <tr>
                <td colSpan={4}>No books available yet.</td>
              </tr>
            ) : (
              books.map((book) => (
                <tr key={book.id}>
                  <td>{book.title}</td>
                  <td>{book.format}</td>
                  <td>{book.pluginId}</td>
                  <td>{book.sourceMissing ? "Source missing" : "Ready"}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>
    </main>
  );
}

