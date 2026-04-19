"use client";

import { useEffect, useRef } from "react";

export type ReaderTheme = "paper" | "sepia" | "night" | "forest";

export type EpubHighlight = {
  id: number;
  anchor: string;
  color: string | null;
};

export type EpubNavigationRequest = {
  id: number;
  direction: "next" | "prev";
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
    body: `${themeStyles[theme].body} margin: 0 auto; padding: 40px 44px 56px; max-width: 760px; min-height: 100%;`,
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
  const onSelectionRef = useRef(onSelection);
  const appliedHighlightIdsRef = useRef<Set<string>>(new Set());
  const lastNavigationIdRef = useRef<number | null>(null);

  useEffect(() => {
    onErrorRef.current = onError;
  }, [onError]);

  useEffect(() => {
    onLocationChangeRef.current = onLocationChange;
  }, [onLocationChange]);

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
    let disposed = false;
    let localBook: any = null;
    let localRendition: any = null;

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
            onSelectionRef.current({
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
            });
          }
          contents?.window?.getSelection?.()?.removeAllRanges?.();
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
    const action = navigationRequest.direction === "prev" ? renditionRef.current.prev?.() : renditionRef.current.next?.();
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

    const nextIds = new Set(highlights.map((item) => `annotation-${item.id}`));

    for (const appliedId of appliedHighlightIdsRef.current) {
      if (!nextIds.has(appliedId)) {
        const cfiRange = highlights.find((item) => `annotation-${item.id}` === appliedId)?.anchor;
        if (cfiRange) {
          rendition.annotations.remove(cfiRange, "highlight", appliedId);
        }
      }
    }

    for (const highlight of highlights) {
      const annotationId = `annotation-${highlight.id}`;
      if (appliedHighlightIdsRef.current.has(annotationId)) {
        continue;
      }
      rendition.annotations.highlight(
        highlight.anchor,
        {},
        undefined,
        annotationId,
        {
          fill: highlight.color ?? "#c3924a",
          "fill-opacity": 0.28,
          "mix-blend-mode": "multiply",
        },
      );
    }

    appliedHighlightIdsRef.current = nextIds;
  }, [highlights]);

  return <div ref={containerRef} className="epub-reader-host" />;
}
