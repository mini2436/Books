"use client";

import { useEffect, useState } from "react";
import { AdminShell } from "../../../components/admin-shell";
import { ApiClient, type AdminBookSummary, type UserSummary } from "../../../lib/api";
import { useAuth } from "../../../lib/auth";
import { useI18n } from "../../../lib/i18n";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

export default function AdminAccessPage() {
  const { t } = useI18n();
  const { session } = useAuth();
  const isSuperAdmin = session?.user.role === "SUPER_ADMIN";
  const [books, setBooks] = useState<AdminBookSummary[]>([]);
  const [users, setUsers] = useState<UserSummary[]>([]);
  const [selectedBookId, setSelectedBookId] = useState("");
  const [selectedUserId, setSelectedUserId] = useState("");
  const [granting, setGranting] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!session) {
      setBooks([]);
      setUsers([]);
      return;
    }

    let cancelled = false;

    async function loadData() {
      try {
        const [nextBooks, nextUsers] = await Promise.all([
          api.listAdminBooks(),
          isSuperAdmin ? api.listUsers() : Promise.resolve([]),
        ]);
        if (!cancelled) {
          setBooks(nextBooks);
          setUsers(nextUsers.filter((user) => user.enabled));
        }
      } catch {
        if (!cancelled) {
          setBooks([]);
          setUsers([]);
        }
      }
    }

    void loadData();
    return () => {
      cancelled = true;
    };
  }, [isSuperAdmin, session]);

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

  return (
    <AdminShell title={t("admin.nav.access.title")} subtitle={t("admin.accessPageBody")}>
      {notice ? <p className="notice">{notice}</p> : null}
      {error ? <p className="notice error">{error}</p> : null}

      <section className="admin-dashboard-grid admin-two-column">
        <article className="card admin-panel">
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
                <select className="input" value={selectedBookId} onChange={(event) => setSelectedBookId(event.target.value)}>
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
                <select className="input" value={selectedUserId} onChange={(event) => setSelectedUserId(event.target.value)}>
                  <option value="">{t("admin.selectUserPrompt")}</option>
                  {users.map((user) => (
                    <option key={user.id} value={user.id}>
                      {`${user.username} (${user.role})`}
                    </option>
                  ))}
                </select>
              </label>

              <div className="toolbar">
                <button className="button" type="submit" disabled={granting}>
                  {granting ? t("admin.granting") : t("admin.grantAction")}
                </button>
              </div>
            </form>
          ) : (
            <p className="muted">{t("admin.grantsSuperAdminOnly")}</p>
          )}
        </article>

        <article className="card admin-panel">
          <div className="section-header">
            <div>
              <h2>{t("admin.usersTitle")}</h2>
              <p className="muted compact">{t("admin.usersBody")}</p>
            </div>
          </div>
          {isSuperAdmin ? (
            <div className="admin-list">
              {users.map((user) => (
                <div key={user.id} className="admin-list-row">
                  <div>
                    <strong>{user.username}</strong>
                    <p className="muted compact">{user.role}</p>
                  </div>
                  <span className="reader-meta-pill">{user.enabled ? t("common.enabled") : t("common.disabled")}</span>
                </div>
              ))}
            </div>
          ) : (
            <p className="muted">{t("admin.usersSuperAdminOnly")}</p>
          )}
        </article>
      </section>

      <article className="card admin-panel">
        <div className="section-header">
          <div>
            <h2>{t("admin.booksTitle")}</h2>
            <p className="muted compact">{t("admin.booksBody")}</p>
          </div>
        </div>
        <div className="admin-table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>ID</th>
                <th>{t("admin.tableBookTitle")}</th>
                <th>{t("admin.tableBookAuthor")}</th>
                <th>{t("admin.tableBookFormat")}</th>
                <th>{t("admin.tableBookSourceType")}</th>
              </tr>
            </thead>
            <tbody>
              {books.map((book) => (
                <tr key={book.id}>
                  <td>{book.id}</td>
                  <td>{book.title}</td>
                  <td>{book.author ?? t("common.notAvailable")}</td>
                  <td>{`${book.format} / ${book.pluginId}`}</td>
                  <td>{book.sourceType}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </article>
    </AdminShell>
  );
}
