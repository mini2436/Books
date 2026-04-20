import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'data/services/server_config_storage.dart';
import 'features/settings/server_config_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final serverConfigStorage = ServerConfigStorage();
  final initialServerAddress = await serverConfigStorage.readAddress();

  runApp(
    ProviderScope(
      overrides: [
        serverConfigStorageProvider.overrideWithValue(serverConfigStorage),
        initialServerAddressProvider.overrideWithValue(initialServerAddress),
      ],
      child: const ReaderApp(),
    ),
  );
}
