import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/auth_models.dart';
import '../../data/services/api_client.dart';
import '../../data/services/offline_queue_service.dart';
import '../../data/services/session_storage.dart';
import '../../data/services/sync_coordinator.dart';
import '../settings/server_config_controller.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SessionStorage(),
);
final offlineQueueServiceProvider = Provider<OfflineQueueService>(
  (ref) => OfflineQueueService(),
);

final authControllerProvider = ChangeNotifierProvider<AuthController>(
  (ref) => AuthController(
    apiClient: (() {
      ref.watch(serverConfigControllerProvider);
      return ref.watch(apiClientProvider);
    })(),
    sessionStorage: ref.watch(sessionStorageProvider),
  ),
);

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final authController = ref.read(authControllerProvider);
  final coordinator = SyncCoordinator(
    apiClient: ref.watch(apiClientProvider),
    offlineQueueService: ref.watch(offlineQueueServiceProvider),
    runAuthorized: authController.runAuthorized,
    isAuthenticated: () => authController.isAuthenticated,
    authListenable: authController,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class AuthController extends ChangeNotifier {
  AuthController({
    required ApiClient apiClient,
    required SessionStorage sessionStorage,
  }) : _apiClient = apiClient,
       _sessionStorage = sessionStorage {
    unawaited(_restoreSession());
  }

  final ApiClient _apiClient;
  final SessionStorage _sessionStorage;

  Session? _session;
  bool _isBootstrapping = true;
  bool _isWorking = false;
  String? _errorMessage;
  Future<Session?>? _refreshInFlight;

  Session? get session => _session;
  AuthUser? get user => _session?.user;
  String? get accessToken => _session?.accessToken;
  bool get isAuthenticated => _session != null;
  bool get isBootstrapping => _isBootstrapping;
  bool get isWorking => _isWorking;
  String? get errorMessage => _errorMessage;

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    _setWorking(true);
    try {
      final session = await _apiClient.login(
        username: username,
        password: password,
      );
      _session = session;
      _errorMessage = null;
      await _sessionStorage.saveSession(session);
    } on ApiException catch (error) {
      _errorMessage = error.message;
      rethrow;
    } finally {
      _setWorking(false);
    }
  }

  Future<void> signOut() async {
    final current = _session;
    _session = null;
    _errorMessage = null;
    notifyListeners();

    if (current != null) {
      try {
        await _apiClient.logout(current.accessToken);
      } catch (_) {
        // Keep local sign-out resilient even if the backend is unreachable.
      }
    }
    await _sessionStorage.clear();
  }

  Future<T> runAuthorized<T>(
    Future<T> Function(String accessToken) action,
  ) async {
    final current = _session;
    if (current == null) {
      throw const ApiException('登录状态已失效');
    }

    try {
      return await action(current.accessToken);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        rethrow;
      }

      final refreshed = await refreshSession();
      if (refreshed == null) {
        rethrow;
      }
      return action(refreshed.accessToken);
    }
  }

  Future<Session?> refreshSession() {
    _refreshInFlight ??= _refreshSessionInternal().whenComplete(() {
      _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }

  Future<void> _restoreSession() async {
    try {
      final stored = await _sessionStorage.readSession();
      if (stored == null) {
        _session = null;
        return;
      }

      _session = stored;
      _isBootstrapping = false;
      notifyListeners();
      unawaited(refreshSession());
      return;
    } catch (_) {
      _session = null;
      await _sessionStorage.clear();
    } finally {
      _isBootstrapping = false;
      notifyListeners();
    }
  }

  Future<Session?> _refreshSessionInternal() async {
    final current = _session;
    if (current == null) {
      return null;
    }

    try {
      final refreshed = await _apiClient.refresh(current.refreshToken);
      _session = refreshed;
      _errorMessage = null;
      await _sessionStorage.saveSession(refreshed);
      notifyListeners();
      return refreshed;
    } on ApiException {
      _session = null;
      await _sessionStorage.clear();
      notifyListeners();
      return null;
    }
  }

  void _setWorking(bool value) {
    _isWorking = value;
    if (value) {
      _errorMessage = null;
    }
    notifyListeners();
  }
}
