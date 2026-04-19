"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, startTransition, useEffect, useMemo, useRef, useState } from "react";
import {
  EpubReader,
  type EpubHighlight,
  type EpubNavigationRequest,
  type ReaderSelection,
  type ReaderTheme,
} from "../../../components/epub-reader";
import {
  ApiClient,
  type AnnotationView,
  type BookDetail,
  type BookSummary,
  type BookmarkView,
  type ManifestTocItem,
  type ReadingProgressMutation,
} from "../../../lib/api";
import { useAuth } from "../../../lib/auth";
import { useI18n } from "../../../lib/i18n";
import { enqueueOfflineOperation, flushPendingOperations } from "../../../lib/offline-sync";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

type FloatingPoint = {
  left: number;
  top: number;
};

type JumpOptions = {
  direction?: "forward" | "backward";
  behavior?: "default" | "section-start";
};

function extensionFor(detail: BookDetail | null): string {
  if (!detail) {
    return "book";
  }
  return detail.format.toLowerCase();
}

function chunkText(content: string, pageSize: number): string[] {
  if (!content.trim()) {
    return [""];
  }

  const pages: string[] = [];
  let cursor = 0;
  while (cursor < content.length) {
    let nextCursor = Math.min(content.length, cursor + pageSize);
    if (nextCursor < content.length) {
      const lineBreak = content.lastIndexOf("\n", nextCursor);
      if (lineBreak > cursor + Math.round(pageSize * 0.6)) {
        nextCursor = lineBreak;
      }
    }
    pages.push(content.slice(cursor, nextCursor).trim());
    cursor = nextCursor;
  }
  return pages.length > 0 ? pages : [content];
}

function parseLocationIndex(location: string | null, prefix: string): number | null {
  if (!location?.startsWith(prefix)) {
    return null;
  }
  const raw = Number.parseInt(location.slice(prefix.length), 10);
  if (Number.isNaN(raw) || raw <= 0) {
    return null;
  }
  return raw - 1;
}

function isoNow(): string {
  return new Date().toISOString();
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function resolveFloatingPoint(
  rect: ReaderSelection["rect"],
  stageRect: DOMRect | null,
  preferredOffsetY: number,
): FloatingPoint | null {
  if (!rect || !stageRect) {
    return null;
  }

  const estimatedWidth = 208;
  const localLeft = rect.left - stageRect.left + rect.width / 2 - estimatedWidth / 2;
  const localTop = rect.top - stageRect.top - preferredOffsetY;

  return {
    left: clamp(localLeft, 16, Math.max(16, stageRect.width - estimatedWidth - 16)),
    top: clamp(localTop, 16, Math.max(16, stageRect.height - 80)),
  };
}

function resolveLocationLabel(
  format: string,
  activeLocation: string | null,
  textPageIndex: number,
  textPagesLength: number,
  pdfPage: number,
  currentChapterTitle: string | null,
) {
  if (format === "txt") {
    return `第 ${textPageIndex + 1} / ${Math.max(1, textPagesLength)} 页`;
  }
  if (format === "pdf") {
    return `第 ${pdfPage} 页`;
  }
  if (currentChapterTitle) {
    return currentChapterTitle;
  }
  if (activeLocation) {
    return activeLocation;
  }
  return "Ready";
}

function ReaderWorkspaceInner() {
  const { t } = useI18n();
  const { session, status } = useAuth();
  const searchParams = useSearchParams();
  const selectedBookId = Number(searchParams.get("book"));
  const stageRef = useRef<HTMLDivElement | null>(null);
  const selectionTimerRef = useRef<number | null>(null);

  const [books, setBooks] = useState<BookSummary[]>([]);
  const [selectedBookDetail, setSelectedBookDetail] = useState<BookDetail | null>(null);
  const [readerError, setReaderError] = useState<string | null>(null);
  const [bookLoading, setBookLoading] = useState(false);
  const [textContent, setTextContent] = useState<string | null>(null);
  const [fileBlob, setFileBlob] = useState<Blob | null>(null);
  const [fileUrl, setFileUrl] = useState<string | null>(null);
  const [activeLocation, setActiveLocation] = useState<string | null>(null);
  const [progressPercent, setProgressPercent] = useState(0);
  const [bookmarks, setBookmarks] = useState<BookmarkView[]>([]);
  const [annotations, setAnnotations] = useState<AnnotationView[]>([]);
  const [fontScale, setFontScale] = useState(108);
  const [theme, setTheme] = useState<ReaderTheme>("paper");
  const [annotationNote, setAnnotationNote] = useState("");
  const [annotationColor, setAnnotationColor] = useState("#c3924a");
  const [pendingSelection, setPendingSelection] = useState<ReaderSelection | null>(null);
  const [navigationRequest, setNavigationRequest] = useState<EpubNavigationRequest>(null);
  const [textPageIndex, setTextPageIndex] = useState(0);
  const [pdfPage, setPdfPage] = useState(1);
  const [stageMotion, setStageMotion] = useState<"forward" | "backward" | null>(null);
  const [isTocOpen, setIsTocOpen] = useState(true);
  const [isNotesOpen, setIsNotesOpen] = useState(true);
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [isAnnotationComposerOpen, setIsAnnotationComposerOpen] = useState(false);
  const [editingAnnotationId, setEditingAnnotationId] = useState<number | null>(null);

  const selectedBook = books.find((book) => book.id === selectedBookId) ?? null;
  const tocItems = selectedBookDetail?.manifest?.toc ?? [];
  const format = selectedBookDetail?.format.toLowerCase() ?? "";
  const textPages = useMemo(
    () => chunkText(textContent ?? "", Math.max(1400, Math.round(5200 - (fontScale - 100) * 18))),
    [fontScale, textContent],
  );
  const epubHighlights = useMemo<EpubHighlight[]>(
    () =>
      annotations
        .filter((annotation) => !annotation.deleted && annotation.anchor.startsWith("epubcfi("))
        .map((annotation) => ({
          id: annotation.id,
          anchor: annotation.anchor,
          color: annotation.color,
        })),
    [annotations],
  );

  const currentTextPage = textPages[Math.max(0, Math.min(textPageIndex, textPages.length - 1))] ?? "";
  const currentChapterTitle =
    tocItems.find((item) => item.href === activeLocation)?.title ??
    bookmarks.find((bookmark) => bookmark.location === activeLocation)?.label ??
    null;
  const pdfHref = fileUrl ? `${fileUrl}${activeLocation ?? ""}` : null;
  const locationLabel = resolveLocationLabel(
    format,
    activeLocation,
    textPageIndex,
    textPages.length,
    pdfPage,
    currentChapterTitle,
  );
  const selectionToolbarPoint = resolveFloatingPoint(pendingSelection?.rect ?? null, stageRef.current?.getBoundingClientRect() ?? null, 58);
  const selectionComposerPoint = resolveFloatingPoint(pendingSelection?.rect ?? null, stageRef.current?.getBoundingClientRect() ?? null, -12);
  const editingAnnotation = annotations.find((annotation) => annotation.id === editingAnnotationId) ?? null;

  useEffect(() => {
    if (!session) {
      setBooks([]);
      return;
    }

    let cancelled = false;

    async function loadBooks() {
      try {
        const nextBooks = await api.listMyBooks();
        if (!cancelled) {
          setBooks(nextBooks);
        }
      } catch (reason) {
        if (!cancelled) {
          setReaderError(reason instanceof Error ? reason.message : t("reader.loadBooksFailed"));
        }
      }
    }

    void loadBooks();
    return () => {
      cancelled = true;
    };
  }, [session, t]);

  useEffect(() => {
    if (!session) {
      return;
    }

    function flushQueuedChanges() {
      void flushPendingOperations(api).catch(() => {
        // Keep the queue intact and retry on the next wake-up or online event.
      });
    }

    flushQueuedChanges();
    window.addEventListener("online", flushQueuedChanges);
    return () => window.removeEventListener("online", flushQueuedChanges);
  }, [session]);

  useEffect(() => {
    if (!session || !Number.isFinite(selectedBookId)) {
      setSelectedBookDetail(null);
      setTextContent(null);
      setFileBlob(null);
      setFileUrl(null);
      setBookmarks([]);
      setAnnotations([]);
      setPendingSelection(null);
      return;
    }

    let cancelled = false;

    async function loadBook() {
      setBookLoading(true);
      setReaderError(null);
      setPendingSelection(null);
      setIsAnnotationComposerOpen(false);

      try {
        await flushPendingOperations(api).catch(() => {
          // If the queue cannot be flushed yet, we still fall back to the last server snapshot.
        });

        const [detail, blob, nextAnnotations, nextBookmarks, syncState] = await Promise.all([
          api.getMyBook(selectedBookId),
          api.downloadMyBookFile(selectedBookId),
          api.listAnnotations(selectedBookId),
          api.listBookmarks(selectedBookId),
          api.pullSync(),
        ]);

        if (cancelled) {
          return;
        }

        const nextUrl = URL.createObjectURL(blob);
        const nextText = detail.format.toLowerCase() === "txt" ? await blob.text() : null;
        const savedProgress = syncState.progresses.find((entry) => entry.bookId === selectedBookId);
        const preferredLocation = savedProgress?.location ?? detail.manifest?.primaryLocation ?? null;

        if (cancelled) {
          URL.revokeObjectURL(nextUrl);
          return;
        }

        setSelectedBookDetail(detail);
        setFileBlob(blob);
        setFileUrl(nextUrl);
        setTextContent(nextText);
        setAnnotations(nextAnnotations.filter((annotation) => !annotation.deleted));
        setBookmarks(nextBookmarks.filter((bookmark) => !bookmark.deleted));
        setActiveLocation(preferredLocation);
        setProgressPercent(savedProgress?.progressPercent ?? 0);

        const initialTextPage = parseLocationIndex(preferredLocation, "txt-page:");
        setTextPageIndex(initialTextPage ?? 0);

        const initialPdfPage = parseLocationIndex(preferredLocation, "#page=");
        setPdfPage(initialPdfPage !== null ? initialPdfPage + 1 : 1);
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

    void loadBook();
    return () => {
      cancelled = true;
    };
  }, [selectedBookId, session, t]);

  useEffect(
    () => () => {
      if (selectionTimerRef.current !== null) {
        window.clearTimeout(selectionTimerRef.current);
      }
      if (fileUrl) {
        URL.revokeObjectURL(fileUrl);
      }
    },
    [fileUrl],
  );

  useEffect(() => {
    if (format !== "txt" || textPages.length === 0) {
      return;
    }
    const boundedIndex = Math.max(0, Math.min(textPageIndex, textPages.length - 1));
    if (boundedIndex !== textPageIndex) {
      setTextPageIndex(boundedIndex);
      return;
    }
    setActiveLocation(`txt-page:${boundedIndex + 1}`);
    setProgressPercent(((boundedIndex + 1) / textPages.length) * 100);
  }, [format, textPageIndex, textPages.length]);

  useEffect(() => {
    if (format !== "pdf") {
      return;
    }
    const nextPage = Math.max(1, pdfPage);
    if (nextPage !== pdfPage) {
      setPdfPage(nextPage);
      return;
    }
    setActiveLocation(`#page=${nextPage}`);
  }, [format, pdfPage]);

  useEffect(() => {
    if (!session || !selectedBookDetail || !activeLocation) {
      return;
    }

    const mutation: ReadingProgressMutation = {
      bookId: selectedBookDetail.id,
      location: activeLocation,
      progressPercent,
      updatedAt: isoNow(),
    };

    const timer = window.setTimeout(() => {
      void api.putProgress(selectedBookDetail.id, mutation).catch(async () => {
        await enqueueOfflineOperation({
          id: crypto.randomUUID(),
          entityType: "progress",
          payload: mutation,
          createdAt: mutation.updatedAt,
        });
      });
    }, 900);

    return () => window.clearTimeout(timer);
  }, [activeLocation, progressPercent, selectedBookDetail, session]);

  useEffect(() => {
    if (!stageMotion) {
      return;
    }
    const timer = window.setTimeout(() => setStageMotion(null), 420);
    return () => window.clearTimeout(timer);
  }, [stageMotion]);

  async function refreshNotesAndBookmarks() {
    if (!selectedBookDetail) {
      return;
    }
    const [nextAnnotations, nextBookmarks] = await Promise.all([
      api.listAnnotations(selectedBookDetail.id),
      api.listBookmarks(selectedBookDetail.id),
    ]);
    setAnnotations(nextAnnotations.filter((annotation) => !annotation.deleted));
    setBookmarks(nextBookmarks.filter((bookmark) => !bookmark.deleted));
  }

  function handleLocationChange(location: string, nextProgress: number) {
    setActiveLocation(location);
    setProgressPercent(nextProgress);
  }

  function resetSelectionUi() {
    if (selectionTimerRef.current !== null) {
      window.clearTimeout(selectionTimerRef.current);
      selectionTimerRef.current = null;
    }
    setAnnotationNote("");
    setPendingSelection(null);
    setIsAnnotationComposerOpen(false);
    setEditingAnnotationId(null);
  }

  function scheduleSelection(selection: ReaderSelection) {
    if (selectionTimerRef.current !== null) {
      window.clearTimeout(selectionTimerRef.current);
    }

    selectionTimerRef.current = window.setTimeout(() => {
      setEditingAnnotationId(null);
      setAnnotationNote("");
      setPendingSelection(selection);
      setIsAnnotationComposerOpen(false);
      selectionTimerRef.current = null;
    }, 180);
  }

  function handleSelection(selection: ReaderSelection) {
    scheduleSelection(selection);
  }

  function handleCaptureSelection() {
    const selection = window.getSelection();
    const quoteText = selection?.toString().trim() ?? "";
    const range = selection?.rangeCount ? selection.getRangeAt(0) : null;
    const rect = range ? range.getBoundingClientRect() : null;
    if (!quoteText || !activeLocation) {
      return;
    }

    scheduleSelection({
      quoteText,
      anchor: activeLocation,
      rect: rect
        ? {
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
          }
        : null,
    });
  }

  function openAnnotationEditor(annotation: AnnotationView, rect: ReaderSelection["rect"] = null) {
    if (selectionTimerRef.current !== null) {
      window.clearTimeout(selectionTimerRef.current);
      selectionTimerRef.current = null;
    }

    setPendingSelection({
      quoteText: annotation.quoteText ?? t("reader.annotationUntitled"),
      anchor: annotation.anchor,
      rect,
    });
    setEditingAnnotationId(annotation.id);
    setAnnotationNote(annotation.noteText ?? "");
    setAnnotationColor(annotation.color ?? "#c3924a");
    setIsAnnotationComposerOpen(true);
    setIsNotesOpen(true);
  }

  function handleAnnotationActivate(annotationId: number, rect: ReaderSelection["rect"] = null) {
    const annotation = annotations.find((item) => item.id === annotationId);
    if (!annotation) {
      return;
    }
    openAnnotationEditor(annotation, rect);
  }

  async function handleCreateBookmark() {
    if (!selectedBookDetail || !activeLocation) {
      return;
    }

    const mutation = {
      bookId: selectedBookDetail.id,
      action: "CREATE" as const,
      location: activeLocation,
      label: currentChapterTitle ?? `${selectedBookDetail.title} · ${activeLocation}`,
      updatedAt: isoNow(),
    };

    try {
      await api.pushSync({ bookmarks: [mutation] });
      await refreshNotesAndBookmarks();
    } catch {
      await enqueueOfflineOperation({
        id: crypto.randomUUID(),
        entityType: "bookmark",
        payload: mutation,
        createdAt: mutation.updatedAt,
      });
    }
  }

  async function handleSaveAnnotation() {
    if (!selectedBookDetail || !pendingSelection) {
      return;
    }

    const updatedAt = isoNow();
    const isEditing = editingAnnotation !== null;
    const mutation = isEditing
      ? {
          annotationId: editingAnnotation.id,
          bookId: selectedBookDetail.id,
          action: "UPDATE" as const,
          quoteText: pendingSelection.quoteText,
          noteText: annotationNote,
          color: annotationColor,
          anchor: pendingSelection.anchor,
          baseVersion: editingAnnotation.version,
          updatedAt,
        }
      : {
          clientTempId: crypto.randomUUID(),
          bookId: selectedBookDetail.id,
          action: "CREATE" as const,
          quoteText: pendingSelection.quoteText,
          noteText: annotationNote,
          color: annotationColor,
          anchor: pendingSelection.anchor,
          updatedAt,
        };

    try {
      await api.pushSync({ annotations: [mutation] });
      resetSelectionUi();
      await refreshNotesAndBookmarks();
    } catch {
      await enqueueOfflineOperation({
        id: "clientTempId" in mutation ? (mutation.clientTempId ?? crypto.randomUUID()) : crypto.randomUUID(),
        entityType: "annotation",
        payload: mutation,
        createdAt: updatedAt,
      });
      resetSelectionUi();
    }
  }

  async function handleQuickHighlight() {
    await handleSaveAnnotation();
  }

  async function handleDeleteAnnotation(annotation: AnnotationView) {
    if (!selectedBookDetail || !window.confirm("删除这条批注？")) {
      return;
    }

    const mutation = {
      annotationId: annotation.id,
      bookId: selectedBookDetail.id,
      action: "DELETE" as const,
      quoteText: annotation.quoteText,
      noteText: annotation.noteText,
      color: annotation.color,
      anchor: annotation.anchor,
      baseVersion: annotation.version,
      updatedAt: isoNow(),
    };

    try {
      await api.pushSync({ annotations: [mutation] });
      if (editingAnnotationId === annotation.id) {
        resetSelectionUi();
      }
      await refreshNotesAndBookmarks();
    } catch {
      await enqueueOfflineOperation({
        id: crypto.randomUUID(),
        entityType: "annotation",
        payload: mutation,
        createdAt: mutation.updatedAt,
      });
      if (editingAnnotationId === annotation.id) {
        resetSelectionUi();
      }
    }
  }

  async function handleCopySelection() {
    if (!pendingSelection?.quoteText) {
      return;
    }
    try {
      await navigator.clipboard.writeText(pendingSelection.quoteText);
      resetSelectionUi();
    } catch {
      setReaderError(t("common.loadingFailed"));
    }
  }

  function jumpToLocation(location: string, options: JumpOptions = {}) {
    const direction = options.direction ?? "forward";
    setStageMotion(direction);
    resetSelectionUi();

    if (format === "txt") {
      const pageIndex = parseLocationIndex(location, "txt-page:");
      if (pageIndex !== null) {
        setTextPageIndex(pageIndex);
      }
      return;
    }
    if (format === "pdf") {
      const pageIndex = parseLocationIndex(location, "#page=");
      if (pageIndex !== null) {
        setPdfPage(pageIndex + 1);
      }
      return;
    }

    if (options.behavior === "section-start") {
      setNavigationRequest({ id: Date.now(), target: location, behavior: "section-start" });
      return;
    }

    startTransition(() => {
      setActiveLocation(location);
    });
  }

  function handlePageTurn(direction: "next" | "prev") {
    setStageMotion(direction === "next" ? "forward" : "backward");
    resetSelectionUi();

    if (format === "txt") {
      setTextPageIndex((current) => {
        const delta = direction === "next" ? 1 : -1;
        return Math.max(0, Math.min(textPages.length - 1, current + delta));
      });
      return;
    }
    if (format === "pdf") {
      setPdfPage((current) => Math.max(1, current + (direction === "next" ? 1 : -1)));
      return;
    }
    setNavigationRequest({ id: Date.now(), direction });
  }

  if (status === "loading") {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{t("reader.readerPanelTitle")}</h1>
          <p className="muted">{t("common.loading")}</p>
        </section>
      </main>
    );
  }

  if (!session) {
    const loginNext = Number.isFinite(selectedBookId) ? `/app/read?book=${selectedBookId}` : "/app/read";
    return (
      <main className="grid">
        <section className="hero">
          <h1>{t("reader.readerPanelTitle")}</h1>
          <p className="muted">{t("reader.subtitle")}</p>
        </section>
        <section className="card auth-card">
          <h2>{t("auth.loginRequired")}</h2>
          <p className="muted">{t("auth.readerLoginHint")}</p>
          <div className="toolbar">
            <Link className="button" href={{ pathname: "/login", query: { next: loginNext } }}>
              {t("auth.openLogin")}
            </Link>
          </div>
        </section>
      </main>
    );
  }

  if (!selectedBook || !Number.isFinite(selectedBookId)) {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{t("reader.readerPanelTitle")}</h1>
          <p className="muted">{t("reader.selectBookPrompt")}</p>
          <div className="toolbar">
            <Link className="button" href="/app">
              {t("reader.backToShelf")}
            </Link>
          </div>
        </section>
      </main>
    );
  }

  return (
    <main className="reader-workspace reader-prototype-page">
      {readerError ? <p className="notice error">{readerError}</p> : null}

      <section className="reader-prototype-shell">
        <aside className={`reader-prototype-sidebar reader-prototype-sidebar-left ${isTocOpen ? "open" : "closed"}`}>
          <div className="reader-prototype-panel-head">
            <h2>{t("reader.tocTitle")}</h2>
            <button className="button secondary" type="button" onClick={() => setIsTocOpen(false)}>
              Close
            </button>
          </div>

          <div className="reader-prototype-panel-body">
            {tocItems.length === 0 ? (
              <p className="muted compact">{t("reader.noToc")}</p>
            ) : (
              <div className="reader-outline-list reader-prototype-outline-list">
                {tocItems.map((item: ManifestTocItem) => (
                  <button
                    key={item.href}
                    className={`reader-outline-item ${item.href === activeLocation ? "active" : ""}`}
                    type="button"
                    onClick={() => jumpToLocation(item.href, { behavior: "section-start" })}
                  >
                    {item.title}
                  </button>
                ))}
              </div>
            )}

            <section className="reader-prototype-panel-section">
              <div className="section-header">
                <h3>{t("reader.bookmarksTitle")}</h3>
                <button className="button secondary" type="button" onClick={() => void handleCreateBookmark()}>
                  {t("reader.addBookmark")}
                </button>
              </div>
              <div className="reader-outline-list reader-prototype-compact-list">
                {bookmarks.length === 0 ? <p className="muted compact">{t("common.notAvailable")}</p> : null}
                {bookmarks.map((bookmark) => (
                  <button
                    key={bookmark.id}
                    className={`reader-outline-item ${bookmark.location === activeLocation ? "active" : ""}`}
                    type="button"
                    onClick={() => jumpToLocation(bookmark.location)}
                  >
                    {bookmark.label ?? bookmark.location}
                  </button>
                ))}
              </div>
            </section>
          </div>
        </aside>

        <section className="reader-prototype-main">
          <header className="reader-prototype-header">
            <div className="reader-prototype-header-side">
              <button className="reader-prototype-icon-button" type="button" onClick={() => setIsTocOpen((value) => !value)}>
                ☰
              </button>
              <div className="reader-prototype-book-meta">
                <strong>{selectedBookDetail?.title ?? selectedBook.title}</strong>
                <span>{selectedBookDetail?.author ?? t("reader.descriptionFallback")}</span>
              </div>
            </div>

            <div className="reader-prototype-header-side reader-prototype-header-actions">
              <button className="reader-prototype-icon-button" type="button" onClick={() => setIsNotesOpen((value) => !value)}>
                ✎
              </button>
              <button className="reader-prototype-icon-button" type="button" onClick={() => setIsSettingsOpen((value) => !value)}>
                ≡
              </button>
              <Link className="reader-prototype-text-button" href="/app">
                {t("reader.backToShelf")}
              </Link>
              {fileUrl ? (
                <a className="reader-prototype-text-button" href={fileUrl} target="_blank" rel="noreferrer">
                  {t("reader.openSource")}
                </a>
              ) : null}
            </div>
          </header>

          {isSettingsOpen ? (
            <section className="reader-prototype-settings">
              <div className="reader-prototype-settings-grid">
                <label className="field">
                  <span>{t("reader.themeLabel")}</span>
                  <select className="input" value={theme} onChange={(event) => setTheme(event.target.value as ReaderTheme)}>
                    <option value="paper">{t("reader.themePaper")}</option>
                    <option value="sepia">{t("reader.themeSepia")}</option>
                    <option value="night">{t("reader.themeNight")}</option>
                    <option value="forest">{t("reader.themeForest")}</option>
                  </select>
                </label>

                <label className="field">
                  <span>{`${t("reader.fontScaleLabel")}: ${fontScale}%`}</span>
                  <input
                    className="input"
                    type="range"
                    min={90}
                    max={150}
                    step={2}
                    value={fontScale}
                    onChange={(event) => setFontScale(Number(event.target.value))}
                  />
                </label>
              </div>
            </section>
          ) : null}

          <div className="reader-prototype-stage-wrap">
            <div ref={stageRef} className={`reader-prototype-stage theme-${theme} ${stageMotion ? `motion-${stageMotion}` : ""}`}>
              {bookLoading ? (
                <div className="reader-loading">{t("reader.loadingBook")}</div>
              ) : format === "txt" ? (
                <div className="text-reader immersive-text-reader reader-prototype-text-stage" style={{ fontSize: `${fontScale}%` }} onMouseUp={handleCaptureSelection}>
                  <pre>{currentTextPage || t("reader.readerTextEmpty")}</pre>
                </div>
              ) : format === "pdf" ? (
                pdfHref ? (
                  <iframe className="document-reader-frame" src={pdfHref} title={selectedBook.title} />
                ) : (
                  <div className="reader-empty">{t("reader.readerUnavailable")}</div>
                )
              ) : format === "epub" && fileBlob ? (
                <EpubReader
                  file={fileBlob}
                  location={activeLocation}
                  theme={theme}
                  fontScale={fontScale}
                  highlights={epubHighlights}
                  navigationRequest={navigationRequest}
                  onLocationChange={handleLocationChange}
                  onAnnotationActivate={handleAnnotationActivate}
                  onSelection={handleSelection}
                  onError={setReaderError}
                />
              ) : (
                <div className="reader-empty">{t("reader.readerUnavailable")}</div>
              )}

              {pendingSelection && !isAnnotationComposerOpen ? (
                <div
                  className="reader-floating-selection-toolbar"
                  style={
                    selectionToolbarPoint
                      ? { left: `${selectionToolbarPoint.left}px`, top: `${selectionToolbarPoint.top}px` }
                      : { left: "50%", bottom: "24px", transform: "translateX(-50%)" }
                  }
                >
                  <button className="reader-prototype-icon-button small" type="button" onClick={() => void handleQuickHighlight()}>
                    高亮
                  </button>
                  <button className="reader-prototype-icon-button small" type="button" onClick={() => setIsAnnotationComposerOpen(true)}>
                    批注
                  </button>
                  <button className="reader-prototype-icon-button small" type="button" onClick={() => void handleCopySelection()}>
                    复制
                  </button>
                </div>
              ) : null}

              {pendingSelection && isAnnotationComposerOpen ? (
                <div
                  className="reader-floating-annotation-box"
                  style={
                    selectionComposerPoint
                      ? { left: `${selectionComposerPoint.left}px`, top: `${selectionComposerPoint.top}px` }
                      : { right: "24px", bottom: "24px" }
                  }
                >
                  <div className="reader-floating-annotation-head">
                    <div className="reader-floating-annotation-title">
                      {editingAnnotation ? "编辑批注" : t("reader.annotationsTitle")}
                    </div>
                    {editingAnnotation ? <span className="reader-prototype-annotation-tag">已存在批注</span> : null}
                  </div>
                  <p className="reader-selection-quote">{pendingSelection.quoteText}</p>
                  <textarea
                    className="input reader-note-input"
                    value={annotationNote}
                    onChange={(event) => setAnnotationNote(event.target.value)}
                    placeholder={t("reader.annotationNote")}
                  />
                  <div className="reader-floating-annotation-actions">
                    <input
                      className="input reader-color-input"
                      type="color"
                      value={annotationColor}
                      onChange={(event) => setAnnotationColor(event.target.value)}
                    />
                    {editingAnnotation ? (
                      <button className="button secondary" type="button" onClick={() => void handleDeleteAnnotation(editingAnnotation)}>
                        删除
                      </button>
                    ) : null}
                    <button className="button secondary" type="button" onClick={resetSelectionUi}>
                      {t("common.cancel")}
                    </button>
                    <button className="button" type="button" onClick={() => void handleSaveAnnotation()}>
                      {editingAnnotation ? "更新批注" : t("reader.saveAnnotation")}
                    </button>
                  </div>
                </div>
              ) : null}
            </div>
          </div>

          <footer className="reader-prototype-footer">
            <div className="reader-prototype-footer-meta">
              <span>{locationLabel}</span>
              <span className="reader-prototype-footer-separator">|</span>
              <span>{`${progressPercent.toFixed(1)}%`}</span>
            </div>

            <div className="reader-prototype-footer-actions">
              <button className="reader-prototype-text-button" type="button" onClick={() => handlePageTurn("prev")}>
                {t("reader.pagePrev")}
              </button>
              <button className="reader-prototype-text-button" type="button" onClick={() => handlePageTurn("next")}>
                {t("reader.pageNext")}
              </button>
            </div>
          </footer>
        </section>

        <aside className={`reader-prototype-sidebar reader-prototype-sidebar-right ${isNotesOpen ? "open" : "closed"}`}>
          <div className="reader-prototype-panel-head">
            <h2>{t("reader.annotationsTitle")}</h2>
            <button className="button secondary" type="button" onClick={() => setIsNotesOpen(false)}>
              Close
            </button>
          </div>

          <div className="reader-prototype-panel-body">
            {annotations.length === 0 ? <p className="muted compact">{t("reader.annotationHint")}</p> : null}
            <div className="reader-prototype-panel-summary">
              <span className="reader-prototype-count-badge">{annotations.length}</span>
              <span>{t("reader.annotationsTitle")}</span>
            </div>
            <div className="reader-annotation-list">
              {annotations.map((annotation) => (
                <article
                  key={annotation.id}
                  className="reader-annotation-card reader-prototype-annotation-card"
                  style={annotation.color ? { borderLeftColor: annotation.color } : undefined}
                  title={annotation.noteText ?? annotation.quoteText ?? t("reader.annotationUntitled")}
                >
                  <button className="reader-prototype-annotation-content" type="button" onClick={() => jumpToLocation(annotation.anchor)}>
                    <div className="reader-prototype-annotation-meta">
                      <span>{new Date(annotation.updatedAt).toLocaleDateString()}</span>
                      <span>{annotation.noteText ? "批注" : "高亮"}</span>
                    </div>
                    <strong>{annotation.quoteText ?? t("reader.annotationUntitled")}</strong>
                    {annotation.noteText ? <p>{annotation.noteText}</p> : <span className="reader-prototype-annotation-tag">高亮标记</span>}
                  </button>
                  <div className="reader-prototype-annotation-actions">
                    <button className="reader-prototype-icon-button small" type="button" onClick={() => jumpToLocation(annotation.anchor)}>
                      定位
                    </button>
                    <button className="reader-prototype-icon-button small" type="button" onClick={() => openAnnotationEditor(annotation)}>
                      编辑
                    </button>
                    <button className="reader-prototype-icon-button small" type="button" onClick={() => void handleDeleteAnnotation(annotation)}>
                      删除
                    </button>
                  </div>
                </article>
              ))}
            </div>
          </div>
        </aside>
      </section>
    </main>
  );
}

export default function ReaderWorkspacePage() {
  return (
    <Suspense
      fallback={
        <main className="grid">
          <section className="hero">
            <h1>Reader</h1>
            <p className="muted">Loading...</p>
          </section>
        </main>
      }
    >
      <ReaderWorkspaceInner />
    </Suspense>
  );
}
