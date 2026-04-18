"use client";

import type { ReactNode } from "react";
import { LanguageSwitcher } from "./language-switcher";

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <>
      <header className="topbar">
        <div className="topbar-inner">
          <div className="topbar-brand">Private Reader</div>
          <LanguageSwitcher />
        </div>
      </header>
      {children}
    </>
  );
}

