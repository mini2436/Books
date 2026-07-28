import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'data/services/server_config_storage.dart';
import 'features/settings/server_config_controller.dart';
import 'shared/localization/app_locale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final serverConfigStorage = ServerConfigStorage();
  final initialServerAddress = await serverConfigStorage.readAddress();
  final appLocaleStorage = AppLocaleStorage();
  final initialAppLanguage = await appLocaleStorage.read();

  runApp(
    ProviderScope(
      overrides: [
        serverConfigStorageProvider.overrideWithValue(serverConfigStorage),
        initialServerAddressProvider.overrideWithValue(initialServerAddress),
        appLocaleStorageProvider.overrideWithValue(appLocaleStorage),
        initialAppLanguageProvider.overrideWithValue(initialAppLanguage),
      ],
      child: const ReaderApp(),
    ),
  );
}
