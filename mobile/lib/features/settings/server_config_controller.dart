import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/api_client.dart';
import '../../data/services/server_config_storage.dart';
import '../../shared/config/app_config.dart';
import '../auth/auth_controller.dart';

final serverConfigStorageProvider = Provider<ServerConfigStorage>(
  (ref) => ServerConfigStorage(),
);

final initialServerAddressProvider = Provider<String>(
  (ref) => AppConfig.defaultServerAddress,
);

final serverConfigControllerProvider =
    ChangeNotifierProvider<ServerConfigController>((ref) {
      return ServerConfigController(
        apiClient: ref.watch(apiClientProvider),
        storage: ref.watch(serverConfigStorageProvider),
        initialAddress: ref.watch(initialServerAddressProvider),
      );
    });

class ServerConfigController extends ChangeNotifier {
  ServerConfigController({
    required ApiClient apiClient,
    required ServerConfigStorage storage,
    required String initialAddress,
  }) : _apiClient = apiClient,
       _storage = storage,
       _serverAddress = AppConfig.normalizeAddress(initialAddress) {
    _apiClient.updateBaseUrl(baseUrl);
  }

  final ApiClient _apiClient;
  final ServerConfigStorage _storage;

  String _serverAddress;
  bool _isSaving = false;
  String? _errorMessage;

  String get serverAddress => _serverAddress;
  String get baseUrl => AppConfig.normalizeBaseUrl(_serverAddress);
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  Future<void> updateAddress(String value) async {
    final normalizedAddress = AppConfig.normalizeAddress(value);
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _serverAddress = normalizedAddress;
      _apiClient.updateBaseUrl(baseUrl);
      await _storage.saveAddress(normalizedAddress);
    } catch (_) {
      _errorMessage = '保存服务地址失败';
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
