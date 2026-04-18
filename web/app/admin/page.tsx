"use client";

import { useEffect, useState } from "react";
import { ApiClient, type PluginSummary } from "../../lib/api";
import { useI18n } from "../../lib/i18n";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

export default function AdminPage() {
  const { t } = useI18n();
  const [plugins, setPlugins] = useState<PluginSummary[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .listPlugins()
      .then(setPlugins)
      .catch((reason) => setError(reason instanceof Error ? reason.message : t("admin.loadPluginsFailed")));
  }, [t]);

  return (
    <main className="grid">
      <section className="hero">
        <h1>{t("admin.title")}</h1>
        <p className="muted">{t("admin.subtitle")}</p>
      </section>

      <section className="card">
        <h2>{t("admin.pluginsTitle")}</h2>
        {error ? <p>{error}</p> : null}
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
