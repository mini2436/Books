import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/features/reader/widgets/reader_html_view.dart';

void main() {
  test('Windows reader image file names are short and file safe', () {
    final fileName = windowsReaderImageFileName(
      BookContentBlock(
        blockIndex: 0,
        type: 'image',
        anchor: 'chapter-0-block-0',
        text: '',
        plainText: '',
        meta: {
          'resourceId': '${'very/long resource '.padRight(180, 'x')}?unsafe',
          'mediaType': 'image/jpeg',
        },
      ),
    );

    expect(fileName.length, lessThan(96));
    expect(fileName, matches(RegExp(r'^[A-Za-z0-9_-]+\.jpg$')));
  });
}
