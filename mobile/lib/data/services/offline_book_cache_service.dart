import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/book_models.dart';
import '../models/sync_models.dart';
import 'offline_web_book_store_stub.dart'
    if (dart.library.js_interop) 'offline_web_book_store_web.dart';

class OfflineCacheIdentity {
  const OfflineCacheIdentity({
    required this.serverKey,
    required this.userId,
    this.bookCount = 0,
    this.lastDownloadedAt = '',
  });

  final String serverKey;
  final int userId;
  final int bookCount;
  final String lastDownloadedAt;
}

class OfflineBookCacheService {
  OfflineBookCacheService({String? databasePathOverride})
    : _databasePathOverride = databasePathOverride;

  final String? _databasePathOverride;
  final WebOfflineBookStore _webStore = WebOfflineBookStore();

  Future<Database> get _database async {
    if (kIsWeb) {
      throw UnsupportedError('Web 端暂不支持离线书库');
    }
    _databaseFuture ??= _open();
    return _databaseFuture!;
  }

  Future<Database>? _databaseFuture;

  @visibleForTesting
  Future<void> close() async {
    if (kIsWeb) {
      await _webStore.close();
      return;
    }
    final database = await _databaseFuture;
    await database?.close();
    _databaseFuture = null;
  }

  Future<OfflineCacheIdentity?> latestCachedIdentity(
    String legacyServerKey,
  ) async {
    final identities = await listCachedIdentities(legacyServerKey);
    return identities.isEmpty ? null : identities.first;
  }

  Future<List<OfflineCacheIdentity>> listCachedIdentities(
    String legacyServerKey,
  ) async {
    if (kIsWeb) {
      final rows = await _webStore.listBooks();
      final grouped = <String, OfflineCacheIdentity>{};
      for (final row in rows) {
        final serverKey = row['server_key']! as String;
        final userId = row['user_id']! as int;
        final downloadedAt = row['downloaded_at']! as String;
        final key = '$serverKey\u0000$userId';
        final current = grouped[key];
        grouped[key] = OfflineCacheIdentity(
          serverKey: serverKey,
          userId: userId,
          bookCount: (current?.bookCount ?? 0) + 1,
          lastDownloadedAt:
              current == null ||
                  downloadedAt.compareTo(current.lastDownloadedAt) > 0
              ? downloadedAt
              : current.lastDownloadedAt,
        );
      }
      final identities = grouped.values.toList()
        ..sort(
          (left, right) =>
              right.lastDownloadedAt.compareTo(left.lastDownloadedAt),
        );
      return identities;
    }
    final db = await _database;
    await _claimLegacyRows(db, legacyServerKey);
    final rows = await db.rawQuery('''
      SELECT
        server_key,
        user_id,
        COUNT(*) AS book_count,
        MAX(downloaded_at) AS last_downloaded_at
      FROM offline_books
      GROUP BY server_key, user_id
      ORDER BY last_downloaded_at DESC
    ''');
    return rows
        .map(
          (row) => OfflineCacheIdentity(
            serverKey: row['server_key']! as String,
            userId: row['user_id']! as int,
            bookCount: (row['book_count']! as num).toInt(),
            lastDownloadedAt: row['last_downloaded_at']! as String,
          ),
        )
        .toList();
  }

  Future<List<BookSummary>> loadCachedBooks(
    String serverKey,
    int userId,
  ) async {
    if (kIsWeb) {
      final rows = await _webStore.listBooks(
        serverKey: serverKey,
        userId: userId,
      );
      rows.sort(
        (left, right) => (right['downloaded_at']! as String).compareTo(
          left['downloaded_at']! as String,
        ),
      );
      return rows
          .map(
            (row) => BookSummary.fromJson(
              jsonDecode(row['summary_json']! as String)
                  as Map<String, dynamic>,
            ),
          )
          .toList();
    }
    final db = await _database;
    await _claimLegacyRows(db, serverKey);
    final rows = await db.query(
      'offline_books',
      columns: ['summary_json'],
      where: 'server_key = ? AND user_id = ?',
      whereArgs: [serverKey, userId],
      orderBy: 'downloaded_at DESC',
    );
    return rows
        .map(
          (row) => BookSummary.fromJson(
            jsonDecode(row['summary_json']! as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<Set<int>> cachedBookIds(String serverKey, int userId) async {
    if (kIsWeb) {
      return (await _webStore.listBooks(
        serverKey: serverKey,
        userId: userId,
      )).map((row) => row['book_id']! as int).toSet();
    }
    final rows = await (await _database).query(
      'offline_books',
      columns: ['book_id'],
      where: 'server_key = ? AND user_id = ?',
      whereArgs: [serverKey, userId],
    );
    return rows.map((row) => row['book_id']! as int).toSet();
  }

  Future<bool> isBookCached(String serverKey, int userId, int bookId) async {
    if (kIsWeb) {
      return await _webStore.getBook(serverKey, userId, bookId) != null;
    }
    final rows = await (await _database).query(
      'offline_books',
      columns: ['book_id'],
      where: 'server_key = ? AND user_id = ? AND book_id = ?',
      whereArgs: [serverKey, userId, bookId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> deleteBook(String serverKey, int userId, int bookId) async {
    if (kIsWeb) {
      await _webStore.deleteBook(serverKey, userId, bookId);
      return;
    }
    final db = await _database;
    await db.transaction((txn) async {
      final args = [serverKey, userId, bookId];
      await txn.delete(
        'offline_resources',
        where: 'server_key = ? AND user_id = ? AND book_id = ?',
        whereArgs: args,
      );
      await txn.delete(
        'offline_chapters',
        where: 'server_key = ? AND user_id = ? AND book_id = ?',
        whereArgs: args,
      );
      await txn.delete(
        'offline_books',
        where: 'server_key = ? AND user_id = ? AND book_id = ?',
        whereArgs: args,
      );
    });
  }

  Future<void> saveChapter(
    String serverKey,
    int userId,
    int bookId,
    BookContentChapter chapter,
  ) async {
    if (kIsWeb) {
      await _webStore.putChapter({
        'server_key': serverKey,
        'user_id': userId,
        'book_id': bookId,
        'chapter_index': chapter.chapterIndex,
        'chapter_json': jsonEncode(chapter.toJson()),
      });
      return;
    }
    await (await _database).insert('offline_chapters', {
      'server_key': serverKey,
      'user_id': userId,
      'book_id': bookId,
      'chapter_index': chapter.chapterIndex,
      'chapter_json': jsonEncode(chapter.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveResource(
    String serverKey,
    int userId,
    int bookId,
    String resourceId,
    Uint8List bytes,
  ) async {
    if (kIsWeb) {
      await _webStore.putResource({
        'server_key': serverKey,
        'user_id': userId,
        'book_id': bookId,
        'resource_id': resourceId,
        'bytes': bytes,
      });
      return;
    }
    await (await _database).insert('offline_resources', {
      'server_key': serverKey,
      'user_id': userId,
      'book_id': bookId,
      'resource_id': resourceId,
      'bytes': bytes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveDownloadedBook({
    required String serverKey,
    required int userId,
    required BookSummary summary,
    required BookDetail detail,
    BookContent? content,
    required List<AnnotationView> annotations,
    required List<BookmarkView> bookmarks,
    ReadingProgressView? progress,
    Uint8List? fileBytes,
    Uint8List? coverBytes,
    required int sizeBytes,
  }) async {
    final row = <String, Object?>{
      'server_key': serverKey,
      'user_id': userId,
      'book_id': summary.id,
      'summary_json': jsonEncode(summary.toJson()),
      'detail_json': jsonEncode(detail.toJson()),
      'content_json': content == null ? null : jsonEncode(content.toJson()),
      'annotations_json': jsonEncode(
        annotations.map((item) => item.toJson()).toList(),
      ),
      'bookmarks_json': jsonEncode(
        bookmarks.map((item) => item.toJson()).toList(),
      ),
      'progress_json': progress == null ? null : jsonEncode(progress.toJson()),
      'file_bytes': fileBytes,
      'cover_bytes': coverBytes,
      'downloaded_at': DateTime.now().toUtc().toIso8601String(),
      'size_bytes': sizeBytes,
    };
    if (kIsWeb) {
      await _webStore.putBook(row);
      return;
    }
    await (await _database).insert(
      'offline_books',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<BookDetail?> loadDetail(
    String serverKey,
    int userId,
    int bookId,
  ) async {
    final value = await _bookValue(serverKey, userId, bookId, 'detail_json');
    return value == null
        ? null
        : BookDetail.fromJson(
            jsonDecode(value as String) as Map<String, dynamic>,
          );
  }

  Future<BookContent?> loadContent(
    String serverKey,
    int userId,
    int bookId,
  ) async {
    final value = await _bookValue(serverKey, userId, bookId, 'content_json');
    return value == null
        ? null
        : BookContent.fromJson(
            jsonDecode(value as String) as Map<String, dynamic>,
          );
  }

  Future<BookContentChapter?> loadChapter(
    String serverKey,
    int userId,
    int bookId,
    int chapterIndex,
  ) async {
    if (kIsWeb) {
      final row = await _webStore.getChapter(
        serverKey,
        userId,
        bookId,
        chapterIndex,
      );
      if (row == null) return null;
      return BookContentChapter.fromJson(
        jsonDecode(row['chapter_json']! as String) as Map<String, dynamic>,
      );
    }
    final rows = await (await _database).query(
      'offline_chapters',
      columns: ['chapter_json'],
      where:
          'server_key = ? AND user_id = ? AND book_id = ? AND chapter_index = ?',
      whereArgs: [serverKey, userId, bookId, chapterIndex],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BookContentChapter.fromJson(
      jsonDecode(rows.first['chapter_json']! as String) as Map<String, dynamic>,
    );
  }

  Future<Uint8List?> loadResource(
    String serverKey,
    int userId,
    int bookId,
    String resourceId,
  ) async {
    if (kIsWeb) {
      return _asBytes(
        (await _webStore.getResource(
          serverKey,
          userId,
          bookId,
          resourceId,
        ))?['bytes'],
      );
    }
    final rows = await (await _database).query(
      'offline_resources',
      columns: ['bytes'],
      where:
          'server_key = ? AND user_id = ? AND book_id = ? AND resource_id = ?',
      whereArgs: [serverKey, userId, bookId, resourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List?;
  }

  Future<Uint8List?> loadFile(String serverKey, int userId, int bookId) async =>
      _asBytes(await _bookValue(serverKey, userId, bookId, 'file_bytes'));

  Future<Uint8List?> loadCover(
    String serverKey,
    int userId,
    int bookId,
  ) async =>
      _asBytes(await _bookValue(serverKey, userId, bookId, 'cover_bytes'));

  Future<List<AnnotationView>> loadAnnotations(
    String serverKey,
    int userId,
    int bookId,
  ) async {
    final value = await _bookValue(
      serverKey,
      userId,
      bookId,
      'annotations_json',
    );
    if (value == null) return const [];
    return (jsonDecode(value as String) as List<dynamic>)
        .map((item) => AnnotationView.fromJson(item as Map<String, dynamic>))
        .where((item) => !item.deleted)
        .toList();
  }

  Future<List<BookmarkView>> loadBookmarks(
    String serverKey,
    int userId,
    int bookId,
  ) async {
    final value = await _bookValue(serverKey, userId, bookId, 'bookmarks_json');
    if (value == null) return const [];
    return (jsonDecode(value as String) as List<dynamic>)
        .map((item) => BookmarkView.fromJson(item as Map<String, dynamic>))
        .where((item) => !item.deleted)
        .toList();
  }

  Future<ReadingProgressView?> loadProgress(
    String serverKey,
    int userId,
    int bookId,
  ) async {
    final value = await _bookValue(serverKey, userId, bookId, 'progress_json');
    return value == null
        ? null
        : ReadingProgressView.fromJson(
            jsonDecode(value as String) as Map<String, dynamic>,
          );
  }

  Future<void> saveReaderState({
    required String serverKey,
    required int userId,
    required int bookId,
    List<AnnotationView>? annotations,
    List<BookmarkView>? bookmarks,
    ReadingProgressView? progress,
  }) async {
    if (!await isBookCached(serverKey, userId, bookId)) return;
    final values = <String, Object?>{};
    if (annotations != null) {
      values['annotations_json'] = jsonEncode(
        annotations.map((item) => item.toJson()).toList(),
      );
    }
    if (bookmarks != null) {
      values['bookmarks_json'] = jsonEncode(
        bookmarks.map((item) => item.toJson()).toList(),
      );
    }
    if (progress != null) {
      values['progress_json'] = jsonEncode(progress.toJson());
    }
    if (values.isEmpty) return;
    if (kIsWeb) {
      await _webStore.updateBook(serverKey, userId, bookId, values);
      return;
    }
    await (await _database).update(
      'offline_books',
      values,
      where: 'server_key = ? AND user_id = ? AND book_id = ?',
      whereArgs: [serverKey, userId, bookId],
    );
  }

  Future<void> applyAnnotationMappings({
    required String serverKey,
    required int userId,
    required Map<String, int> mappings,
  }) async {
    if (mappings.isEmpty) return;
    if (kIsWeb) {
      final rows = await _webStore.listBooks(
        serverKey: serverKey,
        userId: userId,
      );
      for (final row in rows) {
        final mapped = _mapAnnotationIds(
          row['annotations_json']! as String,
          mappings,
        );
        if (mapped == null) continue;
        await _webStore.updateBook(serverKey, userId, row['book_id']! as int, {
          'annotations_json': mapped,
        });
      }
      return;
    }
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'offline_books',
        columns: ['book_id', 'annotations_json'],
        where: 'server_key = ? AND user_id = ?',
        whereArgs: [serverKey, userId],
      );
      for (final row in rows) {
        final annotations =
            (jsonDecode(row['annotations_json']! as String) as List<dynamic>)
                .map(
                  (item) =>
                      AnnotationView.fromJson(item as Map<String, dynamic>),
                )
                .toList();
        var changed = false;
        final mapped = annotations.map((annotation) {
          if (annotation.id >= 0) return annotation;
          final serverId =
              mappings[annotationClientTempIdForLocalId(annotation.id)];
          if (serverId == null) return annotation;
          changed = true;
          return AnnotationView(
            id: serverId,
            bookId: annotation.bookId,
            quoteText: annotation.quoteText,
            noteText: annotation.noteText,
            color: annotation.color,
            anchor: annotation.anchor,
            version: 1,
            deleted: annotation.deleted,
            updatedAt: annotation.updatedAt,
          );
        }).toList();
        if (!changed) continue;
        await txn.update(
          'offline_books',
          {
            'annotations_json': jsonEncode(
              mapped.map((item) => item.toJson()).toList(),
            ),
          },
          where: 'server_key = ? AND user_id = ? AND book_id = ?',
          whereArgs: [serverKey, userId, row['book_id']],
        );
      }
    });
  }

  Future<int> totalSizeBytes(String serverKey, int userId) async {
    if (kIsWeb) {
      return (await _webStore.listBooks(
        serverKey: serverKey,
        userId: userId,
      )).fold<int>(
        0,
        (total, row) => total + ((row['size_bytes'] as num?)?.toInt() ?? 0),
      );
    }
    return Sqflite.firstIntValue(
          await (await _database).rawQuery(
            'SELECT COALESCE(SUM(size_bytes), 0) FROM offline_books WHERE server_key = ? AND user_id = ?',
            [serverKey, userId],
          ),
        ) ??
        0;
  }

  Future<Object?> _bookValue(
    String serverKey,
    int userId,
    int bookId,
    String column,
  ) async {
    if (kIsWeb) {
      return (await _webStore.getBook(serverKey, userId, bookId))?[column];
    }
    final rows = await (await _database).query(
      'offline_books',
      columns: [column],
      where: 'server_key = ? AND user_id = ? AND book_id = ?',
      whereArgs: [serverKey, userId, bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first[column];
  }

  Future<Database> _open() async {
    final databasePath = await _databasePath();
    return openDatabase(
      databasePath,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_books (
            server_key TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            book_id INTEGER NOT NULL,
            summary_json TEXT NOT NULL,
            detail_json TEXT NOT NULL,
            content_json TEXT,
            annotations_json TEXT NOT NULL,
            bookmarks_json TEXT NOT NULL,
            progress_json TEXT,
            file_bytes BLOB,
            cover_bytes BLOB,
            downloaded_at TEXT NOT NULL,
            size_bytes INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (server_key, user_id, book_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_chapters (
            server_key TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            book_id INTEGER NOT NULL,
            chapter_index INTEGER NOT NULL,
            chapter_json TEXT NOT NULL,
            PRIMARY KEY (server_key, user_id, book_id, chapter_index)
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_resources (
            server_key TEXT NOT NULL,
            user_id INTEGER NOT NULL,
            book_id INTEGER NOT NULL,
            resource_id TEXT NOT NULL,
            bytes BLOB NOT NULL,
            PRIMARY KEY (server_key, user_id, book_id, resource_id)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToServerScopedCache(db);
        }
      },
    );
  }

  Future<void> _claimLegacyRows(Database db, String serverKey) async {
    if (serverKey.isEmpty) return;
    await db.transaction((txn) async {
      for (final table in const [
        'offline_books',
        'offline_chapters',
        'offline_resources',
      ]) {
        await txn.update(table, {
          'server_key': serverKey,
        }, where: "server_key = ''");
      }
    });
  }

  Future<void> _migrateToServerScopedCache(Database db) async {
    await db.execute('ALTER TABLE offline_books RENAME TO offline_books_v1');
    await db.execute(
      'ALTER TABLE offline_chapters RENAME TO offline_chapters_v1',
    );
    await db.execute(
      'ALTER TABLE offline_resources RENAME TO offline_resources_v1',
    );
    await db.execute('''
        CREATE TABLE offline_books (
          server_key TEXT NOT NULL,
          user_id INTEGER NOT NULL,
          book_id INTEGER NOT NULL,
          summary_json TEXT NOT NULL,
          detail_json TEXT NOT NULL,
          content_json TEXT,
          annotations_json TEXT NOT NULL,
          bookmarks_json TEXT NOT NULL,
          progress_json TEXT,
          file_bytes BLOB,
          cover_bytes BLOB,
          downloaded_at TEXT NOT NULL,
          size_bytes INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (server_key, user_id, book_id)
        )
      ''');
    await db.execute('''
        CREATE TABLE offline_chapters (
          server_key TEXT NOT NULL,
          user_id INTEGER NOT NULL,
          book_id INTEGER NOT NULL,
          chapter_index INTEGER NOT NULL,
          chapter_json TEXT NOT NULL,
          PRIMARY KEY (server_key, user_id, book_id, chapter_index)
        )
      ''');
    await db.execute('''
        CREATE TABLE offline_resources (
          server_key TEXT NOT NULL,
          user_id INTEGER NOT NULL,
          book_id INTEGER NOT NULL,
          resource_id TEXT NOT NULL,
          bytes BLOB NOT NULL,
          PRIMARY KEY (server_key, user_id, book_id, resource_id)
        )
      ''');
    await db.execute('''
        INSERT INTO offline_books
        SELECT '', user_id, book_id, summary_json, detail_json, content_json,
          annotations_json, bookmarks_json, progress_json, file_bytes,
          cover_bytes, downloaded_at, size_bytes
        FROM offline_books_v1
      ''');
    await db.execute('''
        INSERT INTO offline_chapters
        SELECT '', user_id, book_id, chapter_index, chapter_json
        FROM offline_chapters_v1
      ''');
    await db.execute('''
        INSERT INTO offline_resources
        SELECT '', user_id, book_id, resource_id, bytes
        FROM offline_resources_v1
      ''');
    await db.execute('DROP TABLE offline_books_v1');
    await db.execute('DROP TABLE offline_chapters_v1');
    await db.execute('DROP TABLE offline_resources_v1');
  }

  Future<String> _databasePath() async {
    if (_databasePathOverride != null) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      return _databasePathOverride;
    }
    if (_usesFfiDatabase) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final supportDirectory = await getApplicationSupportDirectory();
      return p.join(supportDirectory.path, 'private_reader_offline_library.db');
    }
    return p.join(
      await getDatabasesPath(),
      'private_reader_offline_library.db',
    );
  }

  bool get _usesFfiDatabase =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is ByteBuffer) return value.asUint8List();
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return null;
  }

  String? _mapAnnotationIds(String annotationsJson, Map<String, int> mappings) {
    final annotations = (jsonDecode(annotationsJson) as List<dynamic>)
        .map((item) => AnnotationView.fromJson(item as Map<String, dynamic>))
        .toList();
    var changed = false;
    final mapped = annotations.map((annotation) {
      if (annotation.id >= 0) return annotation;
      final serverId =
          mappings[annotationClientTempIdForLocalId(annotation.id)];
      if (serverId == null) return annotation;
      changed = true;
      return AnnotationView(
        id: serverId,
        bookId: annotation.bookId,
        quoteText: annotation.quoteText,
        noteText: annotation.noteText,
        color: annotation.color,
        anchor: annotation.anchor,
        version: 1,
        deleted: annotation.deleted,
        updatedAt: annotation.updatedAt,
      );
    }).toList();
    return changed
        ? jsonEncode(mapped.map((item) => item.toJson()).toList())
        : null;
  }
}
