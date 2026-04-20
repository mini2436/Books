import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/settings_storage.dart';
import '../../shared/theme/reader_theme_extension.dart';

enum ReaderFontFamilyPreference { system, sans, serif }

extension ReaderThemePreferenceX on ReaderThemeMode {
  String get storageValue => name;

  static ReaderThemeMode fromStorage(String? value) {
    return ReaderThemeMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ReaderThemeMode.paper,
    );
  }
}

extension ReaderFontFamilyPreferenceX on ReaderFontFamilyPreference {
  String get storageValue => name;

  String? get fontFamily {
    switch (this) {
      case ReaderFontFamilyPreference.system:
        return null;
      case ReaderFontFamilyPreference.sans:
        return 'sans-serif';
      case ReaderFontFamilyPreference.serif:
        return 'serif';
    }
  }

  String get label {
    switch (this) {
      case ReaderFontFamilyPreference.system:
        return '系统默认';
      case ReaderFontFamilyPreference.sans:
        return '清晰黑体';
      case ReaderFontFamilyPreference.serif:
        return '阅读衬线';
    }
  }

  static ReaderFontFamilyPreference fromStorage(String? value) {
    return ReaderFontFamilyPreference.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ReaderFontFamilyPreference.system,
    );
  }
}

@immutable
class ReaderPreferences {
  const ReaderPreferences({
    required this.themeMode,
    required this.fontScale,
    required this.lineHeight,
    required this.fontFamily,
  });

  final ReaderThemeMode themeMode;
  final double fontScale;
  final double lineHeight;
  final ReaderFontFamilyPreference fontFamily;

  ReaderPreferences copyWith({
    ReaderThemeMode? themeMode,
    double? fontScale,
    double? lineHeight,
    ReaderFontFamilyPreference? fontFamily,
  }) {
    return ReaderPreferences(
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

final settingsStorageProvider = Provider<SettingsStorage>(
  (ref) => SettingsStorage(),
);

final readerPreferencesControllerProvider =
    ChangeNotifierProvider<ReaderPreferencesController>(
      (ref) => ReaderPreferencesController(ref.watch(settingsStorageProvider)),
    );

class ReaderPreferencesController extends ChangeNotifier {
  ReaderPreferencesController(this._settingsStorage) {
    _load();
  }

  final SettingsStorage _settingsStorage;

  ReaderPreferences _preferences = const ReaderPreferences(
    themeMode: ReaderThemeMode.paper,
    fontScale: 1,
    lineHeight: 1.8,
    fontFamily: ReaderFontFamilyPreference.system,
  );

  ReaderPreferences get value => _preferences;
  ReaderThemeMode get themeMode => _preferences.themeMode;
  double get fontScale => _preferences.fontScale;
  double get lineHeight => _preferences.lineHeight;
  ReaderFontFamilyPreference get fontFamily => _preferences.fontFamily;

  Future<void> setThemeMode(ReaderThemeMode mode) async {
    _preferences = _preferences.copyWith(themeMode: mode);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> setFontScale(double value) async {
    _preferences = _preferences.copyWith(fontScale: value.clamp(0.9, 1.5));
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> setLineHeight(double value) async {
    _preferences = _preferences.copyWith(lineHeight: value);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> setFontFamily(ReaderFontFamilyPreference value) async {
    _preferences = _preferences.copyWith(fontFamily: value);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> _load() async {
    _preferences = await _settingsStorage.read();
    notifyListeners();
  }
}
