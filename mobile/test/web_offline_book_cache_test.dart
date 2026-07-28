@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';

void main() {
  test('IndexedDB persists a complete offline book and reader state', () async {
    final service = OfflineBookCacheService();
    final serverKey =
        'http://web-test-${DateTime.now().microsecondsSinceEpoch}';
    const userId = 7001;
    const bookId = 9001;
    addTearDown(() async {
      await service.deleteBook(serverKey, userId, bookId);
      await service.close();
    });

    await service.saveChapter(serverKey, userId, bookId, _chapter);
    await service.saveResource(
      serverKey,
      userId,
      bookId,
      'cover-image',
      Uint8List.fromList([1, 2, 3, 4]),
    );
    await service.saveDownloadedBook(
      serverKey: serverKey,
      userId: userId,
      summary: _summary,
      detail: _detail,
      content: _content,
      annotations: const [],
      bookmarks: const [],
      fileBytes: Uint8List.fromList([5, 6, 7]),
      coverBytes: Uint8List.fromList([8, 9]),
      sizeBytes: 9,
    );

    expect(await service.isBookCached(serverKey, userId, bookId), isTrue);
    expect(await service.cachedBookIds(serverKey, userId), {bookId});
    expect(
      (await service.loadCachedBooks(serverKey, userId)).single.title,
      'Web 离线测试',
    );
    expect((await service.loadDetail(serverKey, userId, bookId))?.id, bookId);
    expect(
      (await service.loadContent(serverKey, userId, bookId))?.chapters,
      hasLength(1),
    );
    expect(
      (await service.loadChapter(serverKey, userId, bookId, 0))?.blocks,
      hasLength(1),
    );
    expect(
      await service.loadResource(serverKey, userId, bookId, 'cover-image'),
      Uint8List.fromList([1, 2, 3, 4]),
    );
    expect(
      await service.loadFile(serverKey, userId, bookId),
      Uint8List.fromList([5, 6, 7]),
    );
    expect(
      await service.loadCover(serverKey, userId, bookId),
      Uint8List.fromList([8, 9]),
    );
    expect(await service.totalSizeBytes(serverKey, userId), 9);

    const localAnnotation = AnnotationView(
      id: -1,
      bookId: bookId,
      quoteText: '离线文本',
      noteText: '浏览器批注',
      color: '#C3924A',
      anchor: 'chapter-0-block-0',
      version: 0,
      deleted: false,
      updatedAt: '2026-07-28T00:00:00Z',
    );
    const progress = ReadingProgressView(
      bookId: bookId,
      location: 'chapter-0-block-0',
      progressPercent: 32,
      updatedAt: '2026-07-28T00:00:00Z',
    );
    await service.saveReaderState(
      serverKey: serverKey,
      userId: userId,
      bookId: bookId,
      annotations: const [localAnnotation],
      progress: progress,
    );

    expect(
      (await service.loadAnnotations(
        serverKey,
        userId,
        bookId,
      )).single.noteText,
      '浏览器批注',
    );
    expect(
      (await service.loadProgress(serverKey, userId, bookId))?.progressPercent,
      32,
    );
    await service.applyAnnotationMappings(
      serverKey: serverKey,
      userId: userId,
      mappings: {annotationClientTempIdForLocalId(-1): 88},
    );
    expect(
      (await service.loadAnnotations(serverKey, userId, bookId)).single.id,
      88,
    );

    final identities = await service.listCachedIdentities(serverKey);
    expect(
      identities.any(
        (identity) =>
            identity.serverKey == serverKey &&
            identity.userId == userId &&
            identity.bookCount == 1,
      ),
      isTrue,
    );

    await service.deleteBook(serverKey, userId, bookId);
    expect(await service.isBookCached(serverKey, userId, bookId), isFalse);
    expect(await service.loadChapter(serverKey, userId, bookId, 0), isNull);
  });

  test('IndexedDB isolates the same book id by server and user', () async {
    final service = OfflineBookCacheService();
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final firstServer = 'http://web-isolation-a-$suffix';
    final secondServer = 'http://web-isolation-b-$suffix';
    const firstUser = 7101;
    const secondUser = 7102;
    const bookId = 9001;
    addTearDown(() async {
      await service.deleteBook(firstServer, firstUser, bookId);
      await service.deleteBook(secondServer, secondUser, bookId);
      await service.close();
    });

    Future<void> cacheFor(String serverKey, int userId, String note) async {
      await service.saveDownloadedBook(
        serverKey: serverKey,
        userId: userId,
        summary: _summary,
        detail: _detail,
        content: _content,
        annotations: [
          AnnotationView(
            id: -userId,
            bookId: bookId,
            quoteText: '相同图书',
            noteText: note,
            color: '#C3924A',
            anchor: 'chapter-0-block-0',
            version: 0,
            deleted: false,
            updatedAt: '2026-07-28T00:00:00Z',
          ),
        ],
        bookmarks: const [],
        sizeBytes: 1,
      );
    }

    await cacheFor(firstServer, firstUser, '只同步到服务器 A');
    await cacheFor(secondServer, secondUser, '只同步到服务器 B');

    expect(
      (await service.loadAnnotations(
        firstServer,
        firstUser,
        bookId,
      )).single.noteText,
      '只同步到服务器 A',
    );
    expect(
      (await service.loadAnnotations(
        secondServer,
        secondUser,
        bookId,
      )).single.noteText,
      '只同步到服务器 B',
    );

    await service.deleteBook(firstServer, firstUser, bookId);
    expect(await service.isBookCached(firstServer, firstUser, bookId), isFalse);
    expect(
      await service.isBookCached(secondServer, secondUser, bookId),
      isTrue,
    );
  });
}

const _summary = BookSummary(
  id: 9001,
  title: 'Web 离线测试',
  author: null,
  groupName: null,
  description: null,
  pluginId: 'txt',
  format: 'txt',
  sourceMissing: false,
  updatedAt: '2026-07-28T00:00:00Z',
);

const _detail = BookDetail(
  id: 9001,
  title: 'Web 离线测试',
  author: null,
  groupName: null,
  description: null,
  pluginId: 'txt',
  format: 'txt',
  sourceMissing: false,
  updatedAt: '2026-07-28T00:00:00Z',
  sourceType: 'MANAGED_UPLOAD',
  manifest: null,
  capabilities: ['STRUCTURED_CONTENT'],
  hasStructuredContent: true,
  contentModel: 'CHAPTERS',
  latestContentVersionId: 1,
);

const _content = BookContent(
  bookId: 9001,
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

const _chapter = BookContentChapter(
  bookId: 9001,
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
      text: '离线文本',
      plainText: '离线文本',
      meta: {},
    ),
  ],
);
