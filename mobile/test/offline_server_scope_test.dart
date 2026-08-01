import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/offline_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'offline books with matching numeric ids stay isolated by server',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'private-reader-cache-scope-',
      );
      final service = OfflineBookCacheService(
        databasePathOverride: p.join(directory.path, 'books.db'),
      );
      addTearDown(() async {
        await service.close();
        await directory.delete(recursive: true);
      });

      await _saveBook(service, serverKey: _server1, title: '服务器一的图书');
      await _saveBook(service, serverKey: _server2, title: '服务器二的图书');

      final server1Books = await service.loadCachedBooks(_server1, 7);
      final server2Books = await service.loadCachedBooks(_server2, 7);

      expect(server1Books.single.title, '服务器一的图书');
      expect(server2Books.single.title, '服务器二的图书');
      expect(await service.cachedBookIds(_server1, 7), {11});
      expect(await service.cachedBookIds(_server2, 7), {11});
      final identities = await service.listCachedIdentities(_server1);
      expect(identities, hasLength(2));
      expect(identities.map((identity) => identity.serverKey).toSet(), {
        _server1,
        _server2,
      });
      expect(identities.every((identity) => identity.bookCount == 1), isTrue);
    },
  );

  test(
    'pending operations are returned only for their server and user',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'private-reader-queue-scope-',
      );
      final service = OfflineQueueService(
        databasePathOverride: p.join(directory.path, 'queue.db'),
      );
      addTearDown(() async {
        await service.close();
        await directory.delete(recursive: true);
      });

      await service.enqueue(_progress('server-1', _server1, 7));
      await service.enqueue(_progress('server-2', _server2, 7));
      await service.enqueue(_progress('other-user', _server2, 8));

      final server1 = await service.loadPending(serverKey: _server1, userId: 7);
      final server2 = await service.loadPending(serverKey: _server2, userId: 7);

      expect(server1.map((item) => item.id), ['server-1']);
      expect(server2.map((item) => item.id), ['server-2']);
      expect(await service.pendingCount(serverKey: _server2, userId: 8), 1);
    },
  );

  test('version 1 cache is retained and assigned to current server', () async {
    final directory = await Directory.systemTemp.createTemp(
      'private-reader-cache-migration-',
    );
    final databasePath = p.join(directory.path, 'legacy.db');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final legacy = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_books (
            user_id INTEGER NOT NULL, book_id INTEGER NOT NULL,
            summary_json TEXT NOT NULL, detail_json TEXT NOT NULL,
            content_json TEXT, annotations_json TEXT NOT NULL,
            bookmarks_json TEXT NOT NULL, progress_json TEXT,
            file_bytes BLOB, cover_bytes BLOB, downloaded_at TEXT NOT NULL,
            size_bytes INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (user_id, book_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_chapters (
            user_id INTEGER NOT NULL, book_id INTEGER NOT NULL,
            chapter_index INTEGER NOT NULL, chapter_json TEXT NOT NULL,
            PRIMARY KEY (user_id, book_id, chapter_index)
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_resources (
            user_id INTEGER NOT NULL, book_id INTEGER NOT NULL,
            resource_id TEXT NOT NULL, bytes BLOB NOT NULL,
            PRIMARY KEY (user_id, book_id, resource_id)
          )
        ''');
        final summary = _summary('升级前的图书');
        await db.insert('offline_books', {
          'user_id': 7,
          'book_id': 11,
          'summary_json': jsonEncode(summary.toJson()),
          'detail_json': jsonEncode(_detail(summary).toJson()),
          'annotations_json': '[]',
          'bookmarks_json': '[]',
          'downloaded_at': '2026-07-28T00:00:00Z',
        });
      },
    );
    await legacy.close();

    final service = OfflineBookCacheService(databasePathOverride: databasePath);
    addTearDown(() async {
      await service.close();
      await directory.delete(recursive: true);
    });

    final identity = await service.latestCachedIdentity(_server1);

    expect(identity?.serverKey, _server1);
    expect(identity?.userId, 7);
    expect((await service.loadCachedBooks(_server1, 7)).single.title, '升级前的图书');
  });

  test('server annotation mappings replace cached local ids', () async {
    final directory = await Directory.systemTemp.createTemp(
      'private-reader-annotation-mapping-',
    );
    final service = OfflineBookCacheService(
      databasePathOverride: p.join(directory.path, 'books.db'),
    );
    addTearDown(() async {
      await service.close();
      await directory.delete(recursive: true);
    });
    await _saveBook(service, serverKey: _server2, title: '批注映射测试');
    const localId = -123456;
    await service.saveReaderState(
      serverKey: _server2,
      userId: 7,
      bookId: 11,
      annotations: const [
        AnnotationView(
          id: localId,
          bookId: 11,
          quoteText: '摘录',
          noteText: '离线暂存',
          color: '#C3924A',
          anchor: 'chapter-0',
          version: 0,
          deleted: false,
          updatedAt: '2026-07-28T00:00:00Z',
        ),
      ],
    );

    await service.applyAnnotationMappings(
      serverKey: _server2,
      userId: 7,
      mappings: {annotationClientTempIdForLocalId(localId): 88},
    );

    final mapped = (await service.loadAnnotations(_server2, 7, 11)).single;
    expect(mapped.id, 88);
    expect(mapped.version, 1);
    expect(mapped.noteText, '离线暂存');
  });

  test('reading progresses are loaded in one scoped batch', () async {
    final directory = await Directory.systemTemp.createTemp(
      'private-reader-progress-batch-',
    );
    final service = OfflineBookCacheService(
      databasePathOverride: p.join(directory.path, 'books.db'),
    );
    addTearDown(() async {
      await service.close();
      await directory.delete(recursive: true);
    });

    for (var id = 1; id <= 1000; id++) {
      final summary = _summary('批量图书 $id', id: id);
      await service.saveDownloadedBook(
        serverKey: _server1,
        userId: 7,
        summary: summary,
        detail: _detail(summary),
        annotations: const [],
        bookmarks: const [],
        progress: ReadingProgressView(
          bookId: id,
          location: 'chapter-$id',
          progressPercent: id / 10,
          updatedAt: '2026-07-28T00:00:00Z',
        ),
        sizeBytes: 0,
      );
    }
    await _saveBook(service, serverKey: _server2, title: '其他服务器');

    final progresses = await service.loadProgresses(_server1, 7);

    expect(progresses, hasLength(1000));
    expect(
      progresses.map((item) => item.bookId).toSet(),
      containsAll([1, 1000]),
    );
    expect(
      progresses.every(
        (item) => item.bookId != 11 || item.location == 'chapter-11',
      ),
      isTrue,
    );
  });
}

const _server1 = 'http://server-1:8080';
const _server2 = 'http://server-2:8080';

Future<void> _saveBook(
  OfflineBookCacheService service, {
  required String serverKey,
  required String title,
}) async {
  final summary = _summary(title);
  final detail = _detail(summary);
  await service.saveDownloadedBook(
    serverKey: serverKey,
    userId: 7,
    summary: summary,
    detail: detail,
    annotations: const [],
    bookmarks: const [],
    sizeBytes: 0,
  );
}

BookSummary _summary(String title, {int id = 11}) => BookSummary(
  id: id,
  title: title,
  author: null,
  groupName: null,
  description: null,
  pluginId: 'txt',
  format: 'txt',
  sourceMissing: false,
  updatedAt: '2026-07-28T00:00:00Z',
);

BookDetail _detail(BookSummary summary) => BookDetail(
  id: summary.id,
  title: summary.title,
  author: summary.author,
  groupName: summary.groupName,
  description: summary.description,
  pluginId: summary.pluginId,
  format: summary.format,
  sourceMissing: summary.sourceMissing,
  updatedAt: summary.updatedAt,
  sourceType: 'LOCAL',
  manifest: null,
  capabilities: const ['STRUCTURED_CONTENT'],
  hasStructuredContent: true,
  contentModel: 'CHAPTERS',
  latestContentVersionId: 1,
);

PendingOperation _progress(String id, String serverKey, int userId) =>
    PendingOperation(
      id: id,
      serverKey: serverKey,
      userId: userId,
      entityType: PendingEntityType.progress,
      payload: const {
        'bookId': 11,
        'location': 'chapter-1',
        'progressPercent': 25.0,
        'updatedAt': '2026-07-28T00:00:00Z',
      },
      createdAt: '2026-07-28T00:00:00Z',
    );
