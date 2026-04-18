"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  type AdminBookSummary,
  ApiClient,
  type BookDetail,
  type ImportJob,
  type LibrarySource,
  type PluginSummary,
  type UserSummary,
} from "../../lib/api";
import { useAuth } from "../../lib/auth";
import { useI18n } from "../../lib/i18n";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

function canAccessAdmin(role: string | undefined): boolean {
  return role === "SUPER_ADMIN" || role === "LIBRARIAN";
}

function formatDate(value: string | null, fallback: string): string {
  if (!value) {
    return fallback;
  }
  return new Date(value).toLocaleString();
}

export default function AdminPage() {
  const { t } = useI18n();
  const { session, status } = useAuth();
  const isSuperAdmin = session?.user.role === "SUPER_ADMIN";
  const [plugins, setPlugins] = useState<PluginSummary[]>([]);
  const [books, setBooks] = useState<AdminBookSummary[]>([]);
  const [sources, setSources] = useState<LibrarySource[]>([]);
  const [jobs, setJobs] = useState<ImportJob[]>([]);
  const [users, setUsers] = useState<UserSummary[]>([]);
  const [uploadedBook, setUploadedBook] = useState<BookDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadInputKey, setUploadInputKey] = useState(0);
  const [loadingAdminData, setLoadingAdminData] = useState(false);
  const [creatingSource, setCreatingSource] = useState(false);
  const [rescanSourceId, setRescanSourceId] = useState<number | null>(null);
  const [granting, setGranting] = useState(false);
  const [selectedBookId, setSelectedBookId] = useState("");
  const [selectedUserId, setSelectedUserId] = useState("");
  const [sourceName, setSourceName] = useState("");
  const [sourcePath, setSourcePath] = useState("");
  const [sourceEnabled, setSourceEnabled] = useState(true);

  useEffect(() => {
    if (!session || !canAccessAdmin(session.user.role)) {
      setPlugins([]);
      setBooks([]);
      setSources([]);
      setJobs([]);
      setUsers([]);
      setError(null);
      return;
    }

    const currentRole = session.user.role;
    let cancelled = false;

    async function loadAdminData() {
      setLoadingAdminData(true);
      setError(null);

      try {
        const [nextPlugins, nextBooks, nextSources, nextJobs, nextUsers] = await Promise.all([
          api.listPlugins(),
          api.listAdminBooks(),
          api.listLibrarySources(),
          api.listImportJobs(),
          currentRole === "SUPER_ADMIN" ? api.listUsers() : Promise.resolve([]),
        ]);

        if (cancelled) {
          return;
        }

        setPlugins(nextPlugins);
        setBooks(nextBooks);
        setSources(nextSources);
        setJobs(nextJobs);
        setUsers(nextUsers.filter((user) => user.enabled));
      } catch (reason) {
        if (!cancelled) {
          setError(reason instanceof Error ? reason.message : t("admin.loadPluginsFailed"));
        }
      } finally {
        if (!cancelled) {
          setLoadingAdminData(false);
        }
      }
    }

    void loadAdminData();

    return () => {
      cancelled = true;
    };
  }, [session, t]);

  async function refreshAdminData() {
    if (!session || !canAccessAdmin(session.user.role)) {
      return;
    }

    const currentRole = session.user.role;
    setLoadingAdminData(true);
    setError(null);

    try {
      const [nextPlugins, nextBooks, nextSources, nextJobs, nextUsers] = await Promise.all([
        api.listPlugins(),
        api.listAdminBooks(),
        api.listLibrarySources(),
        api.listImportJobs(),
        currentRole === "SUPER_ADMIN" ? api.listUsers() : Promise.resolve([]),
      ]);
      setPlugins(nextPlugins);
      setBooks(nextBooks);
      setSources(nextSources);
      setJobs(nextJobs);
      setUsers(nextUsers.filter((user) => user.enabled));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("admin.loadPluginsFailed"));
    } finally {
      setLoadingAdminData(false);
    }
  }

  async function handleUpload(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!uploadFile) {
      setError(t("admin.selectFileFirst"));
      return;
    }

    setUploading(true);
    setError(null);
    setNotice(null);

    try {
      const detail = await api.uploadBook(uploadFile);
      setUploadedBook(detail);
      setSelectedBookId(String(detail.id));
      setUploadFile(null);
      setUploadInputKey((value) => value + 1);
      await refreshAdminData();
      setNotice(`${t("admin.uploadSuccess")}: ${detail.title}`);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("admin.uploadFailed"));
    } finally {
      setUploading(false);
    }
  }

  async function handleCreateSource(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCreatingSource(true);
    setError(null);
    setNotice(null);

    try {
      const source = await api.createLibrarySource({
        name: sourceName,
        rootPath: sourcePath,
        enabled: sourceEnabled,
      });
      setSourceName("");
      setSourcePath("");
      setSourceEnabled(true);
      await refreshAdminData();
      setNotice(`${t("admin.sourceCreated")}: ${source.name}`);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("admin.createSourceFailed"));
    } finally {
      setCreatingSource(false);
    }
  }

  async function handleRescan(sourceId: number) {
    setRescanSourceId(sourceId);
    setError(null);
    setNotice(null);

    try {
      const result = await api.rescanLibrarySource(sourceId);
      await refreshAdminData();
      setNotice(
        `${t("admin.rescanSuccess")}: ${t("admin.rescanImported")} ${result.imported}, ${t("admin.rescanMissing")} ${result.missingMarked}`,
      );
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("admin.rescanFailed"));
    } finally {
      setRescanSourceId(null);
    }
  }

  async function handleGrant(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedBookId || !selectedUserId) {
      setError(t("admin.selectGrantTargets"));
      return;
    }

    setGranting(true);
    setError(null);
    setNotice(null);

    try {
      await api.grantBook(Number(selectedBookId), Number(selectedUserId));
      const targetBook = books.find((book) => String(book.id) === selectedBookId);
      const targetUser = users.find((user) => String(user.id) === selectedUserId);
      setNotice(
        `${t("admin.grantSuccess")}: ${targetBook?.title ?? selectedBookId} -> ${targetUser?.username ?? selectedUserId}`,
      );
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("admin.grantFailed"));
    } finally {
      setGranting(false);
    }
  }

  if (status === "loading") {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{t("admin.title")}</h1>
          <p className="muted">{t("common.loading")}</p>
        </section>
      </main>
    );
  }

  if (!session) {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{t("admin.title")}</h1>
          <p className="muted">{t("admin.subtitle")}</p>
        </section>
        <section className="card auth-card">
          <h2>{t("auth.loginRequired")}</h2>
          <p className="muted">{t("auth.adminLoginHint")}</p>
          <div className="toolbar">
            <Link className="button" href={{ pathname: "/login", query: { next: "/admin" } }}>
              {t("auth.openLogin")}
            </Link>
          </div>
        </section>
      </main>
    );
  }

  if (!canAccessAdmin(session.user.role)) {
    return (
      <main className="grid">
        <section className="hero">
          <h1>{t("admin.title")}</h1>
          <p className="muted">{t("admin.subtitle")}</p>
        </section>
        <section className="card auth-card">
          <h2>{t("auth.roleRestrictedTitle")}</h2>
          <p className="muted">{t("auth.roleRestrictedBody")}</p>
        </section>
      </main>
    );
  }

  return (
    <main className="grid">
      <section className="hero">
        <h1>{t("admin.title")}</h1>
        <p className="muted">{t("admin.subtitle")}</p>
        <div className="toolbar">
          <div className="pill">{`${t("admin.summaryPlugins")}: ${plugins.length}`}</div>
          <div className="pill">{`${t("admin.summarySources")}: ${sources.length}`}</div>
          <div className="pill">{`${t("admin.summaryJobs")}: ${jobs.length}`}</div>
          <button className="button secondary" type="button" onClick={() => void refreshAdminData()} disabled={loadingAdminData}>
            {loadingAdminData ? t("admin.refreshing") : t("admin.refreshData")}
          </button>
        </div>
      </section>

      {notice ? <p className="notice">{notice}</p> : null}
      {error ? <p className="notice error">{error}</p> : null}

      <section className="split-grid">
        <article className="card">
          <div className="section-header">
            <div>
              <h2>{t("admin.uploadTitle")}</h2>
              <p className="muted compact">{t("admin.uploadBody")}</p>
            </div>
          </div>
          <form className="form-grid" onSubmit={handleUpload}>
            <label className="field">
              <span>{t("admin.uploadField")}</span>
              <input
                key={uploadInputKey}
                className="input"
                type="file"
                accept=".epub,.pdf,.txt"
                onChange={(event) => setUploadFile(event.target.files?.[0] ?? null)}
              />
            </label>
            <div className="toolbar">
              <button className="button" type="submit" disabled={uploading}>
                {uploading ? t("admin.uploading") : t("admin.uploadAction")}
              </button>
            </div>
          </form>
          {uploadedBook ? (
            <div className="result-panel">
              <h3>{t("admin.lastUploaded")}</h3>
              <p>
                <strong>{uploadedBook.title}</strong>
              </p>
              <p className="muted compact">{`${t("admin.uploadedFormat")}: ${uploadedBook.format} | ${t("admin.uploadedPlugin")}: ${uploadedBook.pluginId}`}</p>
              <p className="muted compact">{`${t("admin.uploadedSource")}: ${uploadedBook.sourceType}`}</p>
              <p className="muted compact">
                {`${t("admin.uploadedCapabilities")}: ${uploadedBook.capabilities.join(", ") || t("common.notAvailable")}`}
              </p>
            </div>
          ) : null}
        </article>

        <article className="card">
          <div className="section-header">
            <div>
              <h2>{t("admin.sourcesTitle")}</h2>
              <p className="muted compact">{t("admin.sourcesBody")}</p>
            </div>
          </div>
          <form className="form-grid" onSubmit={handleCreateSource}>
            <label className="field">
              <span>{t("admin.sourceName")}</span>
              <input className="input" value={sourceName} onChange={(event) => setSourceName(event.target.value)} required />
            </label>
            <label className="field">
              <span>{t("admin.sourceRootPath")}</span>
              <input
                className="input"
                value={sourcePath}
                onChange={(event) => setSourcePath(event.target.value)}
                placeholder="Z:\\ebooks"
                required
              />
            </label>
            <label className="checkbox-row">
              <input
                type="checkbox"
                checked={sourceEnabled}
                onChange={(event) => setSourceEnabled(event.target.checked)}
              />
              <span>{t("admin.sourceEnabled")}</span>
            </label>
            <div className="toolbar">
              <button className="button" type="submit" disabled={creatingSource}>
                {creatingSource ? t("admin.creatingSource") : t("admin.createSource")}
              </button>
            </div>
          </form>
        </article>
      </section>

      <section className="split-grid">
        <article className="card">
          <div className="section-header">
            <div>
              <h2>{t("admin.grantsTitle")}</h2>
              <p className="muted compact">{t("admin.grantsBody")}</p>
            </div>
          </div>
          {isSuperAdmin ? (
            <form className="form-grid" onSubmit={handleGrant}>
              <label className="field">
                <span>{t("admin.grantBookField")}</span>
                <select
                  className="input"
                  value={selectedBookId}
                  onChange={(event) => setSelectedBookId(event.target.value)}
                  required
                >
                  <option value="">{t("admin.selectBookPrompt")}</option>
                  {books.map((book) => (
                    <option key={book.id} value={book.id}>
                      {`${book.title} (#${book.id})`}
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>{t("admin.grantUserField")}</span>
                <select
                  className="input"
                  value={selectedUserId}
                  onChange={(event) => setSelectedUserId(event.target.value)}
                  required
                >
                  <option value="">{t("admin.selectUserPrompt")}</option>
                  {users.map((user) => (
                    <option key={user.id} value={user.id}>
                      {`${user.username} (${user.role})`}
                    </option>
                  ))}
                </select>
              </label>
              <div className="toolbar">
                <button className="button" type="submit" disabled={granting || books.length === 0 || users.length === 0}>
                  {granting ? t("admin.granting") : t("admin.grantAction")}
                </button>
              </div>
            </form>
          ) : (
            <p className="muted compact">{t("admin.grantsSuperAdminOnly")}</p>
          )}
        </article>

        <article className="card">
          <div className="section-header">
            <div>
              <h2>{t("admin.usersTitle")}</h2>
              <p className="muted compact">{t("admin.usersBody")}</p>
            </div>
          </div>
          {isSuperAdmin ? (
            <table className="table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>{t("admin.tableUserName")}</th>
                  <th>{t("admin.tableUserRole")}</th>
                  <th>{t("admin.tableUserEnabled")}</th>
                </tr>
              </thead>
              <tbody>
                {users.length === 0 ? (
                  <tr>
                    <td colSpan={4}>{t("admin.noUsers")}</td>
                  </tr>
                ) : (
                  users.map((user) => (
                    <tr key={user.id}>
                      <td>{user.id}</td>
                      <td>{user.username}</td>
                      <td>{user.role}</td>
                      <td>{user.enabled ? t("common.enabled") : t("common.disabled")}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          ) : (
            <p className="muted compact">{t("admin.usersSuperAdminOnly")}</p>
          )}
        </article>
      </section>

      <section className="card">
        <div className="section-header">
          <div>
            <h2>{t("admin.sourcesListTitle")}</h2>
            <p className="muted compact">{t("admin.sourcesListBody")}</p>
          </div>
        </div>
        <table className="table">
          <thead>
            <tr>
              <th>{t("admin.tableSourceName")}</th>
              <th>{t("admin.tableSourcePath")}</th>
              <th>{t("admin.tableSourceEnabled")}</th>
              <th>{t("admin.tableSourceLastScan")}</th>
              <th>{t("admin.tableActions")}</th>
            </tr>
          </thead>
          <tbody>
            {sources.length === 0 ? (
              <tr>
                <td colSpan={5}>{t("admin.noSources")}</td>
              </tr>
            ) : (
              sources.map((source) => (
                <tr key={source.id}>
                  <td>{source.name}</td>
                  <td className="code">{source.rootPath}</td>
                  <td>{source.enabled ? t("common.enabled") : t("common.disabled")}</td>
                  <td>{formatDate(source.lastScanAt, t("admin.neverScanned"))}</td>
                  <td>
                    <button
                      className="button secondary"
                      type="button"
                      disabled={!source.enabled || rescanSourceId === source.id}
                      onClick={() => void handleRescan(source.id)}
                    >
                      {rescanSourceId === source.id ? t("admin.rescanning") : t("admin.rescanAction")}
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>

      <section className="card">
        <div className="section-header">
          <div>
            <h2>{t("admin.booksTitle")}</h2>
            <p className="muted compact">{t("admin.booksBody")}</p>
          </div>
        </div>
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
            {books.length === 0 ? (
              <tr>
                <td colSpan={6}>{t("admin.noBooks")}</td>
              </tr>
            ) : (
              books.map((book) => (
                <tr key={book.id}>
                  <td>{book.id}</td>
                  <td>
                    <div>{book.title}</div>
                    {book.sourceMissing ? <div className="inline-status">{t("reader.statusMissing")}</div> : null}
                  </td>
                  <td>{book.author ?? t("common.notAvailable")}</td>
                  <td>{`${book.format} / ${book.pluginId}`}</td>
                  <td>{book.sourceType}</td>
                  <td>{formatDate(book.updatedAt, t("common.notAvailable"))}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>

      <section className="card">
        <div className="section-header">
          <div>
            <h2>{t("admin.importJobsTitle")}</h2>
            <p className="muted compact">{t("admin.importJobsBody")}</p>
          </div>
        </div>
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
            {jobs.length === 0 ? (
              <tr>
                <td colSpan={6}>{t("admin.noImportJobs")}</td>
              </tr>
            ) : (
              jobs.map((job) => (
                <tr key={job.id}>
                  <td>{job.id}</td>
                  <td>{job.bookId}</td>
                  <td>{job.sourceId ?? t("common.notAvailable")}</td>
                  <td>{job.status}</td>
                  <td>{job.message ?? t("common.notAvailable")}</td>
                  <td>{formatDate(job.createdAt, t("common.notAvailable"))}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>

      <section className="card">
        <div className="section-header">
          <div>
            <h2>{t("admin.pluginsTitle")}</h2>
            <p className="muted compact">{t("admin.pluginsBody")}</p>
          </div>
        </div>
        <table className="table">
          <thead>
            <tr>
              <th>{t("admin.tablePlugin")}</th>
              <th>{t("admin.tableExtensions")}</th>
              <th>{t("admin.tableCapabilities")}</th>
            </tr>
          </thead>
          <tbody>
            {plugins.length === 0 ? (
              <tr>
                <td colSpan={3}>{t("admin.noPlugins")}</td>
              </tr>
            ) : (
              plugins.map((plugin) => (
                <tr key={plugin.pluginId}>
                  <td>{plugin.displayName}</td>
                  <td>{plugin.supportedExtensions.join(", ")}</td>
                  <td>{plugin.capabilities.join(", ")}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>
    </main>
  );
}
