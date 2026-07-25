import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';

void main() {
  test('offline book models survive JSON round trips', () {
    const detail = BookDetail(
      id: 7,
      title: '离线书籍',
      author: '作者',
      groupName: '测试',
      description: '简介',
      pluginId: 'epub',
      format: 'epub',
      sourceMissing: false,
      updatedAt: '2026-07-25T00:00:00Z',
      sourceType: 'LOCAL',
      manifest: {
        'meta': {'pageCount': 10},
      },
      capabilities: ['STRUCTURED_CONTENT'],
      hasStructuredContent: true,
      contentModel: 'CHAPTERS',
      latestContentVersionId: 2,
    );
    const block = BookContentBlock(
      blockIndex: 0,
      type: 'image',
      anchor: 'chapter-0-image-0',
      text: '',
      plainText: '',
      meta: {'resourceId': 'cover-image'},
    );
    const chapter = BookContentChapter(
      bookId: 7,
      contentModel: 'CHAPTERS',
      contentVersionId: 2,
      hasStructuredContent: true,
      chapterIndex: 0,
      title: '第一章',
      anchor: 'chapter-0',
      blocks: [block],
    );

    final restoredDetail = BookDetail.fromJson(detail.toJson());
    final restoredChapter = BookContentChapter.fromJson(chapter.toJson());

    expect(restoredDetail.title, detail.title);
    expect(restoredDetail.latestContentVersionId, 2);
    expect(restoredChapter.blocks.single.resourceId, 'cover-image');
  });

  test('offline reader state survives JSON round trips', () {
    const annotation = AnnotationView(
      id: -1,
      bookId: 7,
      quoteText: '摘录',
      noteText: '离线批注',
      color: '#C3924A',
      anchor: 'chapter-0',
      version: 0,
      deleted: false,
      updatedAt: '2026-07-25T00:00:00Z',
    );
    const bookmark = BookmarkView(
      id: -2,
      bookId: 7,
      location: 'chapter-0',
      label: '第一章',
      deleted: false,
      updatedAt: '2026-07-25T00:00:01Z',
    );
    const progress = ReadingProgressView(
      bookId: 7,
      location: 'chapter-0',
      progressPercent: 12.5,
      updatedAt: '2026-07-25T00:00:02Z',
    );

    expect(AnnotationView.fromJson(annotation.toJson()).noteText, '离线批注');
    expect(BookmarkView.fromJson(bookmark.toJson()).location, 'chapter-0');
    expect(
      ReadingProgressView.fromJson(progress.toJson()).progressPercent,
      12.5,
    );
  });
}
