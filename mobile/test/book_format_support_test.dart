import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';

void main() {
  test('structured reader accepts all unified content formats', () {
    for (final format in const ['txt', 'epub', 'cbz', 'fb2', 'mobi']) {
      final detail = BookDetail(
        id: 1,
        title: 'Book',
        author: null,
        groupName: null,
        description: null,
        pluginId: 'plugin-$format',
        format: format,
        sourceMissing: false,
        updatedAt: '',
        sourceType: 'MANAGED_UPLOAD',
        manifest: null,
        capabilities: const ['READ_ONLINE'],
        hasStructuredContent: true,
        contentModel: 'UNIFIED_V2',
        latestContentVersionId: 1,
      );

      expect(detail.supportsStructuredReader, isTrue, reason: format);
    }
  });

  test('structured reader still requires generated content', () {
    const detail = BookDetail(
      id: 1,
      title: 'Book',
      author: null,
      groupName: null,
      description: null,
      pluginId: 'plugin-cbz',
      format: 'cbz',
      sourceMissing: false,
      updatedAt: '',
      sourceType: 'MANAGED_UPLOAD',
      manifest: null,
      capabilities: ['READ_ONLINE'],
      hasStructuredContent: false,
      contentModel: null,
      latestContentVersionId: null,
    );

    expect(detail.supportsStructuredReader, isFalse);
  });
}
