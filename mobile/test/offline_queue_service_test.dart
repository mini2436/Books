import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/data/services/offline_queue_service.dart';

void main() {
  group('OfflineQueueService web codec', () {
    test('decodes and sorts stored pending operations', () {
      const later = PendingOperation(
        id: 'progress-2',
        entityType: PendingEntityType.progress,
        payload: {'bookId': 2, 'location': 'chapter-2'},
        createdAt: '2026-07-12T10:01:00Z',
      );
      const earlier = PendingOperation(
        id: 'bookmark-1',
        entityType: PendingEntityType.bookmark,
        payload: {'bookId': 1, 'location': 'chapter-1'},
        createdAt: '2026-07-12T10:00:00Z',
      );
      final raw = jsonEncode([later.toDatabaseRow(), earlier.toDatabaseRow()]);

      final decoded = OfflineQueueService.decodeWebOperations(raw);

      expect(decoded.map((item) => item.id), ['bookmark-1', 'progress-2']);
      expect(decoded.first.payload['location'], 'chapter-1');
      expect(decoded.last.entityType, PendingEntityType.progress);
    });

    test('treats missing or corrupt browser storage as an empty queue', () {
      expect(OfflineQueueService.decodeWebOperations(null), isEmpty);
      expect(OfflineQueueService.decodeWebOperations('not-json'), isEmpty);
    });
  });
}
