import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  chinese(Locale('zh', 'CN')),
  english(Locale('en'));

  const AppLanguage(this.locale);

  final Locale locale;

  String get languageCode => locale.languageCode;

  static AppLanguage fromLocale(Locale locale) {
    return locale.languageCode == 'en'
        ? AppLanguage.english
        : AppLanguage.chinese;
  }

  static AppLanguage? fromStorage(String? value) {
    return switch (value) {
      'zh' => AppLanguage.chinese,
      'en' => AppLanguage.english,
      _ => null,
    };
  }
}

class AppLocaleStorage {
  static const _key = 'app.language';

  Future<AppLanguage?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return AppLanguage.fromStorage(preferences.getString(_key));
  }

  Future<void> write(AppLanguage language) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, language.languageCode);
  }
}

final appLocaleStorageProvider = Provider<AppLocaleStorage>(
  (ref) => AppLocaleStorage(),
);

final initialAppLanguageProvider = Provider<AppLanguage?>((ref) => null);

final appLocaleControllerProvider = ChangeNotifierProvider<AppLocaleController>(
  (ref) => AppLocaleController(
    storage: ref.watch(appLocaleStorageProvider),
    initialLanguage: ref.watch(initialAppLanguageProvider),
  ),
);

class AppLocaleController extends ChangeNotifier {
  AppLocaleController({
    required AppLocaleStorage storage,
    AppLanguage? initialLanguage,
  }) : _storage = storage,
       _language = initialLanguage;

  final AppLocaleStorage _storage;
  AppLanguage? _language;

  AppLanguage? get language => _language;
  Locale? get locale => _language?.locale;

  AppLanguage effectiveLanguage(BuildContext context) {
    return _language ?? AppLanguage.fromLocale(Localizations.localeOf(context));
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    await _storage.write(language);
  }
}
