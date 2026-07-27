import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/auth_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/session_storage.dart';
import 'package:private_reader_mobile/features/auth/auth_controller.dart';

void main() {
  test(
    'offline entry uses the latest cached account without a session',
    () async {
      final controller = _controller(cachedUserId: 42);
      addTearDown(controller.dispose);
      await _waitForBootstrap(controller);

      final entered = await controller.enterOfflineMode();

      expect(entered, isTrue);
      expect(controller.isAuthenticated, isFalse);
      expect(controller.canAccessApp, isTrue);
      expect(controller.isOfflineGuest, isTrue);
      expect(controller.isOfflineMode, isTrue);
      expect(controller.activeUserId, 42);

      controller.exitOfflineMode();
      expect(controller.canAccessApp, isFalse);
      expect(controller.activeUserId, isNull);
    },
  );

  test('offline entry explains when the device has no cached books', () async {
    final controller = _controller(cachedUserId: null);
    addTearDown(controller.dispose);
    await _waitForBootstrap(controller);

    final entered = await controller.enterOfflineMode();

    expect(entered, isFalse);
    expect(controller.canAccessApp, isFalse);
    expect(controller.errorMessage, contains('还没有离线缓存'));
  });
}

AuthController _controller({required int? cachedUserId}) => AuthController(
  apiClient: ApiClient(baseUrl: 'http://localhost:8080'),
  sessionStorage: _MemorySessionStorage(),
  offlineBookCacheService: _FakeOfflineBookCacheService(cachedUserId),
);

Future<void> _waitForBootstrap(AuthController controller) async {
  while (controller.isBootstrapping) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _MemorySessionStorage extends SessionStorage {
  @override
  Future<Session?> readSession() async => null;

  @override
  Future<void> saveSession(Session session) async {}

  @override
  Future<void> clear() async {}
}

class _FakeOfflineBookCacheService extends OfflineBookCacheService {
  _FakeOfflineBookCacheService(this.cachedUserId);

  final int? cachedUserId;

  @override
  Future<int?> latestCachedUserId() async => cachedUserId;
}
