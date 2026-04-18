export type BookSummary = {
  id: number;
  title: string;
  format: string;
  pluginId: string;
  sourceMissing: boolean;
};

export type PluginSummary = {
  pluginId: string;
  displayName: string;
  supportedExtensions: string[];
  capabilities: string[];
};

export class ApiClient {
  constructor(private readonly baseUrl: string) {}

  private async request<T>(path: string): Promise<T> {
    const response = await fetch(`${this.baseUrl}${path}`, {
      headers: {
        "Content-Type": "application/json",
      },
      cache: "no-store",
    });

    if (!response.ok) {
      throw new Error(`Request failed: ${response.status}`);
    }

    return (await response.json()) as T;
  }

  async listMyBooks(): Promise<BookSummary[]> {
    return this.request<BookSummary[]>("/api/me/books");
  }

  async listPlugins(): Promise<PluginSummary[]> {
    return this.request<PluginSummary[]>("/api/admin/plugins");
  }
}

