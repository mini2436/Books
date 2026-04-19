"use client";

import Link from "next/link";
import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { ApiClient, type BookSummary } from "../../lib/api";
import { useAuth } from "../../lib/auth";
import { useI18n } from "../../lib/i18n";
import { loadOfflineQueueStats } from "../../lib/offline-sync";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

const shelfPalette = [
  ["#6b4328", "#8d5a36"],
  ["#385b6b", "#4d7b8e"],
  ["#5c3131", "#8a4747"],
  ["#495b2f", "#67813f"],
  ["#5a3d6e", "#7f5f9b"],
  ["#8b5d20", "#b98631"],
  ["#c7c2ba", "#efe8db"],
  ["#9c3c34", "#cf6258"],
];

function coverTitle(title: string): string {
  return title.replace(/\s+/g, " ").trim();
}

function coverMonogram(title: string): string {
  const normalized = title.replace(/[^\p{L}\p{N}]/gu, "");
  return normalized.slice(0, 2).toUpperCase() || "BK";
}

export default function BookshelfPage() {
  const { t } = useI18n();
  const { session, status } = useAuth();
  const [books, setBooks] = useState<BookSummary[]>([]);
  const [coverUrls, setCoverUrls] = useState<Record<number, string | null>>({});
  const [queueSize, setQueueSize] = useState(0);
  const [booksLoading, setBooksLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadOfflineQueueStats().then((stats) => setQueueSize(stats.pending));
  }, []);

  useEffect(() => {
    if (!session) {
      setBooks([]);
      setCoverUrls({});
      setError(null);
      return;
    }

    let cancelled = false;

    async function loadBooks() {
      setBooksLoading(true);
      setError(null);
      try {
        const nextBooks = await api.listMyBooks();
        if (!cancelled) {
          setBooks(nextBooks);
        }
      } catch (reason) {
        if (!cancelled) {
          setBooks([]);
          setError(reason instanceof Error ? reason.message : t("reader.loadBooksFailed"));
        }
      } finally {
        if (!cancelled) {
          setBooksLoading(false);
        }
      }
    }

    void loadBooks();
    return () => {
      cancelled = true;
    };
  }, [session, t]);

  useEffect(() => {
    if (!session || books.length === 0) {
      setCoverUrls((current) => {
        for (const url of Object.values(current)) {
          if (url) {
            URL.revokeObjectURL(url);
          }
        }
        return {};
      });
      return;
    }

    let cancelled = false;
    const createdUrls: string[] = [];

    async function loadCovers() {
      const entries = await Promise.all(
        books.map(async (book) => {
          try {
            const blob = await api.downloadMyBookCover(book.id);
            if (!blob) {
              return [book.id, null] as const;
            }
            const url = URL.createObjectURL(blob);
            createdUrls.push(url);
            return [book.id, url] as const;
          } catch {
            return [book.id, null] as const;
          }
        }),
      );

      if (cancelled) {
        for (const url of createdUrls) {
          URL.revokeObjectURL(url);
        }
        return;
      }

      setCoverUrls((current) => {
        for (const previousUrl of Object.values(current)) {
          if (previousUrl && !createdUrls.includes(previousUrl)) {
            URL.revokeObjectURL(previousUrl);
          }
        }
        return Object.fromEntries(entries);
      });
    }

    void loadCovers();

    return () => {
      cancelled = true;
      for (const url of createdUrls) {
        URL.revokeObjectURL(url);
      }
    };
  }, [books, session]);

  const shelfRows = useMemo(() => {
    const rows: BookSummary[][] = [];
    for (let index = 0; index < books.length; index += 10) {
      rows.push(books.slice(index, index + 10));
    }
    return rows;
  }, [books]);

  if (status === "loading") {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{t("reader.title")}</h1>
          <p className="muted">{t("common.loading")}</p>
        </section>
      </main>
    );
  }

  if (!session) {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{t("reader.title")}</h1>
          <p className="muted">{t("reader.bookshelfSubtitle")}</p>
        </section>
        <section className="card auth-card">
          <h2>{t("auth.loginRequired")}</h2>
          <p className="muted">{t("auth.readerLoginHint")}</p>
          <div className="toolbar">
            <Link className="button" href={{ pathname: "/login", query: { next: "/app" } }}>
              {t("auth.openLogin")}
            </Link>
          </div>
        </section>
      </main>
    );
  }

  return (
    <main className="bookshelf-page">
      <section className="hero bookshelf-hero">
        <div className="bookshelf-hero-copy">
          <div className="eyebrow">{t("reader.libraryEyebrow")}</div>
          <h1>{t("reader.bookshelfTitle")}</h1>
          <p className="muted">{t("reader.bookshelfSubtitle")}</p>
        </div>
        <div className="bookshelf-summary">
          <div className="admin-summary-card">
            <span>{t("reader.queueSize")}</span>
            <strong>{queueSize}</strong>
          </div>
          <div className="admin-summary-card">
            <span>{t("reader.bookshelfCount")}</span>
            <strong>{books.length}</strong>
          </div>
        </div>
      </section>

      {error ? <p className="notice error">{error}</p> : null}

      <section className="bookshelf-scene card">
        <div className="bookshelf-cabinet-top">
          <button className="bookshelf-cabinet-button" type="button" aria-label={t("reader.refreshShelf")} onClick={() => window.location.reload()} disabled={booksLoading}>
            {booksLoading ? "..." : "≡"}
          </button>
          <div className="bookshelf-cabinet-title">
            <strong>{t("reader.bookshelf")}</strong>
            <span>{booksLoading ? t("reader.refreshingShelf") : t("reader.bookshelfBody")}</span>
          </div>
          <div className="bookshelf-cabinet-meta">
            <span>{t("reader.bookshelfCount")}</span>
            <strong>{books.length}</strong>
          </div>
        </div>

        {books.length === 0 ? (
          <div className="bookshelf-empty">{t("reader.noBooks")}</div>
        ) : (
          <div className="bookshelf-wood">
            {shelfRows.map((row, rowIndex) => (
              <div key={`row-${rowIndex}`} className="shelf-row">
                <div className="shelf-books">
                  {row.map((book, index) => {
                    const [start, end] = shelfPalette[(rowIndex * 8 + index) % shelfPalette.length];
                    return (
                      <Link
                        key={book.id}
                        className="book-cover"
                        href={{ pathname: "/app/read", query: { book: String(book.id) } }}
                        style={
                          {
                            "--book-start": start,
                            "--book-end": end,
                          } as CSSProperties
                        }
                      >
                        {coverUrls[book.id] ? (
                          <>
                            <img className="book-cover-image" src={coverUrls[book.id] ?? undefined} alt={book.title} />
                            <span className="book-cover-image-fade" />
                            <span className="book-cover-format floating">{book.format}</span>
                          </>
                        ) : (
                          <>
                            <span className="book-cover-shine" />
                            <span className="book-cover-format">{book.format}</span>
                            <span className="book-cover-mark">{coverMonogram(book.title)}</span>
                            <span className="book-cover-body">
                              <strong title={book.title}>{coverTitle(book.title)}</strong>
                              <small>{`${book.pluginId} · #${book.id}`}</small>
                            </span>
                          </>
                        )}
                      </Link>
                    );
                  })}
                </div>
                <div className="shelf-plank" />
              </div>
            ))}
          </div>
        )}

        <div className="bookshelf-cabinet-bottom">
          <span>{t("reader.bookshelfCount")}</span>
          <strong>{`${books.length} ${t("reader.bookshelf")}`}</strong>
        </div>
      </section>
    </main>
  );
}
