import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_reader_mobile/data/models/auth_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/offline_queue_service.dart';
import 'package:private_reader_mobile/data/services/session_storage.dart';
import 'package:private_reader_mobile/features/auth/auth_controller.dart';
import 'package:private_reader_mobile/features/bookshelf/bookshelf_controller.dart';

void main() {
  test(
    'latest queue count wins when refreshes complete out of order',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'private-reader-pending-count-',
      );
      final cache = OfflineBookCacheService(
        databasePathOverride: p.join(directory.path, 'books.db'),
      );
      final queue = _ControlledQueueService();
      final auth = AuthController(
        apiClient: ApiClient(baseUrl: _serverKey),
        sessionStorage: _MemorySessionStorage(),
        offlineBookCacheService: cache,
      );
      await _waitForBootstrap(auth);
      await auth.enterOfflineMode(
        const OfflineCacheIdentity(
          serverKey: _serverKey,
          userId: _userId,
          bookCount: 1,
          lastDownloadedAt: '2026-07-28T00:00:00Z',
        ),
      );

      final controller = BookshelfController(
        authController: auth,
        apiClient: ApiClient(baseUrl: _serverKey),
        offlineQueueService: queue,
        offlineBookCacheService: cache,
      );
      addTearDown(() async {
        controller.dispose();
        auth.dispose();
        await cache.close();
        await directory.delete(recursive: true);
      });

      await _waitUntil(() => queue.requests.length == 1);
      queue.requests[0].complete(2);
      await _waitUntil(() => controller.pendingCount == 2);

      queue.emitChange();
      queue.emitChange();
      expect(queue.requests, hasLength(3));

      queue.requests[2].complete(0);
      await _waitUntil(() => controller.pendingCount == 0);
      queue.requests[1].complete(2);
      await Future<void>.delayed(Duration.zero);

      expect(controller.pendingCount, 0);
    },
  );
}

const _serverKey = 'http://server-1:8080';
const _userId = 7;

Future<void> _waitForBootstrap(AuthController auth) async {
  await _waitUntil(() => !auth.isBootstrapping);
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _ControlledQueueService extends OfflineQueueService {
  final List<Completer<int>> requests = [];

  @override
  Future<int> pendingCount({required String serverKey, required int userId}) {
    final completer = Completer<int>();
    requests.add(completer);
    return completer.future;
  }

  void emitChange() => notifyListeners();
}

class _MemorySessionStorage extends SessionStorage {
  @override
  Future<Session?> readSession() async => null;

  @override
  Future<void> saveSession(Session session) async {}

  @override
  Future<void> clear() async {}
}
