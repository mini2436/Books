import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';

void main() {
  test('cover URL includes the server supplied cover version', () {
    final client = ApiClient(baseUrl: 'https://reader.example');

    expect(
      client.buildBookCoverUrl(42, version: '12345'),
      'https://reader.example/api/me/books/42/cover?v=12345',
    );
  });

  test('book summary preserves cover version through JSON and copy', () {
    final summary = BookSummary.fromJson({
      'id': 42,
      'title': '缓存测试',
      'pluginId': 'epub',
      'format': 'epub',
      'sourceMissing': false,
      'updatedAt': '2026-07-30T00:00:00Z',
      'coverVersion': '12345',
    });

    expect(summary.coverVersion, '12345');
    expect(summary.toJson()['coverVersion'], '12345');
    expect(summary.copyWith(groupName: '测试').coverVersion, '12345');
  });
}
