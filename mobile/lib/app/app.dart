import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/settings/reader_preferences_controller.dart';
import '../features/settings/server_config_controller.dart';
import '../shared/localization/app_locale.dart';
import '../shared/localization/app_localizations.dart';
import '../shared/theme/app_theme.dart';
import 'router.dart';

class ReaderApp extends ConsumerWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(serverConfigControllerProvider);
    ref.watch(syncCoordinatorProvider);
    final router = ref.watch(routerProvider);
    final preferences = ref.watch(readerPreferencesControllerProvider).value;
    final appLocale = ref.watch(appLocaleControllerProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.tr('轻阅'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(preferences),
      locale: appLocale.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
