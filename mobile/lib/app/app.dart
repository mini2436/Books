import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/settings/reader_preferences_controller.dart';
import '../shared/theme/app_theme.dart';
import 'router.dart';

class ReaderApp extends ConsumerWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncCoordinatorProvider);
    final router = ref.watch(routerProvider);
    final preferences = ref.watch(readerPreferencesControllerProvider).value;

    return MaterialApp.router(
      title: 'Private Reader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(preferences),
      routerConfig: router,
    );
  }
}
