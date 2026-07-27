import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/auth_models.dart';
import '../../data/services/api_client.dart';
import '../../data/services/offline_queue_service.dart';
import '../../data/services/offline_book_cache_service.dart';
import '../../data/services/session_storage.dart';
import '../../data/services/sync_coordinator.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SessionStorage(),
);
final offlineQueueServiceProvider = Provider<OfflineQueueService>(
  (ref) => OfflineQueueService(),
);
final offlineBookCacheServiceProvider = Provider<OfflineBookCacheService>(
  (ref) => OfflineBookCacheService(),
);

final authControllerProvider = ChangeNotifierProvider<AuthController>(
  (ref) => AuthController(
    apiClient: ref.watch(apiClientProvider),
    sessionStorage: ref.watch(sessionStorageProvider),
    offlineBookCacheService: ref.watch(offlineBookCacheServiceProvider),
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
    required OfflineBookCacheService offlineBookCacheService,
  }) : _apiClient = apiClient,
       _sessionStorage = sessionStorage,
       _offlineBookCacheService = offlineBookCacheService {
    unawaited(_restoreSession());
  }

  final ApiClient _apiClient;
  final SessionStorage _sessionStorage;
  final OfflineBookCacheService _offlineBookCacheService;

  Session? _session;
  int? _offlineUserId;
  bool _isBootstrapping = true;
  bool _isWorking = false;
  bool _isOfflineMode = false;
  bool _isOfflineGuest = false;
  String? _errorMessage;
  Future<Session?>? _refreshInFlight;

  Session? get session => _session;
  AuthUser? get user => _session?.user;
  String? get accessToken => _session?.accessToken;
  bool get isAuthenticated => _session != null;
  bool get canAccessApp => isAuthenticated || _isOfflineGuest;
  int? get activeUserId => user?.id ?? _offlineUserId;
  bool get isBootstrapping => _isBootstrapping;
  bool get isWorking => _isWorking;
  bool get isOfflineMode => _isOfflineMode;
  bool get isOfflineGuest => _isOfflineGuest;
  String? get errorMessage => _errorMessage;

  void markServerReachable() {
    if (!_isOfflineMode || _isOfflineGuest) return;
    _isOfflineMode = false;
    notifyListeners();
  }

  void markServerUnavailable() {
    if (_isOfflineMode || _session == null) return;
    _isOfflineMode = true;
    notifyListeners();
  }

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
      _offlineUserId = null;
      _isOfflineGuest = false;
      _isOfflineMode = false;
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
    _offlineUserId = null;
    _isOfflineGuest = false;
    _isOfflineMode = false;
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

  Future<bool> enterOfflineMode() async {
    _setWorking(true);
    try {
      final userId = await _offlineBookCacheService.latestCachedUserId();
      if (userId == null) {
        _errorMessage = kIsWeb
            ? 'Web 端暂不支持离线书库，请在 Windows 或移动端使用离线阅读。'
            : '当前设备还没有离线缓存，请先登录并下载书籍。';
        return false;
      }
      _session = null;
      _offlineUserId = userId;
      _isOfflineGuest = true;
      _isOfflineMode = true;
      _errorMessage = null;
      return true;
    } catch (_) {
      _errorMessage = '无法读取本地离线书库，请稍后重试。';
      return false;
    } finally {
      _setWorking(false);
    }
  }

  void exitOfflineMode() {
    if (!_isOfflineGuest) return;
    _offlineUserId = null;
    _isOfflineGuest = false;
    _isOfflineMode = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> updateDisplayName(String value) async {
    _setWorking(true);
    try {
      final normalized = value.trim().isEmpty ? null : value.trim();
      final user = await runAuthorized(
        (token) => _apiClient.updateMyProfile(token, displayName: normalized),
      );
      await _replaceSessionUser(user);
    } finally {
      _setWorking(false);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _setWorking(true);
    try {
      await runAuthorized(
        (token) => _apiClient.changeMyPassword(
          token,
          currentPassword: currentPassword,
          newPassword: newPassword,
        ),
      );
    } finally {
      _setWorking(false);
    }
  }

  Future<void> uploadAvatar({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    _setWorking(true);
    try {
      final user = await runAuthorized(
        (token) => _apiClient.uploadMyAvatar(
          token,
          filePath: filePath,
          fileBytes: fileBytes,
          fileName: fileName,
        ),
      );
      await _replaceSessionUser(user);
    } finally {
      _setWorking(false);
    }
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
      if (!error.isAuthenticationFailure) {
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
    Session? stored;
    try {
      stored = await _sessionStorage.readSession();
    } catch (_) {
      stored = null;
    }

    _session = stored;
    _offlineUserId = null;
    _isOfflineGuest = false;
    _isOfflineMode = stored != null;
    _errorMessage = null;
    _isBootstrapping = false;
    notifyListeners();

    if (stored != null) {
      try {
        await refreshSession();
      } catch (_) {
        // _refreshSessionInternal keeps a usable local session on network errors.
      }
    } else {
      _errorMessage = null;
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
      _isOfflineMode = false;
      _errorMessage = null;
      await _sessionStorage.saveSession(refreshed);
      notifyListeners();
      return refreshed;
    } on ApiException catch (error) {
      if (error.isNetworkFailure) {
        _isOfflineMode = true;
        notifyListeners();
        return null;
      }
      _session = null;
      _isOfflineMode = false;
      _errorMessage = '登录状态已过期，请重新登录。';
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

  Future<void> _replaceSessionUser(AuthUser user) async {
    final current = _session;
    if (current == null) {
      return;
    }
    final next = Session(
      accessToken: current.accessToken,
      refreshToken: current.refreshToken,
      user: user,
    );
    _session = next;
    _errorMessage = null;
    await _sessionStorage.saveSession(next);
    notifyListeners();
  }
}
