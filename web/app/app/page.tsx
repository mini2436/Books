"use client";

import Link from "next/link";
import { startTransition, useEffect, useState } from "react";
import { EpubReader } from "../../components/epub-reader";
import { ApiClient, type BookDetail, type BookSummary, type ManifestTocItem } from "../../lib/api";
import { useAuth } from "../../lib/auth";
import { useI18n } from "../../lib/i18n";
import { loadOfflineQueueStats } from "../../lib/offline-sync";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

function extensionFor(detail: BookDetail | null): string {
  if (!detail) {
    return "book";
  }
  return detail.format.toLowerCase();
}

export default function ReaderAppPage() {
  const { t } = useI18n();
  const { session, status } = useAuth();
  const [books, setBooks] = useState<BookSummary[]>([]);
  const [queueSize, setQueueSize] = useState(0);
  const [shelfError, setShelfError] = useState<string | null>(null);
  const [booksLoading, setBooksLoading] = useState(false);
  const [selectedBookId, setSelectedBookId] = useState<number | null>(null);
  const [selectedBookDetail, setSelectedBookDetail] = useState<BookDetail | null>(null);
  const [readerError, setReaderError] = useState<string | null>(null);
  const [bookLoading, setBookLoading] = useState(false);
  const [textContent, setTextContent] = useState<string | null>(null);
  const [fileBlob, setFileBlob] = useState<Blob | null>(null);
  const [fileUrl, setFileUrl] = useState<string | null>(null);
  const [activeLocation, setActiveLocation] = useState<string | null>(null);

  const selectedBook = books.find((book) => book.id === selectedBookId) ?? null;
  const tocItems = selectedBookDetail?.manifest?.toc ?? [];

  useEffect(() => {
    loadOfflineQueueStats().then((stats) => setQueueSize(stats.pending));
  }, []);

  useEffect(() => {
    if (!session) {
      setBooks([]);
      setShelfError(null);
      setBooksLoading(false);
      setSelectedBookId(null);
      return;
    }

    let cancelled = false;

    async function loadBooks() {
      setBooksLoading(true);
      setShelfError(null);

      try {
        const nextBooks = await api.listMyBooks();

        if (cancelled) {
          return;
        }

        setBooks(nextBooks);
        setSelectedBookId((current) => {
          if (nextBooks.length === 0) {
            return null;
          }
          if (current && nextBooks.some((book) => book.id === current)) {
            return current;
          }
          return nextBooks[0].id;
        });
      } catch (reason) {
        if (!cancelled) {
          setBooks([]);
          setSelectedBookId(null);
          setShelfError(reason instanceof Error ? reason.message : t("reader.loadBooksFailed"));
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
    if (!session || selectedBookId === null) {
      setSelectedBookDetail(null);
      setReaderError(null);
      setTextContent(null);
      setFileBlob(null);
      setFileUrl(null);
      setActiveLocation(null);
      setBookLoading(false);
      return;
    }

    const currentBookId = selectedBookId;
    let cancelled = false;

    async function loadSelectedBook() {
      setBookLoading(true);
      setReaderError(null);
      setSelectedBookDetail(null);
      setTextContent(null);
      setFileBlob(null);
      setFileUrl(null);
      setActiveLocation(null);

      try {
        const [detail, blob] = await Promise.all([
          api.getMyBook(currentBookId),
          api.downloadMyBookFile(currentBookId),
        ]);

        if (cancelled) {
          return;
        }

        const nextUrl = URL.createObjectURL(blob);
        const nextText = detail.format.toLowerCase() === "txt" ? await blob.text() : null;

        if (cancelled) {
          URL.revokeObjectURL(nextUrl);
          return;
        }

        setSelectedBookDetail(detail);
        setFileBlob(blob);
        setFileUrl(nextUrl);
        setTextContent(nextText);
        setActiveLocation(detail.manifest?.primaryLocation ?? null);
      } catch (reason) {
        if (!cancelled) {
          setReaderError(reason instanceof Error ? reason.message : t("reader.loadBookFailed"));
        }
      } finally {
        if (!cancelled) {
          setBookLoading(false);
        }
      }
    }

    void loadSelectedBook();

    return () => {
      cancelled = true;
    };
  }, [books, selectedBookId, session, t]);

  useEffect(
    () => () => {
      if (fileUrl) {
        URL.revokeObjectURL(fileUrl);
      }
    },
    [fileUrl],
  );

  async function handleRefreshBooks() {
    if (!session) {
      return;
    }

    setBooksLoading(true);
    setShelfError(null);

    try {
      const nextBooks = await api.listMyBooks();
      setBooks(nextBooks);
      setSelectedBookId((current) => {
        if (nextBooks.length === 0) {
          return null;
        }
        if (current && nextBooks.some((book) => book.id === current)) {
          return current;
        }
        return nextBooks[0].id;
      });
    } catch (reason) {
      setShelfError(reason instanceof Error ? reason.message : t("reader.loadBooksFailed"));
    } finally {
      setBooksLoading(false);
    }
  }

  function handleSelectBook(bookId: number) {
    startTransition(() => {
      setSelectedBookId(bookId);
    });
  }

  function handleJumpToLocation(item: ManifestTocItem) {
    startTransition(() => {
      setActiveLocation(item.href);
    });
  }

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
          <p className="muted">{t("reader.subtitle")}</p>
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
    <main className="grid">
      <section className="hero">
        <h1>{t("reader.title")}</h1>
        <p className="muted">{t("reader.subtitle")}</p>
        <div className="toolbar">
          <div className="pill">{`${t("reader.queueSize")}: ${queueSize}`}</div>
          <div className="pill">
            {selectedBook ? `${t("reader.activeBook")}: ${selectedBook.title}` : t("reader.selectBookPrompt")}
          </div>
        </div>
      </section>

      <section className="reader-layout">
        <aside className="card reader-sidebar">
          <div className="section-header">
            <div>
              <h2>{t("reader.bookshelf")}</h2>
              <p className="muted compact">{t("reader.bookshelfBody")}</p>
            </div>
            <button className="button secondary" type="button" onClick={() => void handleRefreshBooks()} disabled={booksLoading}>
              {booksLoading ? t("reader.refreshingShelf") : t("reader.refreshShelf")}
            </button>
          </div>

          {shelfError ? <p className="notice error">{shelfError}</p> : null}

          <div className="reader-book-list">
            {books.length === 0 ? (
              <div className="reader-empty">{t("reader.noBooks")}</div>
            ) : (
              books.map((book) => (
                <button
                  key={book.id}
                  type="button"
                  className={`reader-book-item${selectedBookId === book.id ? " active" : ""}`}
                  onClick={() => handleSelectBook(book.id)}
                >
                  <div className="reader-book-item-head">
                    <strong>{book.title}</strong>
                    <span className="code">{book.format}</span>
                  </div>
                  <div className="reader-book-item-meta">
                    <span>{book.pluginId}</span>
                    <span>{book.sourceMissing ? t("reader.statusMissing") : t("reader.statusReady")}</span>
                  </div>
                </button>
              ))
            )}
          </div>
        </aside>

        <section className="reader-main">
          <article className="card reader-detail-card">
            {selectedBookDetail ? (
              <>
                <div className="section-header">
                  <div>
                    <h2>{selectedBookDetail.title}</h2>
                    <p className="muted compact">{selectedBookDetail.author ?? t("common.notAvailable")}</p>
                  </div>
                  <div className="toolbar reader-actions">
                    {fileUrl ? (
                      <>
                        <a
                          className="button secondary"
                          href={fileUrl}
                          target="_blank"
                          rel="noreferrer"
                        >
                          {t("reader.openSource")}
                        </a>
                        <a
                          className="button secondary"
                          href={fileUrl}
                          download={`${selectedBookDetail.title}.${extensionFor(selectedBookDetail)}`}
                        >
                          {t("reader.downloadCopy")}
                        </a>
                      </>
                    ) : null}
                  </div>
                </div>
                <p className="muted">{selectedBookDetail.description ?? t("reader.descriptionFallback")}</p>
                <div className="reader-meta-grid">
                  <div className="reader-meta-pill">{`${t("reader.metaFormat")}: ${selectedBookDetail.format}`}</div>
                  <div className="reader-meta-pill">{`${t("reader.metaPlugin")}: ${selectedBookDetail.pluginId}`}</div>
                  <div className="reader-meta-pill">{`${t("reader.metaSource")}: ${selectedBookDetail.sourceType}`}</div>
                  <div className="reader-meta-pill">{`${t("reader.metaCapabilities")}: ${selectedBookDetail.capabilities.join(", ")}`}</div>
                </div>
              </>
            ) : (
              <>
                <h2>{t("reader.readerPanelTitle")}</h2>
                <p className="muted">{t("reader.selectBookPrompt")}</p>
              </>
            )}
          </article>

          {readerError ? <p className="notice error">{readerError}</p> : null}

          <div className="reader-content-layout">
            <aside className="card reader-outline-card">
              <h3>{t("reader.tocTitle")}</h3>
              {tocItems.length === 0 ? (
                <p className="muted compact">{t("reader.noToc")}</p>
              ) : (
                <div className="reader-outline-list">
                  {tocItems.map((item) => (
                    <button
                      key={item.href}
                      type="button"
                      className={`reader-outline-item${activeLocation === item.href ? " active" : ""}`}
                      onClick={() => handleJumpToLocation(item)}
                    >
                      {item.title}
                    </button>
                  ))}
                </div>
              )}
            </aside>

            <article className="card reader-stage-card">
              <div className="section-header">
                <div>
                  <h3>{t("reader.readerPanelTitle")}</h3>
                  <p className="muted compact">
                    {selectedBookDetail?.format.toLowerCase() === "pdf"
                      ? t("reader.pdfHint")
                      : selectedBookDetail?.format.toLowerCase() === "epub"
                        ? t("reader.epubHint")
                        : t("reader.textHint")}
                  </p>
                </div>
              </div>

              {selectedBook && selectedBook.sourceMissing ? (
                <div className="reader-empty">{t("reader.bookMissingBody")}</div>
              ) : bookLoading ? (
                <div className="reader-loading">{t("reader.loadingBook")}</div>
              ) : !selectedBookDetail ? (
                <div className="reader-empty">{t("reader.selectBookPrompt")}</div>
              ) : selectedBookDetail.format.toLowerCase() === "txt" ? (
                <article className="text-reader">
                  {textContent ? <pre>{textContent}</pre> : <p>{t("reader.readerTextEmpty")}</p>}
                </article>
              ) : selectedBookDetail.format.toLowerCase() === "pdf" && fileUrl ? (
                <iframe
                  className="document-reader-frame"
                  src={fileUrl}
                  title={selectedBookDetail.title}
                />
              ) : selectedBookDetail.format.toLowerCase() === "epub" && fileBlob ? (
                <EpubReader
                  file={fileBlob}
                  location={activeLocation}
                  onError={(message) => setReaderError(message)}
                />
              ) : (
                <div className="reader-empty">{t("reader.readerUnavailable")}</div>
              )}
            </article>
          </div>
        </section>
      </section>
    </main>
  );
}
