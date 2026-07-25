import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/book_models.dart';
import '../models/sync_models.dart';

class OfflineBookCacheService {
  Future<Database> get _database async {
    if (kIsWeb) {
      throw UnsupportedError('Web 端暂不支持离线书库');
    }
    _databaseFuture ??= _open();
    return _databaseFuture!;
  }

  Future<Database>? _databaseFuture;

  Future<List<BookSummary>> loadCachedBooks(int userId) async {
    if (kIsWeb) return const [];
    final rows = await (await _database).query(
      'offline_books',
      columns: ['summary_json'],
      where: 'user_id = ?',
      whereArgs: [userId],
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

  Future<Set<int>> cachedBookIds(int userId) async {
    if (kIsWeb) return <int>{};
    final rows = await (await _database).query(
      'offline_books',
      columns: ['book_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.map((row) => row['book_id']! as int).toSet();
  }

  Future<bool> isBookCached(int userId, int bookId) async {
    if (kIsWeb) return false;
    final rows = await (await _database).query(
      'offline_books',
      columns: ['book_id'],
      where: 'user_id = ? AND book_id = ?',
      whereArgs: [userId, bookId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> deleteBook(int userId, int bookId) async {
    if (kIsWeb) return;
    final db = await _database;
    await db.transaction((txn) async {
      final args = [userId, bookId];
      await txn.delete(
        'offline_resources',
        where: 'user_id = ? AND book_id = ?',
        whereArgs: args,
      );
      await txn.delete(
        'offline_chapters',
        where: 'user_id = ? AND book_id = ?',
        whereArgs: args,
      );
      await txn.delete(
        'offline_books',
        where: 'user_id = ? AND book_id = ?',
        whereArgs: args,
      );
    });
  }

  Future<void> saveChapter(
    int userId,
    int bookId,
    BookContentChapter chapter,
  ) async {
    if (kIsWeb) return;
    await (await _database).insert('offline_chapters', {
      'user_id': userId,
      'book_id': bookId,
      'chapter_index': chapter.chapterIndex,
      'chapter_json': jsonEncode(chapter.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveResource(
    int userId,
    int bookId,
    String resourceId,
    Uint8List bytes,
  ) async {
    if (kIsWeb) return;
    await (await _database).insert('offline_resources', {
      'user_id': userId,
      'book_id': bookId,
      'resource_id': resourceId,
      'bytes': bytes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveDownloadedBook({
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
    if (kIsWeb) return;
    await (await _database).insert('offline_books', {
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
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<BookDetail?> loadDetail(int userId, int bookId) async {
    final value = await _bookValue(userId, bookId, 'detail_json');
    return value == null
        ? null
        : BookDetail.fromJson(
            jsonDecode(value as String) as Map<String, dynamic>,
          );
  }

  Future<BookContent?> loadContent(int userId, int bookId) async {
    final value = await _bookValue(userId, bookId, 'content_json');
    return value == null
        ? null
        : BookContent.fromJson(
            jsonDecode(value as String) as Map<String, dynamic>,
          );
  }

  Future<BookContentChapter?> loadChapter(
    int userId,
    int bookId,
    int chapterIndex,
  ) async {
    if (kIsWeb) return null;
    final rows = await (await _database).query(
      'offline_chapters',
      columns: ['chapter_json'],
      where: 'user_id = ? AND book_id = ? AND chapter_index = ?',
      whereArgs: [userId, bookId, chapterIndex],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BookContentChapter.fromJson(
      jsonDecode(rows.first['chapter_json']! as String) as Map<String, dynamic>,
    );
  }

  Future<Uint8List?> loadResource(
    int userId,
    int bookId,
    String resourceId,
  ) async {
    if (kIsWeb) return null;
    final rows = await (await _database).query(
      'offline_resources',
      columns: ['bytes'],
      where: 'user_id = ? AND book_id = ? AND resource_id = ?',
      whereArgs: [userId, bookId, resourceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List?;
  }

  Future<Uint8List?> loadFile(int userId, int bookId) async =>
      (await _bookValue(userId, bookId, 'file_bytes')) as Uint8List?;

  Future<Uint8List?> loadCover(int userId, int bookId) async =>
      (await _bookValue(userId, bookId, 'cover_bytes')) as Uint8List?;

  Future<List<AnnotationView>> loadAnnotations(int userId, int bookId) async {
    final value = await _bookValue(userId, bookId, 'annotations_json');
    if (value == null) return const [];
    return (jsonDecode(value as String) as List<dynamic>)
        .map((item) => AnnotationView.fromJson(item as Map<String, dynamic>))
        .where((item) => !item.deleted)
        .toList();
  }

  Future<List<BookmarkView>> loadBookmarks(int userId, int bookId) async {
    final value = await _bookValue(userId, bookId, 'bookmarks_json');
    if (value == null) return const [];
    return (jsonDecode(value as String) as List<dynamic>)
        .map((item) => BookmarkView.fromJson(item as Map<String, dynamic>))
        .where((item) => !item.deleted)
        .toList();
  }

  Future<ReadingProgressView?> loadProgress(int userId, int bookId) async {
    final value = await _bookValue(userId, bookId, 'progress_json');
    return value == null
        ? null
        : ReadingProgressView.fromJson(
            jsonDecode(value as String) as Map<String, dynamic>,
          );
  }

  Future<void> saveReaderState({
    required int userId,
    required int bookId,
    List<AnnotationView>? annotations,
    List<BookmarkView>? bookmarks,
    ReadingProgressView? progress,
  }) async {
    if (kIsWeb || !await isBookCached(userId, bookId)) return;
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
    await (await _database).update(
      'offline_books',
      values,
      where: 'user_id = ? AND book_id = ?',
      whereArgs: [userId, bookId],
    );
  }

  Future<int> totalSizeBytes(int userId) async {
    if (kIsWeb) return 0;
    return Sqflite.firstIntValue(
          await (await _database).rawQuery(
            'SELECT COALESCE(SUM(size_bytes), 0) FROM offline_books WHERE user_id = ?',
            [userId],
          ),
        ) ??
        0;
  }

  Future<Object?> _bookValue(int userId, int bookId, String column) async {
    if (kIsWeb) return null;
    final rows = await (await _database).query(
      'offline_books',
      columns: [column],
      where: 'user_id = ? AND book_id = ?',
      whereArgs: [userId, bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first[column];
  }

  Future<Database> _open() async {
    final databasePath = await _databasePath();
    return openDatabase(
      databasePath,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_books (
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
            PRIMARY KEY (user_id, book_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_chapters (
            user_id INTEGER NOT NULL,
            book_id INTEGER NOT NULL,
            chapter_index INTEGER NOT NULL,
            chapter_json TEXT NOT NULL,
            PRIMARY KEY (user_id, book_id, chapter_index)
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_resources (
            user_id INTEGER NOT NULL,
            book_id INTEGER NOT NULL,
            resource_id TEXT NOT NULL,
            bytes BLOB NOT NULL,
            PRIMARY KEY (user_id, book_id, resource_id)
          )
        ''');
      },
    );
  }

  Future<String> _databasePath() async {
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
}
