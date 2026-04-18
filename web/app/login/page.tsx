"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useAuth } from "../../lib/auth";
import { useI18n } from "../../lib/i18n";

type AppRoute = "/" | "/app" | "/admin";

function resolveNextPath(nextPath: string | null): AppRoute {
  if (nextPath === "/" || nextPath === "/app" || nextPath === "/admin") {
    return nextPath;
  }
  return "/app";
}

export default function LoginPage() {
  const { session, login, logout } = useAuth();
  const { t } = useI18n();
  const router = useRouter();
  const [nextPath, setNextPath] = useState<AppRoute>("/app");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const searchParams = new URLSearchParams(window.location.search);
    setNextPath(resolveNextPath(searchParams.get("next")));
  }, []);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      await login({ username, password });
      router.replace(nextPath);
      router.refresh();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("auth.loginFailed"));
    } finally {
      setSubmitting(false);
    }
  }

  if (session) {
    return (
      <main className="grid">
        <section className="card auth-card">
          <h1>{t("auth.alreadySignedIn")}</h1>
          <p className="muted">
            {t("auth.loggedInAs")}: <strong>{session.user.username}</strong>
          </p>
          <p className="muted">
            {t("auth.role")}: <span className="code">{session.user.role}</span>
          </p>
          <div className="toolbar">
            <Link className="button" href={nextPath}>
              {t("auth.continueToApp")}
            </Link>
            <button
              type="button"
              className="button secondary"
              onClick={() => {
                void logout();
              }}
            >
              {t("auth.signOut")}
            </button>
          </div>
        </section>
      </main>
    );
  }

  return (
    <main className="grid">
      <section className="card auth-card">
        <h1>{t("auth.title")}</h1>
        <p className="muted">{t("auth.subtitle")}</p>
        <form className="auth-form" onSubmit={handleSubmit}>
          <label className="field">
            <span>{t("auth.username")}</span>
            <input
              className="input"
              name="username"
              autoComplete="username"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              placeholder="admin"
              required
            />
          </label>
          <label className="field">
            <span>{t("auth.password")}</span>
            <input
              className="input"
              type="password"
              name="password"
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="admin12345"
              required
            />
          </label>
          {error ? <p className="notice error">{error}</p> : null}
          <div className="toolbar">
            <button className="button" type="submit" disabled={submitting}>
              {submitting ? t("auth.signingIn") : t("auth.signIn")}
            </button>
            <Link className="button secondary" href="/">
              {t("auth.backHome")}
            </Link>
          </div>
        </form>
      </section>
    </main>
  );
}
