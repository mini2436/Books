import type { AnnotationMutation, BookmarkMutation, ReadingProgressMutation, SyncPushRequest } from "./api";

const DB_NAME = "private-reader-sync";
const STORE_NAME = "pending-ops";

type PendingOperation = {
  id: string;
  entityType: "annotation" | "bookmark" | "progress";
  payload: unknown;
  createdAt: string;
};

type SyncApi = {
  pushSync: (input: SyncPushRequest) => Promise<unknown>;
};

let flushInFlight: Promise<{ flushed: number }> | null = null;

function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(STORE_NAME)) {
        database.createObjectStore(STORE_NAME, { keyPath: "id" });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function enqueueOfflineOperation(operation: PendingOperation): Promise<void> {
  const database = await openDatabase();
  await new Promise<void>((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readwrite");
    transaction.objectStore(STORE_NAME).put(operation);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
  });
}

export async function loadOfflineQueueStats(): Promise<{ pending: number }> {
  if (typeof indexedDB === "undefined") {
    return { pending: 0 };
  }
  const database = await openDatabase();
  return new Promise<{ pending: number }>((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readonly");
    const request = transaction.objectStore(STORE_NAME).count();
    request.onsuccess = () => resolve({ pending: request.result });
    request.onerror = () => reject(request.error);
  });
}

async function readPendingOperations(): Promise<PendingOperation[]> {
  if (typeof indexedDB === "undefined") {
    return [];
  }

  const database = await openDatabase();
  return new Promise<PendingOperation[]>((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readonly");
    const request = transaction.objectStore(STORE_NAME).getAll();
    request.onsuccess = () => resolve((request.result as PendingOperation[]).sort((a, b) => a.createdAt.localeCompare(b.createdAt)));
    request.onerror = () => reject(request.error);
  });
}

async function deletePendingOperations(ids: string[]): Promise<void> {
  if (typeof indexedDB === "undefined" || ids.length === 0) {
    return;
  }

  const database = await openDatabase();
  await new Promise<void>((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readwrite");
    const store = transaction.objectStore(STORE_NAME);
    ids.forEach((id) => store.delete(id));
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
  });
}

function compactPendingOperations(operations: PendingOperation[]): SyncPushRequest {
  const annotations: AnnotationMutation[] = [];
  const bookmarks: BookmarkMutation[] = [];
  const latestProgressByBook = new Map<number, ReadingProgressMutation>();

  operations.forEach((operation) => {
    if (operation.entityType === "annotation") {
      annotations.push(operation.payload as AnnotationMutation);
      return;
    }

    if (operation.entityType === "bookmark") {
      bookmarks.push(operation.payload as BookmarkMutation);
      return;
    }

    const progress = operation.payload as ReadingProgressMutation;
    latestProgressByBook.set(progress.bookId, progress);
  });

  return {
    annotations,
    bookmarks,
    progresses: Array.from(latestProgressByBook.values()),
  };
}

async function flushPendingOperationsInternal(api: SyncApi): Promise<{ flushed: number }> {
  const operations = await readPendingOperations();
  if (operations.length === 0) {
    return { flushed: 0 };
  }

  const request = compactPendingOperations(operations);
  const hasPayload =
    (request.annotations?.length ?? 0) > 0 ||
    (request.bookmarks?.length ?? 0) > 0 ||
    (request.progresses?.length ?? 0) > 0;

  if (!hasPayload) {
    await deletePendingOperations(operations.map((operation) => operation.id));
    return { flushed: 0 };
  }

  await api.pushSync(request);
  await deletePendingOperations(operations.map((operation) => operation.id));
  return { flushed: operations.length };
}

export async function flushPendingOperations(api: SyncApi): Promise<{ flushed: number }> {
  if (flushInFlight) {
    return flushInFlight;
  }

  flushInFlight = flushPendingOperationsInternal(api).finally(() => {
    flushInFlight = null;
  });
  return flushInFlight;
}
