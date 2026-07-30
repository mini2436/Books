import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/features/annotations/annotation_center_controller.dart';
import 'package:private_reader_mobile/features/annotations/annotation_markdown_exporter.dart';

void main() {
  test('builds readable Markdown for the selected books and current user', () {
    final markdown = buildAnnotationMarkdown(
      groups: [
        _group(
          bookId: 11,
          title: '给莉莉的信：关于世界之道',
          author: '艾伦·麦克法兰',
          entries: [
            _entry(
              bookId: 11,
              quote: '第一行高亮\n第二行高亮',
              note: '这是我的笔记。',
              updatedAt: '2026-07-30T08:15:00',
            ),
          ],
        ),
      ],
      userDisplayName: '轻阅用户',
      username: 'reader',
      exportedAt: DateTime(2026, 7, 30, 16, 20),
    );

    expect(markdown, startsWith('# 轻阅批注导出\n'));
    expect(markdown, contains('- 导出用户：轻阅用户（reader）'));
    expect(markdown, contains('- 书籍数量：1'));
    expect(markdown, contains('- 批注数量：1'));
    expect(markdown, contains('## 1. 给莉莉的信：关于世界之道'));
    expect(markdown, contains('- 作者：艾伦·麦克法兰'));
    expect(markdown, contains('> 第一行高亮\n> 第二行高亮'));
    expect(markdown, contains('**笔记**\n\n这是我的笔记。'));
    expect(markdown, contains('- 更新时间：2026-07-30 08:15'));
  });

  test('escapes headings, fills missing content, and sanitizes file names', () {
    final markdown = buildAnnotationMarkdown(
      groups: [
        _group(
          bookId: 12,
          title: '# 标题\n下一行',
          author: null,
          entries: [
            _entry(bookId: 12, quote: null, note: null, updatedAt: '未知时间'),
          ],
        ),
      ],
      userDisplayName: 'reader',
      username: 'reader',
      exportedAt: DateTime(2026, 7, 30, 9, 5),
    );

    expect(markdown, contains('## 1. \\# 标题 下一行'));
    expect(markdown, contains('- 作者：未知作者'));
    expect(markdown, contains('> 未记录高亮原文'));
    expect(markdown, contains('- 更新时间：未知时间'));
    expect(
      buildAnnotationExportFileName(
        username: 'reader:test/name',
        exportedAt: DateTime(2026, 7, 30, 9, 5),
      ),
      '轻阅批注-reader-test-name-20260730-0905.md',
    );
  });
}

AnnotationBookGroup _group({
  required int bookId,
  required String title,
  required String? author,
  required List<AnnotationCenterEntry> entries,
}) {
  final book = BookSummary(
    id: bookId,
    title: title,
    author: author,
    groupName: null,
    description: null,
    pluginId: 'builtin',
    format: 'epub',
    sourceMissing: false,
    updatedAt: '2026-07-30T08:00:00',
  );
  return AnnotationBookGroup(
    book: book,
    entries: entries
        .map(
          (entry) =>
              AnnotationCenterEntry(annotation: entry.annotation, book: book),
        )
        .toList(),
  );
}

AnnotationCenterEntry _entry({
  required int bookId,
  required String? quote,
  required String? note,
  required String updatedAt,
}) {
  const placeholderBook = BookSummary(
    id: -1,
    title: 'placeholder',
    author: null,
    groupName: null,
    description: null,
    pluginId: 'builtin',
    format: 'epub',
    sourceMissing: false,
    updatedAt: '',
  );
  return AnnotationCenterEntry(
    annotation: AnnotationView(
      id: bookId,
      bookId: bookId,
      quoteText: quote,
      noteText: note,
      color: '#9B6B43',
      anchor: 'chapter-1',
      version: 1,
      deleted: false,
      updatedAt: updatedAt,
    ),
    book: placeholderBook,
  );
}
