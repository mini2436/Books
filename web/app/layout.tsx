import "./globals.css";
import type { Metadata } from "next";
import { AppShell } from "../components/app-shell";
import { AuthProvider } from "../lib/auth";
import { I18nProvider } from "../lib/i18n";

export const metadata: Metadata = {
  title: "Private Reader",
  description: "Self-hosted multi-user reading platform",
  icons: {
    icon: "/icon.svg",
    shortcut: "/favicon.ico",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>
        <AuthProvider>
          <I18nProvider>
            <AppShell>{children}</AppShell>
          </I18nProvider>
        </AuthProvider>
      </body>
    </html>
  );
}
