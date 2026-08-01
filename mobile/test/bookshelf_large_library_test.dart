import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_reader_mobile/data/models/auth_models.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/offline_queue_service.dart';
import 'package:private_reader_mobile/data/services/session_storage.dart';
import 'package:private_reader_mobile/features/auth/auth_controller.dart';
import 'package:private_reader_mobile/features/bookshelf/bookshelf_controller.dart';

void main() {
  test('千本离线书架复用派生缓存并按需读取封面', () async {
    final directory = await Directory.systemTemp.createTemp(
      'private-reader-large-library-',
    );
    final cache = _CountingCoverCache(
      databasePathOverride: p.join(directory.path, 'books.db'),
    );
    for (var id = 1; id <= 1000; id++) {
      final summary = _summary(id);
      await cache.saveDownloadedBook(
        serverKey: _serverKey,
        userId: _userId,
        summary: summary,
        detail: _detail(summary),
        annotations: const [],
        bookmarks: const [],
        progress: id % 10 == 0
            ? ReadingProgressView(
                bookId: id,
                location: 'chapter-$id',
                progressPercent: 50,
                updatedAt:
                    '2026-07-${(id % 28 + 1).toString().padLeft(2, '0')}T00:00:00Z',
              )
            : null,
        sizeBytes: 0,
      );
    }

    final auth = AuthController(
      apiClient: ApiClient(baseUrl: _serverKey),
      sessionStorage: _MemorySessionStorage(),
      offlineBookCacheService: cache,
    );
    await _waitUntil(() => !auth.isBootstrapping);
    await auth.enterOfflineMode(
      const OfflineCacheIdentity(
        serverKey: _serverKey,
        userId: _userId,
        bookCount: 1000,
        lastDownloadedAt: '2026-07-28T00:00:00Z',
      ),
    );
    final controller = BookshelfController(
      authController: auth,
      apiClient: ApiClient(baseUrl: _serverKey),
      offlineQueueService: _ZeroQueueService(),
      offlineBookCacheService: cache,
    );
    addTearDown(() async {
      controller.dispose();
      auth.dispose();
      await cache.close();
      await directory.delete(recursive: true);
    });

    await _waitUntil(
      () =>
          controller.books.length == 1000 &&
          controller.groupedBooks.length == 10 &&
          !controller.isLoading,
    );

    expect(cache.coverLoads, 0);
    expect(controller.groupedBooks, hasLength(10));
    expect(controller.filterOptions, hasLength(13));
    expect(controller.recentBooks, hasLength(10));
    expect(identical(controller.groupedBooks, controller.groupedBooks), isTrue);
    expect(
      identical(controller.filterOptions, controller.filterOptions),
      isTrue,
    );
    expect(
      identical(controller.filteredBooks, controller.filteredBooks),
      isTrue,
    );
    expect(controller.searchBooks('图书 999').single.id, 999);

    controller.setFilter(bookshelfFilterRead);
    expect(controller.filteredBooks, hasLength(100));

    final firstCover = controller.offlineCoverForBook(1);
    final repeatedCover = controller.offlineCoverForBook(1);
    expect(firstCover, isNotNull);
    expect(identical(firstCover, repeatedCover), isTrue);
    expect(await firstCover, Uint8List.fromList([1, 2, 3]));
    expect(cache.coverLoads, 1);
  });
}

const _serverKey = 'http://large-library:8080';
const _userId = 7;

BookSummary _summary(int id) => BookSummary(
  id: id,
  title: '图书 $id',
  author: '作者 ${id % 50}',
  groupName: '分组 ${id % 10}',
  description: '用于千本书架测试的简介 $id',
  pluginId: 'epub',
  format: 'epub',
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

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 300 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _CountingCoverCache extends OfflineBookCacheService {
  _CountingCoverCache({required super.databasePathOverride});

  int coverLoads = 0;

  @override
  Future<Uint8List?> loadCover(String serverKey, int userId, int bookId) async {
    coverLoads += 1;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _ZeroQueueService extends OfflineQueueService {
  @override
  Future<int> pendingCount({required String serverKey, required int userId}) {
    return Future.value(0);
  }
}

class _MemorySessionStorage extends SessionStorage {
  @override
  Future<Session?> readSession() async => null;

  @override
  Future<void> saveSession(Session session) async {}

  @override
  Future<void> clear() async {}
}
