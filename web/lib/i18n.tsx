"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type Locale = "zh-CN" | "en";

type TranslationLeaf = string;
type TranslationTree = {
  [key: string]: TranslationLeaf | TranslationTree;
};

type I18nContextValue = {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: (path: string) => string;
};

const STORAGE_KEY = "private-reader-locale";

const translations: Record<Locale, TranslationTree> = {
  "zh-CN": {
    common: {
      language: "语言",
      simplifiedChinese: "简体中文",
      english: "English",
      loadingFailed: "加载失败",
    },
    home: {
      pillNative: "Spring Boot 原生镜像就绪",
      pillSync: "离线同步",
      pillPlugin: "插件扫描器",
      title: "私有阅读器",
      description:
        "一个面向私有部署的多用户阅读平台，支持细粒度访问控制、NAS 扫描与离线批注同步。",
      openReader: "打开阅读端",
      openAdmin: "打开管理台",
      readerExperienceTitle: "阅读体验",
      readerExperienceBody:
        "网页与移动端共用阅读内核，支持本地优先的批注队列与断线恢复同步。",
      adminToolsTitle: "管理工具",
      adminToolsBody:
        "在浏览器中完成书籍上传、授权分配、扫描源配置与导入任务查看。",
      pluginsTitle: "格式插件",
      pluginsBody:
        "内置 EPUB、PDF、TXT 插件，后续新增格式时不需要改写导入核心。",
    },
    reader: {
      title: "阅读端",
      subtitle: "这个页面作为 Web 与 Capacitor 共用的阅读器外壳。",
      queueSize: "离线同步队列数量",
      bookshelf: "书架",
      noBooks: "当前还没有可阅读的书籍。",
      tableTitle: "书名",
      tableFormat: "格式",
      tablePlugin: "插件",
      tableStatus: "状态",
      statusMissing: "源文件缺失",
      statusReady: "可阅读",
      loadBooksFailed: "加载书架失败",
    },
    admin: {
      title: "管理台",
      subtitle: "在这里管理扫描源、导入任务、授权策略和编译期插件注册表。",
      pluginsTitle: "扫描插件",
      noPlugins: "当前没有加载任何插件。",
      tablePlugin: "插件",
      tableExtensions: "扩展名",
      tableCapabilities: "能力",
      loadPluginsFailed: "加载插件列表失败",
    },
  },
  en: {
    common: {
      language: "Language",
      simplifiedChinese: "Simplified Chinese",
      english: "English",
      loadingFailed: "Loading failed",
    },
    home: {
      pillNative: "Spring Boot Native-Ready",
      pillSync: "Offline Sync",
      pillPlugin: "Plugin Scanner",
      title: "Private Reader",
      description:
        "A self-hosted multi-user reading platform with fine-grained access control, NAS scanning, and offline annotation sync.",
      openReader: "Open Reading App",
      openAdmin: "Open Admin Console",
      readerExperienceTitle: "Reader Experience",
      readerExperienceBody:
        "A shared Web/App reader shell with a local-first annotation queue and reconnect-based sync recovery.",
      adminToolsTitle: "Admin Tools",
      adminToolsBody:
        "Upload books, assign permissions, configure scan sources, and inspect import jobs in the browser.",
      pluginsTitle: "Format Plugins",
      pluginsBody:
        "EPUB, PDF, and TXT are built in. New formats can be added without rewriting the import core.",
    },
    reader: {
      title: "Reading App",
      subtitle: "This page is the shared reader shell for Web and Capacitor.",
      queueSize: "Offline sync queue size",
      bookshelf: "Bookshelf",
      noBooks: "No books are available yet.",
      tableTitle: "Title",
      tableFormat: "Format",
      tablePlugin: "Plugin",
      tableStatus: "Status",
      statusMissing: "Source missing",
      statusReady: "Ready",
      loadBooksFailed: "Failed to load books",
    },
    admin: {
      title: "Admin Console",
      subtitle:
        "Manage scan sources, import jobs, permissions, and the compile-time plugin registry here.",
      pluginsTitle: "Scanner Plugins",
      noPlugins: "No plugins are loaded.",
      tablePlugin: "Plugin",
      tableExtensions: "Extensions",
      tableCapabilities: "Capabilities",
      loadPluginsFailed: "Failed to load plugins",
    },
  },
};

const I18nContext = createContext<I18nContextValue | null>(null);

function readTranslation(tree: TranslationTree, path: string): string | undefined {
  const parts = path.split(".");
  let current: TranslationLeaf | TranslationTree | undefined = tree;

  for (const part of parts) {
    if (typeof current === "string") {
      return undefined;
    }
    current = current?.[part];
  }

  return typeof current === "string" ? current : undefined;
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>("zh-CN");

  useEffect(() => {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (stored === "zh-CN" || stored === "en") {
      setLocaleState(stored);
    }
  }, []);

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, locale);
    document.documentElement.lang = locale;
  }, [locale]);

  const value = useMemo<I18nContextValue>(
    () => ({
      locale,
      setLocale: setLocaleState,
      t: (path: string) => readTranslation(translations[locale], path) ?? path,
    }),
    [locale],
  );

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nContextValue {
  const context = useContext(I18nContext);
  if (!context) {
    throw new Error("useI18n must be used inside I18nProvider");
  }
  return context;
}

