"use client";

import { useEffect, useState } from "react";
import { ApiClient, type PluginSummary } from "../../lib/api";

const api = new ApiClient(process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080");

export default function AdminPage() {
  const [plugins, setPlugins] = useState<PluginSummary[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .listPlugins()
      .then(setPlugins)
      .catch((reason) => setError(reason instanceof Error ? reason.message : "Failed to load plugins"));
  }, []);

  return (
    <main className="grid">
      <section className="hero">
        <h1>Admin Console</h1>
        <p className="muted">
          Manage library sources, upload books, assign permissions, and inspect
          the compile-time plugin registry.
        </p>
      </section>

      <section className="card">
        <h2>Scanner Plugins</h2>
        {error ? <p>{error}</p> : null}
        <table className="table">
          <thead>
            <tr>
              <th>Plugin</th>
              <th>Extensions</th>
              <th>Capabilities</th>
            </tr>
          </thead>
          <tbody>
            {plugins.length === 0 ? (
              <tr>
                <td colSpan={3}>No plugins loaded.</td>
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

