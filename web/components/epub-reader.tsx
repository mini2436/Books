"use client";

import { useEffect, useRef, useState } from "react";

export type ReaderTheme = "paper" | "sepia" | "night" | "forest";

export type EpubHighlight = {
  id: number;
  anchor: string;
  color: string | null;
};

export type EpubNavigationRequest = {
  id: number;
  direction: "next" | "prev";
} | {
  id: number;
  target: string;
  behavior?: "default" | "section-start";
} | null;

export type ReaderSelection = {
  quoteText: string;
  anchor: string;
  rect: {
    left: number;
    top: number;
    width: number;
    height: number;
  } | null;
};

type EpubReaderProps = {
  file: Blob;
  location: string | null;
  theme: ReaderTheme;
  fontScale: number;
  highlights: EpubHighlight[];
  navigationRequest: EpubNavigationRequest;
  onLocationChange: (location: string, progressPercent: number) => void;
  onAnnotationActivate?: (annotationId: number, rect: ReaderSelection["rect"]) => void;
  onSelection: (selection: ReaderSelection) => void;
  onError: (message: string) => void;
};

const themeStyles: Record<ReaderTheme, Record<string, string>> = {
  paper: {
    body: "background: #f8f1e2; color: #2c241b; font-family: Georgia, serif; line-height: 1.8;",
    "::selection": "background: rgba(166, 114, 70, 0.35);",
  },
  sepia: {
    body: "background: #ead7bf; color: #3e2f1f; font-family: Georgia, serif; line-height: 1.85;",
    "::selection": "background: rgba(132, 78, 28, 0.35);",
  },
  night: {
    body: "background: #17171a; color: #ece5d8; font-family: Georgia, serif; line-height: 1.85;",
    "a, a:visited": "color: #f0c68e;",
    "::selection": "background: rgba(240, 198, 142, 0.35);",
  },
  forest: {
    body: "background: #e3ebde; color: #233222; font-family: Georgia, serif; line-height: 1.85;",
    "::selection": "background: rgba(74, 111, 73, 0.28);",
  },
};

function buildReaderStyles(theme: ReaderTheme): Record<string, string> {
  return {
    html: "height: auto !important;",
    body: `${themeStyles[theme].body} margin: 0 auto; padding: 40px 44px 56px; width: min(920px, calc(100% - 32px)); max-width: 100%; min-height: 100%;`,
    "img, svg, video, canvas": "max-width: 100%; height: auto;",
  };
}

export function EpubReader({
  file,
  location,
  theme,
  fontScale,
  highlights,
  navigationRequest,
  onLocationChange,
  onAnnotationActivate,
  onSelection,
  onError,
}: EpubReaderProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const bookRef = useRef<any>(null);
  const renditionRef = useRef<any>(null);
  const onErrorRef = useRef(onError);
  const locationRef = useRef(location);
  const themeRef = useRef(theme);
  const fontScaleRef = useRef(fontScale);
  const onLocationChangeRef = useRef(onLocationChange);
  const onAnnotationActivateRef = useRef(onAnnotationActivate);
  const onSelectionRef = useRef(onSelection);
  const appliedHighlightIdsRef = useRef<Map<string, string>>(new Map());
  const lastNavigationIdRef = useRef<number | null>(null);
  const isPointerDownRef = useRef(false);
  const selectionEmitTimerRef = useRef<number | null>(null);
  const pendingSelectionRef = useRef<{ selection: ReaderSelection; clearSelection: () => void } | null>(null);
  const [renditionRevision, setRenditionRevision] = useState(0);

  useEffect(() => {
    onErrorRef.current = onError;
  }, [onError]);

  useEffect(() => {
    onLocationChangeRef.current = onLocationChange;
  }, [onLocationChange]);

  useEffect(() => {
    onAnnotationActivateRef.current = onAnnotationActivate;
  }, [onAnnotationActivate]);

  useEffect(() => {
    onSelectionRef.current = onSelection;
  }, [onSelection]);

  useEffect(() => {
    locationRef.current = location;
  }, [location]);

  useEffect(() => {
    themeRef.current = theme;
  }, [theme]);

  useEffect(() => {
    fontScaleRef.current = fontScale;
  }, [fontScale]);

  useEffect(() => {
    if (!renditionRef.current) {
      return;
    }

    renditionRef.current.themes.default(buildReaderStyles(theme));
    renditionRef.current.themes.fontSize(`${fontScale}%`);
  }, [fontScale, theme]);

  useEffect(() => {
    if (!containerRef.current) {
      return;
    }

    const container = containerRef.current;
    let frameId: number | null = null;

    function syncRenditionSize() {
      const rendition = renditionRef.current;
      if (!rendition) {
        return;
      }

      const width = Math.max(Math.floor(container.clientWidth), 320);
      const height = Math.max(Math.floor(container.clientHeight), 700);
      rendition.resize?.(width, height);
    }

    const observer = new ResizeObserver(() => {
      if (frameId !== null) {
        window.cancelAnimationFrame(frameId);
      }
      frameId = window.requestAnimationFrame(() => {
        syncRenditionSize();
        frameId = null;
      });
    });

    observer.observe(container);
    syncRenditionSize();

    return () => {
      observer.disconnect();
      if (frameId !== null) {
        window.cancelAnimationFrame(frameId);
      }
    };
  }, []);

  useEffect(() => {
    let disposed = false;
    let localBook: any = null;
    let localRendition: any = null;

    function clearScheduledSelection() {
      if (selectionEmitTimerRef.current !== null) {
        window.clearTimeout(selectionEmitTimerRef.current);
        selectionEmitTimerRef.current = null;
      }
    }

    function emitPendingSelection() {
      clearScheduledSelection();
      const pendingSelection = pendingSelectionRef.current;
      if (!pendingSelection) {
        return;
      }

      onSelectionRef.current(pendingSelection.selection);
      pendingSelection.clearSelection();
      pendingSelectionRef.current = null;
    }

    function schedulePendingSelection() {
      clearScheduledSelection();
      selectionEmitTimerRef.current = window.setTimeout(() => {
        emitPendingSelection();
      }, 150);
    }

    async function mountBook() {
      if (!containerRef.current) {
        return;
      }

      try {
        const epubModule = await import("epubjs");
        const ePub = (epubModule.default ?? epubModule) as (input: ArrayBuffer) => any;
        const arrayBuffer = await file.arrayBuffer();

        if (disposed || !containerRef.current) {
          return;
        }

        containerRef.current.innerHTML = "";
        const book = ePub(arrayBuffer);
        const width = Math.max(Math.floor(containerRef.current.clientWidth), 320);
        const height = Math.max(Math.floor(containerRef.current.clientHeight), 700);
        const rendition = book.renderTo(containerRef.current, {
          width,
          height,
          flow: "scrolled-doc",
          manager: "continuous",
          spread: "none",
          allowScriptedContent: true,
        });

        if (disposed) {
          try {
            rendition.destroy?.();
          } catch {}
          try {
            book.destroy?.();
          } catch {}
          return;
        }

        localBook = book;
        localRendition = rendition;
        bookRef.current = book;
        renditionRef.current = rendition;
        setRenditionRevision((current) => current + 1);
        rendition.spread("none");
        rendition.flow("scrolled-doc");
        rendition.hooks.content.register((contents: any) => {
          contents.addStylesheetRules(buildReaderStyles(themeRef.current));
          const frame = contents?.document?.defaultView?.frameElement as HTMLIFrameElement | null;
          if (frame) {
            frame.style.width = "100%";
            frame.style.maxWidth = "100%";
            frame.style.height = "100%";
            frame.style.background = "transparent";
          }

          const document = contents?.document as Document | undefined;
          if (document) {
            const handlePointerStart = () => {
              isPointerDownRef.current = true;
              clearScheduledSelection();
            };

            const handlePointerEnd = () => {
              isPointerDownRef.current = false;
              if (pendingSelectionRef.current) {
                schedulePendingSelection();
              }
            };

            document.addEventListener("mousedown", handlePointerStart);
            document.addEventListener("touchstart", handlePointerStart, { passive: true });
            document.addEventListener("mouseup", handlePointerEnd);
            document.addEventListener("touchend", handlePointerEnd);
          }
        });
        rendition.themes.default(buildReaderStyles(themeRef.current));
        rendition.themes.fontSize(`${fontScaleRef.current}%`);

        rendition.on("relocated", (currentLocation: any) => {
          const nextLocation =
            currentLocation?.start?.cfi ??
            currentLocation?.start?.href ??
            currentLocation?.end?.cfi ??
            currentLocation?.end?.href;
          if (!nextLocation) {
            return;
          }

          const progress =
            typeof currentLocation?.start?.percentage === "number"
              ? currentLocation.start.percentage * 100
              : 0;
          onLocationChangeRef.current(nextLocation, progress);
        });

        rendition.on("selected", (cfiRange: string, contents: any) => {
          const quoteText = contents?.window?.getSelection?.()?.toString?.()?.trim?.() ?? "";
          const range = contents?.window?.getSelection?.()?.rangeCount ? contents.window.getSelection().getRangeAt(0) : null;
          const rect = range?.getBoundingClientRect?.() ?? null;
          const frameRect = (contents?.document?.defaultView?.frameElement as HTMLIFrameElement | null)?.getBoundingClientRect?.() ?? null;
          if (quoteText) {
            pendingSelectionRef.current = {
              selection: {
                quoteText,
                anchor: cfiRange,
                rect:
                  rect && frameRect
                    ? {
                        left: frameRect.left + rect.left,
                        top: frameRect.top + rect.top,
                        width: rect.width,
                        height: rect.height,
                      }
                    : null,
              },
              clearSelection: () => {
                contents?.window?.getSelection?.()?.removeAllRanges?.();
              },
            };
            if (!isPointerDownRef.current) {
              schedulePendingSelection();
            }
          }
        });

        await rendition.display(locationRef.current ?? undefined);
      } catch (reason) {
        const message = reason instanceof Error ? reason.message : "Failed to open EPUB";
        onErrorRef.current(message);
      }
    }

    void mountBook();

    return () => {
      disposed = true;
      if (renditionRef.current === localRendition) {
        renditionRef.current = null;
      }
      if (bookRef.current === localBook) {
        bookRef.current = null;
      }
      clearScheduledSelection();
      pendingSelectionRef.current = null;
      try {
        localRendition?.destroy?.();
      } catch {}
      try {
        localBook?.destroy?.();
      } catch {}
    };
  }, [file]);

  useEffect(() => {
    if (!location || !renditionRef.current) {
      return;
    }

    renditionRef.current.display(location).catch((reason: unknown) => {
      const message = reason instanceof Error ? reason.message : "Failed to navigate EPUB";
      onErrorRef.current(message);
    });
  }, [location]);

  useEffect(() => {
    if (!navigationRequest || !renditionRef.current || navigationRequest.id === lastNavigationIdRef.current) {
      return;
    }

    lastNavigationIdRef.current = navigationRequest.id;
    const action =
      "target" in navigationRequest
        ? renditionRef.current.display(navigationRequest.target).then(() => {
            if (navigationRequest.behavior === "section-start") {
              const contents = renditionRef.current.getContents?.() ?? [];
              contents.forEach((item: any) => {
                item.window?.scrollTo?.(0, 0);
                if (item.document?.documentElement) {
                  item.document.documentElement.scrollTop = 0;
                }
                if (item.document?.body) {
                  item.document.body.scrollTop = 0;
                }
              });
            }
          })
        : navigationRequest.direction === "prev"
          ? renditionRef.current.prev?.()
          : renditionRef.current.next?.();
    Promise.resolve(action).catch((reason: unknown) => {
      const message = reason instanceof Error ? reason.message : "Failed to turn EPUB page";
      onErrorRef.current(message);
    });
  }, [navigationRequest]);

  useEffect(() => {
    const rendition = renditionRef.current;
    if (!rendition?.annotations) {
      return;
    }

    appliedHighlightIdsRef.current.forEach((anchor, annotationId) => {
      rendition.annotations.remove(anchor, "highlight", annotationId);
    });

    const nextHighlights = new Map<string, string>();

    for (const highlight of highlights) {
      const annotationId = `annotation-${highlight.id}`;
      rendition.annotations.highlight(
        highlight.anchor,
        {},
        (event: Event | undefined) => {
          const target = event?.target;
          const rect =
            target instanceof Element
              ? (() => {
                  const box = target.getBoundingClientRect();
                  return {
                    left: box.left,
                    top: box.top,
                    width: box.width,
                    height: box.height,
                  };
                })()
              : null;
          onAnnotationActivateRef.current?.(highlight.id, rect);
        },
        annotationId,
        {
          fill: highlight.color ?? "#c3924a",
          "fill-opacity": 0.28,
          "mix-blend-mode": "multiply",
        },
      );
      nextHighlights.set(annotationId, highlight.anchor);
    }

    appliedHighlightIdsRef.current = nextHighlights;
  }, [highlights, renditionRevision]);

  return <div ref={containerRef} className="epub-reader-host" />;
}
