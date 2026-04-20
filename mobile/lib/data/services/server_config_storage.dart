import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/config/app_config.dart';

class ServerConfigStorage {
  static const String _serverAddressKey = 'server.address';

  Future<String> readAddress() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_serverAddressKey);
    return AppConfig.normalizeAddress(stored ?? AppConfig.defaultServerAddress);
  }

  Future<void> saveAddress(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _serverAddressKey,
      AppConfig.normalizeAddress(value),
    );
  }
}
