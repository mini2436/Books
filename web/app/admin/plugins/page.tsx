"use client";

import { useEffect, useState } from "react";
import { AdminShell } from "../../../components/admin-shell";
import { ApiClient, type PluginSummary } from "../../../lib/api";
import { useAuth } from "../../../lib/auth";
import { useI18n } from "../../../lib/i18n";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

export default function AdminPluginsPage() {
  const { t } = useI18n();
  const { session } = useAuth();
  const [plugins, setPlugins] = useState<PluginSummary[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!session) {
      setPlugins([]);
      setError(null);
      return;
    }

    let cancelled = false;

    async function loadPlugins() {
      try {
        const nextPlugins = await api.listPlugins();
        if (!cancelled) {
          setPlugins(nextPlugins);
        }
      } catch (reason) {
        if (!cancelled) {
          setError(reason instanceof Error ? reason.message : t("admin.loadPluginsFailed"));
        }
      }
    }

    void loadPlugins();
    return () => {
      cancelled = true;
    };
  }, [session, t]);

  return (
    <AdminShell title={t("admin.nav.plugins.title")} subtitle={t("admin.pluginsPageBody")}>
      {error ? <p className="notice error">{error}</p> : null}
      <article className="card admin-panel">
        <div className="section-header">
          <div>
            <h2>{t("admin.pluginsTitle")}</h2>
            <p className="muted compact">{t("admin.pluginsBody")}</p>
          </div>
        </div>
        <div className="admin-table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>{t("admin.tablePlugin")}</th>
                <th>{t("admin.tableExtensions")}</th>
                <th>{t("admin.tableCapabilities")}</th>
              </tr>
            </thead>
            <tbody>
              {plugins.map((plugin) => (
                <tr key={plugin.pluginId}>
                  <td>{plugin.displayName}</td>
                  <td>{plugin.supportedExtensions.join(", ")}</td>
                  <td>{plugin.capabilities.join(", ")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </article>
    </AdminShell>
  );
}
