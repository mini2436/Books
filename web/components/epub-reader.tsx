"use client";

import { useEffect, useRef } from "react";

type EpubReaderProps = {
  file: Blob;
  location: string | null;
  onError: (message: string) => void;
};

export function EpubReader({ file, location, onError }: EpubReaderProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const bookRef = useRef<any>(null);
  const renditionRef = useRef<any>(null);
  const onErrorRef = useRef(onError);
  const locationRef = useRef(location);

  useEffect(() => {
    onErrorRef.current = onError;
  }, [onError]);

  useEffect(() => {
    locationRef.current = location;
  }, [location]);

  useEffect(() => {
    let disposed = false;

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
        const rendition = book.renderTo(containerRef.current, {
          width: "100%",
          height: "100%",
          flow: "paginated",
          manager: "continuous",
        });

        bookRef.current = book;
        renditionRef.current = rendition;
        await rendition.display(locationRef.current ?? undefined);
      } catch (reason) {
        const message = reason instanceof Error ? reason.message : "Failed to open EPUB";
        onErrorRef.current(message);
      }
    }

    void mountBook();

    return () => {
      disposed = true;
      try {
        renditionRef.current?.destroy?.();
      } catch {}
      try {
        bookRef.current?.destroy?.();
      } catch {}
      renditionRef.current = null;
      bookRef.current = null;
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

  return <div ref={containerRef} className="epub-reader-host" />;
}
