import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_reader_mobile/data/models/auth_models.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/offline_queue_service.dart';
import 'package:private_reader_mobile/data/services/session_storage.dart';
import 'package:private_reader_mobile/features/annotations/annotation_change_notifier.dart';
import 'package:private_reader_mobile/features/auth/auth_controller.dart';
import 'package:private_reader_mobile/features/reader/models/annotation_anchor.dart';
import 'package:private_reader_mobile/features/reader/reader_controller.dart';

void main() {
  test(
    'offline annotations and flushed reading progress persist locally',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'private-reader-offline-annotation-',
      );
      final cache = OfflineBookCacheService(
        databasePathOverride: p.join(directory.path, 'books.db'),
      );
      final queue = OfflineQueueService(
        databasePathOverride: p.join(directory.path, 'queue.db'),
      );
      final apiClient = ApiClient(baseUrl: _serverKey);
      final auth = AuthController(
        apiClient: apiClient,
        sessionStorage: _MemorySessionStorage(),
        offlineBookCacheService: cache,
      );
      await _waitForBootstrap(auth);
      await _saveOfflineBook(cache);
      await auth.enterOfflineMode(
        const OfflineCacheIdentity(
          serverKey: _serverKey,
          userId: _userId,
          bookCount: 1,
          lastDownloadedAt: '2026-07-28T00:00:00Z',
        ),
      );

      final controller = ReaderController(
        bookId: _bookId,
        authController: auth,
        apiClient: apiClient,
        offlineQueueService: queue,
        offlineBookCacheService: cache,
        annotationChangeNotifier: AnnotationChangeNotifier(),
      );
      addTearDown(() async {
        controller.dispose();
        auth.dispose();
        await queue.close();
        await cache.close();
        await directory.delete(recursive: true);
      });
      await _waitForReader(controller);

      const selection = AnnotationSelection(
        blockAnchor: 'chapter-0-block-0',
        blockText: '离线批注测试文本',
        startOffset: 0,
        endOffset: 4,
      );
      await controller.addAnnotation(
        selection: selection,
        noteText: '第一版',
        color: '#C3924A',
        underlineStyle: AnnotationUnderlineStyle.solid,
      );

      final localAnnotation = controller.annotations.single;
      expect(localAnnotation.id, isNegative);
      var pending = await queue.loadPending(
        serverKey: _serverKey,
        userId: _userId,
      );
      expect(pending, hasLength(1));
      expect(
        pending.single.id,
        annotationClientTempIdForLocalId(localAnnotation.id),
      );
      expect(pending.single.payload['action'], 'CREATE');

      await controller.updateAnnotation(
        annotation: localAnnotation,
        noteText: '第二版',
        color: '#6F8F72',
      );

      pending = await queue.loadPending(serverKey: _serverKey, userId: _userId);
      expect(pending, hasLength(1));
      expect(pending.single.payload['action'], 'CREATE');
      expect(pending.single.payload['noteText'], '第二版');
      expect(controller.annotations.single.noteText, '第二版');
      expect(
        (await cache.loadAnnotations(
          _serverKey,
          _userId,
          _bookId,
        )).single.noteText,
        '第二版',
      );

      await controller.deleteAnnotation(controller.annotations.single);

      expect(controller.annotations, isEmpty);
      expect(
        await queue.loadPending(serverKey: _serverKey, userId: _userId),
        isEmpty,
      );
      expect(
        await cache.loadAnnotations(_serverKey, _userId, _bookId),
        isEmpty,
      );

      controller.updateVisibleAnchor('chapter-0-block-0');
      await controller.flushProgress();

      final progress = await cache.loadProgress(_serverKey, _userId, _bookId);
      expect(progress?.location, 'chapter-0-block-0');
      pending = await queue.loadPending(serverKey: _serverKey, userId: _userId);
      expect(pending, hasLength(1));
      expect(pending.single.entityType, PendingEntityType.progress);
    },
  );
}

const _serverKey = 'http://server-2:8080';
const _userId = 7;
const _bookId = 11;

Future<void> _saveOfflineBook(OfflineBookCacheService cache) async {
  const summary = BookSummary(
    id: _bookId,
    title: '离线批注测试',
    author: null,
    groupName: null,
    description: null,
    pluginId: 'txt',
    format: 'txt',
    sourceMissing: false,
    updatedAt: '2026-07-28T00:00:00Z',
  );
  const detail = BookDetail(
    id: _bookId,
    title: '离线批注测试',
    author: null,
    groupName: null,
    description: null,
    pluginId: 'txt',
    format: 'txt',
    sourceMissing: false,
    updatedAt: '2026-07-28T00:00:00Z',
    sourceType: 'LOCAL',
    manifest: null,
    capabilities: ['STRUCTURED_CONTENT'],
    hasStructuredContent: true,
    contentModel: 'CHAPTERS',
    latestContentVersionId: 1,
  );
  const content = BookContent(
    bookId: _bookId,
    contentModel: 'CHAPTERS',
    contentVersionId: 1,
    hasStructuredContent: true,
    chapters: [
      BookContentChapterSummary(
        chapterIndex: 0,
        title: '第一章',
        anchor: 'chapter-0',
      ),
    ],
  );
  const chapter = BookContentChapter(
    bookId: _bookId,
    contentModel: 'CHAPTERS',
    contentVersionId: 1,
    hasStructuredContent: true,
    chapterIndex: 0,
    title: '第一章',
    anchor: 'chapter-0',
    blocks: [
      BookContentBlock(
        blockIndex: 0,
        type: 'paragraph',
        anchor: 'chapter-0-block-0',
        text: '离线批注测试文本',
        plainText: '离线批注测试文本',
        meta: {},
      ),
    ],
  );
  await cache.saveDownloadedBook(
    serverKey: _serverKey,
    userId: _userId,
    summary: summary,
    detail: detail,
    content: content,
    annotations: const [],
    bookmarks: const [],
    sizeBytes: 0,
  );
  await cache.saveChapter(_serverKey, _userId, _bookId, chapter);
}

Future<void> _waitForBootstrap(AuthController auth) async {
  while (auth.isBootstrapping) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitForReader(ReaderController controller) async {
  while (controller.isLoading) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(controller.error, isNull);
}

class _MemorySessionStorage extends SessionStorage {
  @override
  Future<Session?> readSession() async => null;

  @override
  Future<void> saveSession(Session session) async {}

  @override
  Future<void> clear() async {}
}
