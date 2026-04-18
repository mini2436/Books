const DB_NAME = "private-reader-sync";
const STORE_NAME = "pending-ops";

type PendingOperation = {
  id: string;
  entityType: "annotation" | "bookmark" | "progress";
  payload: unknown;
  createdAt: string;
};

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

