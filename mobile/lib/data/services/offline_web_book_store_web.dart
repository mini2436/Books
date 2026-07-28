import 'package:idb_shim/idb_browser.dart';

class WebOfflineBookStore {
  static const _databaseName = 'private_reader_offline_library';
  static const _booksStore = 'offline_books';
  static const _chaptersStore = 'offline_chapters';
  static const _resourcesStore = 'offline_resources';

  Future<Database> get _database async {
    _databaseFuture ??= idbFactoryBrowser.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = event.database;
        if (!database.objectStoreNames.contains(_booksStore)) {
          database.createObjectStore(_booksStore, keyPath: 'key');
        }
        if (!database.objectStoreNames.contains(_chaptersStore)) {
          database.createObjectStore(_chaptersStore, keyPath: 'key');
        }
        if (!database.objectStoreNames.contains(_resourcesStore)) {
          database.createObjectStore(_resourcesStore, keyPath: 'key');
        }
      },
    );
    return _databaseFuture!;
  }

  Future<Database>? _databaseFuture;

  Future<void> close() async {
    final database = await _databaseFuture;
    database?.close();
    _databaseFuture = null;
  }

  Future<List<Map<String, Object?>>> listBooks({
    String? serverKey,
    int? userId,
  }) async {
    final rows = await _allRows(_booksStore);
    return rows.where((row) {
      if (serverKey != null && row['server_key'] != serverKey) return false;
      if (userId != null && row['user_id'] != userId) return false;
      return true;
    }).toList();
  }

  Future<Map<String, Object?>?> getBook(
    String serverKey,
    int userId,
    int bookId,
  ) => _get(_booksStore, _bookKey(serverKey, userId, bookId));

  Future<void> putBook(Map<String, Object?> row) {
    final copy = Map<String, Object?>.from(row);
    copy['key'] = _bookKey(
      copy['server_key']! as String,
      copy['user_id']! as int,
      copy['book_id']! as int,
    );
    return _put(_booksStore, copy);
  }

  Future<void> updateBook(
    String serverKey,
    int userId,
    int bookId,
    Map<String, Object?> values,
  ) async {
    final row = await getBook(serverKey, userId, bookId);
    if (row == null) return;
    await putBook({...row, ...values});
  }

  Future<void> deleteBook(String serverKey, int userId, int bookId) async {
    final bookKey = _bookKey(serverKey, userId, bookId);
    final database = await _database;
    final transaction = database.transaction([
      _booksStore,
      _chaptersStore,
      _resourcesStore,
    ], idbModeReadWrite);
    await transaction.objectStore(_booksStore).delete(bookKey);
    await _deleteRowsForBook(transaction.objectStore(_chaptersStore), bookKey);
    await _deleteRowsForBook(transaction.objectStore(_resourcesStore), bookKey);
    await transaction.completed;
  }

  Future<void> putChapter(Map<String, Object?> row) {
    final copy = Map<String, Object?>.from(row);
    final bookKey = _bookKey(
      copy['server_key']! as String,
      copy['user_id']! as int,
      copy['book_id']! as int,
    );
    copy['book_key'] = bookKey;
    copy['key'] = '$bookKey\u0000${copy['chapter_index']}';
    return _put(_chaptersStore, copy);
  }

  Future<Map<String, Object?>?> getChapter(
    String serverKey,
    int userId,
    int bookId,
    int chapterIndex,
  ) => _get(
    _chaptersStore,
    '${_bookKey(serverKey, userId, bookId)}\u0000$chapterIndex',
  );

  Future<void> putResource(Map<String, Object?> row) {
    final copy = Map<String, Object?>.from(row);
    final bookKey = _bookKey(
      copy['server_key']! as String,
      copy['user_id']! as int,
      copy['book_id']! as int,
    );
    copy['book_key'] = bookKey;
    copy['key'] = '$bookKey\u0000${copy['resource_id']}';
    return _put(_resourcesStore, copy);
  }

  Future<Map<String, Object?>?> getResource(
    String serverKey,
    int userId,
    int bookId,
    String resourceId,
  ) => _get(
    _resourcesStore,
    '${_bookKey(serverKey, userId, bookId)}\u0000$resourceId',
  );

  Future<List<Map<String, Object?>>> _allRows(String storeName) async {
    final transaction = (await _database).transaction(
      storeName,
      idbModeReadOnly,
    );
    final values = await transaction.objectStore(storeName).getAll();
    await transaction.completed;
    return values
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .toList();
  }

  Future<Map<String, Object?>?> _get(String storeName, String key) async {
    final transaction = (await _database).transaction(
      storeName,
      idbModeReadOnly,
    );
    final value = await transaction.objectStore(storeName).getObject(key);
    await transaction.completed;
    return value is Map ? Map<String, Object?>.from(value) : null;
  }

  Future<void> _put(String storeName, Map<String, Object?> row) async {
    final transaction = (await _database).transaction(
      storeName,
      idbModeReadWrite,
    );
    await transaction.objectStore(storeName).put(row);
    await transaction.completed;
  }

  Future<void> _deleteRowsForBook(ObjectStore store, String bookKey) async {
    final rows = await store.getAll();
    for (final value in rows.whereType<Map>()) {
      if (value['book_key'] == bookKey) {
        await store.delete(value['key']);
      }
    }
  }

  String _bookKey(String serverKey, int userId, int bookId) =>
      '${Uri.encodeComponent(serverKey)}\u0000$userId\u0000$bookId';
}
