import Link from "next/link";

export default function HomePage() {
  return (
    <main className="grid">
      <section className="hero">
        <div className="pill">Spring Boot Native-Ready</div>
        <div className="pill">Offline Sync</div>
        <div className="pill">Plugin Scanner</div>
        <h1>Private Reader</h1>
        <p className="muted">
          A self-hosted reading platform for multi-user libraries, fine-grained
          access control, NAS scanning, and offline-first annotation sync.
        </p>
        <div className="toolbar">
          <Link className="button" href="/app">
            Open Reading App
          </Link>
          <Link className="button secondary" href="/admin">
            Open Admin Console
          </Link>
        </div>
      </section>

      <section className="cards">
        <article className="card">
          <h2>Reader Experience</h2>
          <p className="muted">
            Shared Web/App reader shell with local-first annotation queue and
            sync recovery after reconnect.
          </p>
        </article>
        <article className="card">
          <h2>Admin Tools</h2>
          <p className="muted">
            Upload books, assign permissions, register scan sources, and inspect
            import jobs without leaving the browser.
          </p>
        </article>
        <article className="card">
          <h2>Format Plugins</h2>
          <p className="muted">
            EPUB, PDF, and TXT are built in. New formats can be added as
            compile-time modules without changing the import core.
          </p>
        </article>
      </section>
    </main>
  );
}

