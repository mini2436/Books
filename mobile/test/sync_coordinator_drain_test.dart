import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/offline_queue_service.dart';
import 'package:private_reader_mobile/data/services/sync_coordinator.dart';

void main() {
  test(
    'operations queued during a flush are drained in the next pass',
    () async {
      final queue = _MemoryQueueService()..add(_operation('first'));
      final apiClient = _BlockingSyncApiClient();
      final authListenable = ChangeNotifier();
      final coordinator = SyncCoordinator(
        apiClient: apiClient,
        offlineQueueService: queue,
        offlineBookCacheService: _MemoryBookCacheService(),
        runAuthorized: <T>(action) => action('access-token'),
        isAuthenticated: () => true,
        currentServerKey: () => _serverKey,
        currentUserId: () => _userId,
        authListenable: authListenable,
        connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
      );
      addTearDown(() {
        coordinator.dispose();
        authListenable.dispose();
      });

      final flush = coordinator.flushPendingOperations();
      await _waitUntil(() => apiClient.pushCount == 1);

      queue.add(_operation('second'));
      apiClient.firstPush.complete(
        const SyncPushResponse(annotationMappings: {}, conflicts: []),
      );

      expect(await flush, 2);
      expect(apiClient.pushCount, 2);
      expect(queue.operations, isEmpty);
    },
  );
}

const _serverKey = 'http://server-1:8080';
const _userId = 7;

PendingOperation _operation(String id) => PendingOperation(
  id: id,
  serverKey: _serverKey,
  userId: _userId,
  entityType: PendingEntityType.progress,
  payload: {
    'bookId': id == 'first' ? 1 : 2,
    'location': 'chapter-0',
    'progressPercent': 10.0,
    'updatedAt': '2026-07-28T00:00:00Z',
  },
  createdAt: '2026-07-28T00:00:00Z',
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _MemoryQueueService extends OfflineQueueService {
  final List<PendingOperation> operations = [];

  void add(PendingOperation operation) {
    operations.add(operation);
    notifyListeners();
  }

  @override
  Future<List<PendingOperation>> loadPending({
    required String serverKey,
    required int userId,
  }) async => operations
      .where(
        (operation) =>
            operation.serverKey == serverKey && operation.userId == userId,
      )
      .toList();

  @override
  Future<void> deleteByIds(List<String> ids) async {
    operations.removeWhere((operation) => ids.contains(operation.id));
    notifyListeners();
  }
}

class _BlockingSyncApiClient extends ApiClient {
  _BlockingSyncApiClient() : super(baseUrl: _serverKey);

  final Completer<SyncPushResponse> firstPush = Completer<SyncPushResponse>();
  int pushCount = 0;

  @override
  Future<SyncPushResponse> pushSync(
    String accessToken,
    SyncPushRequest request,
  ) {
    pushCount++;
    if (pushCount == 1) return firstPush.future;
    return Future.value(
      const SyncPushResponse(annotationMappings: {}, conflicts: []),
    );
  }
}

class _MemoryBookCacheService extends OfflineBookCacheService {
  @override
  Future<void> applyAnnotationMappings({
    required String serverKey,
    required int userId,
    required Map<String, int> mappings,
  }) async {}
}
