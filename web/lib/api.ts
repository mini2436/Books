import { getStoredSession } from "./auth-storage";

export type BookSummary = {
  id: number;
  title: string;
  format: string;
  pluginId: string;
  sourceMissing: boolean;
};

export type ManifestTocItem = {
  title: string;
  href: string;
};

export type ReadingManifest = {
  format: string;
  toc: ManifestTocItem[];
  primaryLocation: string;
};

export type PluginSummary = {
  pluginId: string;
  displayName: string;
  supportedExtensions: string[];
  capabilities: string[];
};

export type AdminBookSummary = {
  id: number;
  title: string;
  author: string | null;
  description: string | null;
  pluginId: string;
  format: string;
  sourceType: string;
  sourceMissing: boolean;
  updatedAt: string;
};

export type BookDetail = {
  id: number;
  title: string;
  author: string | null;
  description: string | null;
  pluginId: string;
  format: string;
  sourceType: string;
  manifest: ReadingManifest | null;
  capabilities: string[];
  sourceMissing: boolean;
};

export type LibrarySource = {
  id: number;
  name: string;
  rootPath: string;
  enabled: boolean;
  lastScanAt: string | null;
};

export type ImportJob = {
  id: number;
  bookId: number;
  sourceId: number | null;
  fileId: number;
  status: string;
  message: string | null;
  createdAt: string;
  updatedAt: string;
};

export type UserSummary = {
  id: number;
  username: string;
  role: string;
  enabled: boolean;
};

export type AnnotationView = {
  id: number;
  bookId: number;
  quoteText: string | null;
  noteText: string | null;
  color: string | null;
  anchor: string;
  version: number;
  deleted: boolean;
  updatedAt: string;
};

export type BookmarkView = {
  id: number;
  bookId: number;
  location: string;
  label: string | null;
  deleted: boolean;
  updatedAt: string;
};

export type ReadingProgressView = {
  bookId: number;
  location: string;
  progressPercent: number;
  updatedAt: string;
};

export type AnnotationMutation = {
  clientTempId?: string;
  annotationId?: number;
  bookId: number;
  action: "CREATE" | "UPDATE" | "DELETE";
  quoteText?: string | null;
  noteText?: string | null;
  color?: string | null;
  anchor: string;
  baseVersion?: number;
  updatedAt: string;
};

export type BookmarkMutation = {
  bookmarkId?: number;
  bookId: number;
  action: "CREATE" | "UPDATE" | "DELETE";
  location: string;
  label?: string | null;
  updatedAt: string;
};

export type ReadingProgressMutation = {
  bookId: number;
  location: string;
  progressPercent: number;
  updatedAt: string;
};

export type SyncPushRequest = {
  annotations?: AnnotationMutation[];
  bookmarks?: BookmarkMutation[];
  progresses?: ReadingProgressMutation[];
};

export type SyncPushResponse = {
  annotationMappings: Record<string, number>;
  conflicts: Array<{
    entityType: string;
    entityId: number;
    message: string;
    serverAnnotation?: AnnotationView | null;
  }>;
};

export type SyncPullResponse = {
  cursor: number;
  annotations: AnnotationView[];
  bookmarks: BookmarkView[];
  progresses: ReadingProgressView[];
};

export type SourceScanSummary = {
  sourceId: number;
  imported: number;
  missingMarked: number;
};

export type CreateLibrarySourceInput = {
  name: string;
  rootPath: string;
  enabled: boolean;
};

async function readErrorMessage(response: Response): Promise<string> {
  const contentType = response.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    const payload = (await response.json()) as { error?: string; message?: string };
    return payload.error ?? payload.message ?? `Request failed: ${response.status}`;
  }

  const text = (await response.text()).trim();
  return text || `Request failed: ${response.status}`;
}

export class ApiClient {
  constructor(private readonly baseUrl: string) {}

  private async requestResponse(path: string, init: RequestInit = {}): Promise<Response> {
    const session = getStoredSession();
    const headers = new Headers(init.headers);

    if (session) {
      headers.set("Authorization", `Bearer ${session.accessToken}`);
    }

    if (init.body && !(init.body instanceof FormData) && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }

    const response = await fetch(`${this.baseUrl}${path}`, {
      ...init,
      headers,
      cache: "no-store",
    });

    if (!response.ok) {
      throw new Error(await readErrorMessage(response));
    }

    return response;
  }

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await this.requestResponse(path, init);
    return (await response.json()) as T;
  }

  async listMyBooks(): Promise<BookSummary[]> {
    return this.request<BookSummary[]>("/api/me/books");
  }

  async getMyBook(bookId: number): Promise<BookDetail> {
    return this.request<BookDetail>(`/api/me/books/${bookId}`);
  }

  async downloadMyBookFile(bookId: number): Promise<Blob> {
    const response = await this.requestResponse(`/api/me/books/${bookId}/file`);
    return response.blob();
  }

  async downloadMyBookCover(bookId: number): Promise<Blob | null> {
    const session = getStoredSession();
    const headers = new Headers();
    if (session) {
      headers.set("Authorization", `Bearer ${session.accessToken}`);
    }

    const response = await fetch(`${this.baseUrl}/api/me/books/${bookId}/cover`, {
      headers,
      cache: "no-store",
    });

    if (response.status === 204 || response.status === 404) {
      return null;
    }

    if (!response.ok) {
      throw new Error(await readErrorMessage(response));
    }

    return response.blob();
  }

  async listPlugins(): Promise<PluginSummary[]> {
    return this.request<PluginSummary[]>("/api/admin/plugins");
  }

  async listAdminBooks(): Promise<AdminBookSummary[]> {
    return this.request<AdminBookSummary[]>("/api/admin/books");
  }

  async uploadBook(file: File): Promise<BookDetail> {
    const formData = new FormData();
    formData.set("file", file);
    return this.request<BookDetail>("/api/admin/books/upload", {
      method: "POST",
      body: formData,
    });
  }

  async listImportJobs(): Promise<ImportJob[]> {
    return this.request<ImportJob[]>("/api/admin/books/import-jobs");
  }

  async listLibrarySources(): Promise<LibrarySource[]> {
    return this.request<LibrarySource[]>("/api/admin/library-sources");
  }

  async createLibrarySource(input: CreateLibrarySourceInput): Promise<LibrarySource> {
    return this.request<LibrarySource>("/api/admin/library-sources", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  async rescanLibrarySource(sourceId: number): Promise<SourceScanSummary> {
    return this.request<SourceScanSummary>(`/api/admin/library-sources/${sourceId}/rescan`, {
      method: "POST",
    });
  }

  async listUsers(): Promise<UserSummary[]> {
    return this.request<UserSummary[]>("/api/admin/users");
  }

  async grantBook(bookId: number, userId: number): Promise<{ success: boolean }> {
    return this.request<{ success: boolean }>(`/api/admin/books/${bookId}/grants`, {
      method: "POST",
      body: JSON.stringify({ userId }),
    });
  }

  async listAnnotations(bookId: number): Promise<AnnotationView[]> {
    return this.request<AnnotationView[]>(`/api/me/books/${bookId}/annotations`);
  }

  async listBookmarks(bookId: number): Promise<BookmarkView[]> {
    return this.request<BookmarkView[]>(`/api/me/books/${bookId}/bookmarks`);
  }

  async putProgress(bookId: number, input: ReadingProgressMutation): Promise<ReadingProgressView> {
    return this.request<ReadingProgressView>(`/api/me/books/${bookId}/progress`, {
      method: "PUT",
      body: JSON.stringify(input),
    });
  }

  async pullSync(cursor?: number): Promise<SyncPullResponse> {
    const suffix = typeof cursor === "number" ? `?cursor=${cursor}` : "";
    return this.request<SyncPullResponse>(`/api/me/sync/pull${suffix}`);
  }

  async pushSync(input: SyncPushRequest): Promise<SyncPushResponse> {
    return this.request<SyncPushResponse>("/api/me/sync/push", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }
}
