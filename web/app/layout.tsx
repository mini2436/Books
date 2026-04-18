import "./globals.css";
import type { Metadata } from "next";
import { AppShell } from "../components/app-shell";
import { I18nProvider } from "../lib/i18n";

export const metadata: Metadata = {
  title: "Private Reader",
  description: "Self-hosted multi-user reading platform",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>
        <I18nProvider>
          <AppShell>{children}</AppShell>
        </I18nProvider>
      </body>
    </html>
  );
}
