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
      loading: "加载中",
      enabled: "启用",
      disabled: "禁用",
      notAvailable: "暂无",
    },
    auth: {
      title: "登录",
      subtitle: "使用你的账号换取 access token，之后前端会自动为受保护接口附带 Bearer 认证头。",
      username: "用户名",
      password: "密码",
      signIn: "登录",
      signingIn: "登录中",
      signOut: "退出登录",
      openLogin: "前往登录",
      backHome: "返回首页",
      alreadySignedIn: "已登录",
      continueToApp: "继续进入",
      loggedInAs: "当前用户",
      role: "角色",
      loginFailed: "登录失败",
      loginRequired: "需要先登录",
      readerLoginHint: "阅读端会请求你的书架接口，登录后才会携带 access token。",
      adminLoginHint: "管理台接口要求管理员或馆员角色，登录后才会携带 access token。",
      roleRestrictedTitle: "当前账号无管理权限",
      roleRestrictedBody: "这个页面仅允许 SUPER_ADMIN 或 LIBRARIAN 访问。",
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
      subtitle: "这个页面现在提供 Web 阅读器、书架选择和基础格式预览能力。",
      queueSize: "离线同步队列数量",
      bookshelf: "书架",
      bookshelfBody: "从左侧选择一本已授权的书，右侧会加载对应的在线阅读器。",
      noBooks: "当前还没有可阅读的书籍。",
      statusMissing: "源文件缺失",
      statusReady: "可阅读",
      loadBooksFailed: "加载书架失败",
      loadBookFailed: "加载书籍内容失败",
      refreshShelf: "刷新书架",
      refreshingShelf: "刷新中",
      activeBook: "当前阅读",
      selectBookPrompt: "先从左侧书架选择一本书开始阅读。",
      readerPanelTitle: "在线阅读器",
      tocTitle: "目录",
      noToc: "当前没有可用目录。",
      openSource: "打开原文件",
      downloadCopy: "下载副本",
      descriptionFallback: "当前没有书籍简介。",
      metaFormat: "格式",
      metaPlugin: "插件",
      metaSource: "来源",
      metaCapabilities: "能力",
      loadingBook: "正在加载书籍内容...",
      readerTextEmpty: "当前文本内容为空。",
      readerUnavailable: "当前格式暂时无法直接嵌入浏览器，请先打开原文件或下载副本。",
      pdfHint: "PDF 会使用浏览器内置预览器显示。",
      epubHint: "EPUB 会在页面内渲染，首次打开可能稍慢。",
      textHint: "TXT 会以正文模式直接展示。",
      bookMissingBody: "这本书的源文件已经缺失，请联系管理员修复源目录或重新上传。",
    },
    admin: {
      title: "管理台",
      subtitle: "在这里管理扫描源、导入任务、授权策略和编译期插件注册表。",
      summaryPlugins: "插件",
      summarySources: "扫描源",
      summaryJobs: "导入任务",
      refreshData: "刷新数据",
      refreshing: "刷新中",
      uploadTitle: "手动上传书籍",
      uploadBody: "直接从浏览器上传 EPUB、PDF 或 TXT 文件，后端会按插件自动识别并导入。",
      uploadField: "书籍文件",
      uploadAction: "上传并导入",
      uploading: "上传中",
      uploadSuccess: "书籍已导入",
      uploadFailed: "上传书籍失败",
      selectFileFirst: "请先选择一个书籍文件。",
      selectGrantTargets: "请先选择要授权的书籍和用户。",
      lastUploaded: "最近一次上传结果",
      uploadedFormat: "格式",
      uploadedPlugin: "插件",
      uploadedSource: "来源",
      uploadedCapabilities: "能力",
      grantsTitle: "书籍授权",
      grantsBody: "把某本书授权给已有用户，授权后对方会在自己的书架里看到这本书。",
      grantBookField: "选择书籍",
      grantUserField: "选择用户",
      selectBookPrompt: "请选择一本书",
      selectUserPrompt: "请选择一个用户",
      grantAction: "执行授权",
      granting: "授权中",
      grantSuccess: "授权成功",
      grantFailed: "书籍授权失败",
      grantsSuperAdminOnly: "当前 Web 管理台只对超级管理员开放用户选择与授权入口。",
      usersTitle: "用户列表",
      usersBody: "列出当前启用用户，方便确认授权目标。",
      usersSuperAdminOnly: "只有超级管理员可以查看当前用户列表。",
      tableUserName: "用户名",
      tableUserRole: "角色",
      tableUserEnabled: "状态",
      noUsers: "当前没有可授权的启用用户。",
      booksTitle: "书籍目录",
      booksBody: "列出当前系统中的书籍，方便选择授权目标和核对导入结果。",
      tableBookTitle: "书名",
      tableBookAuthor: "作者",
      tableBookFormat: "格式 / 插件",
      tableBookSourceType: "来源类型",
      tableBookUpdatedAt: "更新时间",
      noBooks: "当前还没有任何已导入书籍。",
      sourcesTitle: "创建扫描源",
      sourcesBody: "配置一个本地/NAS 目录，让后端定时扫描并自动导入其中的新文件。",
      sourceName: "扫描源名称",
      sourceRootPath: "根目录路径",
      sourceEnabled: "创建后立即启用",
      createSource: "创建扫描源",
      creatingSource: "创建中",
      sourceCreated: "扫描源已创建",
      createSourceFailed: "创建扫描源失败",
      sourcesListTitle: "扫描源列表",
      sourcesListBody: "可以手动触发重扫，导入新文件，并把已消失的文件标记为缺失。",
      tableSourceName: "名称",
      tableSourcePath: "路径",
      tableSourceEnabled: "状态",
      tableSourceLastScan: "最近扫描",
      tableActions: "操作",
      noSources: "当前还没有配置扫描源。",
      neverScanned: "尚未扫描",
      rescanAction: "立即重扫",
      rescanning: "重扫中",
      rescanSuccess: "扫描完成",
      rescanFailed: "执行重扫失败",
      rescanImported: "新导入",
      rescanMissing: "标记缺失",
      importJobsTitle: "导入任务",
      importJobsBody: "展示最近 100 条导入记录，便于确认上传或扫描是否已经完成。",
      noImportJobs: "当前还没有导入任务。",
      tableJobBookId: "书籍 ID",
      tableJobSourceId: "来源 ID",
      tableJobStatus: "状态",
      tableJobMessage: "消息",
      tableJobCreatedAt: "创建时间",
      pluginsTitle: "扫描插件",
      pluginsBody: "展示当前编译期内置的格式插件和它们支持的能力。",
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
      loading: "Loading",
      enabled: "Enabled",
      disabled: "Disabled",
      notAvailable: "N/A",
    },
    auth: {
      title: "Sign In",
      subtitle:
        "Use your account to obtain an access token. The web app will attach the Bearer token to protected API calls automatically.",
      username: "Username",
      password: "Password",
      signIn: "Sign In",
      signingIn: "Signing In",
      signOut: "Sign Out",
      openLogin: "Open Login",
      backHome: "Back Home",
      alreadySignedIn: "You are already signed in",
      continueToApp: "Continue",
      loggedInAs: "Signed in as",
      role: "Role",
      loginFailed: "Sign-in failed",
      loginRequired: "Please sign in first",
      readerLoginHint: "The reader page calls your bookshelf API, so it needs an access token first.",
      adminLoginHint: "Admin APIs require an administrator or librarian account with a valid access token.",
      roleRestrictedTitle: "This account cannot access the admin console",
      roleRestrictedBody: "Only SUPER_ADMIN and LIBRARIAN roles can open this page.",
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
      subtitle: "This page now includes a web reader, bookshelf picker, and basic in-browser previews.",
      queueSize: "Offline sync queue size",
      bookshelf: "Bookshelf",
      bookshelfBody: "Pick a granted book on the left and the matching web reader will load on the right.",
      noBooks: "No books are available yet.",
      statusMissing: "Source missing",
      statusReady: "Ready",
      loadBooksFailed: "Failed to load books",
      loadBookFailed: "Failed to load the selected book",
      refreshShelf: "Refresh Shelf",
      refreshingShelf: "Refreshing",
      activeBook: "Now reading",
      selectBookPrompt: "Choose a book from the bookshelf to start reading.",
      readerPanelTitle: "Online Reader",
      tocTitle: "Table of Contents",
      noToc: "No table of contents is available for this book yet.",
      openSource: "Open Source File",
      downloadCopy: "Download Copy",
      descriptionFallback: "No description is available for this book.",
      metaFormat: "Format",
      metaPlugin: "Plugin",
      metaSource: "Source",
      metaCapabilities: "Capabilities",
      loadingBook: "Loading book content...",
      readerTextEmpty: "This text file is empty.",
      readerUnavailable: "This format cannot be embedded directly right now. Open the raw file or download it instead.",
      pdfHint: "PDF uses the browser's built-in previewer.",
      epubHint: "EPUB renders inside the page and may take a moment on first load.",
      textHint: "TXT is rendered directly as readable text.",
      bookMissingBody: "The source file for this book is missing. Ask an administrator to restore the source or upload it again.",
    },
    admin: {
      title: "Admin Console",
      subtitle:
        "Manage scan sources, import jobs, permissions, and the compile-time plugin registry here.",
      summaryPlugins: "Plugins",
      summarySources: "Sources",
      summaryJobs: "Jobs",
      refreshData: "Refresh Data",
      refreshing: "Refreshing",
      uploadTitle: "Manual Upload",
      uploadBody:
        "Upload EPUB, PDF, or TXT files directly from the browser. The backend will detect the right plugin and import them automatically.",
      uploadField: "Book File",
      uploadAction: "Upload and Import",
      uploading: "Uploading",
      uploadSuccess: "Book imported",
      uploadFailed: "Failed to upload the book",
      selectFileFirst: "Please choose a book file first.",
      selectGrantTargets: "Please choose both a book and a user first.",
      lastUploaded: "Latest upload result",
      uploadedFormat: "Format",
      uploadedPlugin: "Plugin",
      uploadedSource: "Source",
      uploadedCapabilities: "Capabilities",
      grantsTitle: "Book Grants",
      grantsBody: "Grant a book to an existing user so it appears in their personal bookshelf.",
      grantBookField: "Select Book",
      grantUserField: "Select User",
      selectBookPrompt: "Choose a book",
      selectUserPrompt: "Choose a user",
      grantAction: "Grant Access",
      granting: "Granting",
      grantSuccess: "Grant succeeded",
      grantFailed: "Failed to grant the book",
      grantsSuperAdminOnly: "The current web console exposes the user picker and grant workflow to super admins only.",
      usersTitle: "Users",
      usersBody: "Lists active users so you can verify the grant target.",
      usersSuperAdminOnly: "Only super admins can view the user list here.",
      tableUserName: "Username",
      tableUserRole: "Role",
      tableUserEnabled: "Status",
      noUsers: "There are no active users to grant books to.",
      booksTitle: "Books",
      booksBody: "Lists imported books so you can pick the right grant target and verify import results.",
      tableBookTitle: "Title",
      tableBookAuthor: "Author",
      tableBookFormat: "Format / Plugin",
      tableBookSourceType: "Source Type",
      tableBookUpdatedAt: "Updated At",
      noBooks: "No books have been imported yet.",
      sourcesTitle: "Create Scan Source",
      sourcesBody:
        "Configure a local or NAS folder so the backend can scan it on a schedule and import newly discovered files.",
      sourceName: "Source Name",
      sourceRootPath: "Root Path",
      sourceEnabled: "Enable immediately",
      createSource: "Create Source",
      creatingSource: "Creating",
      sourceCreated: "Scan source created",
      createSourceFailed: "Failed to create the scan source",
      sourcesListTitle: "Scan Sources",
      sourcesListBody:
        "Trigger rescans manually to import new files and mark missing ones when they disappear from disk.",
      tableSourceName: "Name",
      tableSourcePath: "Path",
      tableSourceEnabled: "Status",
      tableSourceLastScan: "Last Scan",
      tableActions: "Actions",
      noSources: "No scan sources are configured yet.",
      neverScanned: "Never scanned",
      rescanAction: "Rescan Now",
      rescanning: "Rescanning",
      rescanSuccess: "Rescan finished",
      rescanFailed: "Failed to rescan the source",
      rescanImported: "Imported",
      rescanMissing: "Marked missing",
      importJobsTitle: "Import Jobs",
      importJobsBody:
        "Shows the latest 100 import records so you can confirm whether uploads and rescans already finished.",
      noImportJobs: "No import jobs yet.",
      tableJobBookId: "Book ID",
      tableJobSourceId: "Source ID",
      tableJobStatus: "Status",
      tableJobMessage: "Message",
      tableJobCreatedAt: "Created At",
      pluginsTitle: "Scanner Plugins",
      pluginsBody: "Shows the built-in compile-time plugins and the capabilities each one exposes.",
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
