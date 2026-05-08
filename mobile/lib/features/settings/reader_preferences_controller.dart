import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/settings_storage.dart';
import '../../shared/theme/reader_theme_extension.dart';

enum ReaderFontFamilyPreference { system, sans, serif }

enum TabletPageTurnAxis { horizontal, vertical }

enum TabletPageTurnAnimation { smooth }

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

extension TabletPageTurnAxisX on TabletPageTurnAxis {
  String get storageValue => name;

  String get label {
    switch (this) {
      case TabletPageTurnAxis.horizontal:
        return '左右翻页';
      case TabletPageTurnAxis.vertical:
        return '上下翻页';
    }
  }

  static TabletPageTurnAxis fromStorage(String? value) {
    return TabletPageTurnAxis.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TabletPageTurnAxis.horizontal,
    );
  }
}

extension TabletPageTurnAnimationX on TabletPageTurnAnimation {
  String get storageValue => name;

  String get label {
    switch (this) {
      case TabletPageTurnAnimation.smooth:
        return '平滑翻页';
    }
  }

  static TabletPageTurnAnimation fromStorage(String? value) {
    return TabletPageTurnAnimation.values.firstWhere(
      (item) => item.name == value,
      orElse: () => TabletPageTurnAnimation.smooth,
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
    required this.tabletPageTurnAxis,
    required this.tabletPageTurnAnimation,
  });

  final ReaderThemeMode themeMode;
  final double fontScale;
  final double lineHeight;
  final ReaderFontFamilyPreference fontFamily;
  final TabletPageTurnAxis tabletPageTurnAxis;
  final TabletPageTurnAnimation tabletPageTurnAnimation;

  ReaderPreferences copyWith({
    ReaderThemeMode? themeMode,
    double? fontScale,
    double? lineHeight,
    ReaderFontFamilyPreference? fontFamily,
    TabletPageTurnAxis? tabletPageTurnAxis,
    TabletPageTurnAnimation? tabletPageTurnAnimation,
  }) {
    return ReaderPreferences(
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      tabletPageTurnAxis: tabletPageTurnAxis ?? this.tabletPageTurnAxis,
      tabletPageTurnAnimation:
          tabletPageTurnAnimation ?? this.tabletPageTurnAnimation,
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
    tabletPageTurnAxis: TabletPageTurnAxis.horizontal,
    tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
  );

  ReaderPreferences get value => _preferences;
  ReaderThemeMode get themeMode => _preferences.themeMode;
  double get fontScale => _preferences.fontScale;
  double get lineHeight => _preferences.lineHeight;
  ReaderFontFamilyPreference get fontFamily => _preferences.fontFamily;
  TabletPageTurnAxis get tabletPageTurnAxis => _preferences.tabletPageTurnAxis;
  TabletPageTurnAnimation get tabletPageTurnAnimation =>
      _preferences.tabletPageTurnAnimation;

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

  Future<void> setTabletPageTurnAxis(TabletPageTurnAxis value) async {
    _preferences = _preferences.copyWith(tabletPageTurnAxis: value);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> setTabletPageTurnAnimation(TabletPageTurnAnimation value) async {
    _preferences = _preferences.copyWith(tabletPageTurnAnimation: value);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> _load() async {
    _preferences = await _settingsStorage.read();
    notifyListeners();
  }
}
