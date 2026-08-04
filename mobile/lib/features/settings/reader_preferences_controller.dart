import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/settings_storage.dart';
import '../../shared/theme/glass_theme.dart';
import '../../shared/theme/reader_theme_extension.dart';

enum ReaderFontFamilyPreference {
  system,
  sans,
  serif,
  miSans,
  sourceHanSerif,
  wenKai,
}

enum TabletPageTurnAnimation { smooth }

enum ReaderColumnLayout { single, double }

enum ReaderRenderingEngine { flutter, webView }

bool supportsReaderRenderingEngineSelection(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.windows;

bool usesFlutterReaderOnPlatform({
  required bool isWeb,
  required TargetPlatform platform,
  required ReaderRenderingEngine preference,
}) {
  if (isWeb ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS) {
    return true;
  }
  return supportsReaderRenderingEngineSelection(platform) &&
      preference == ReaderRenderingEngine.flutter;
}

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
      case ReaderFontFamilyPreference.miSans:
        return 'MiSans';
      case ReaderFontFamilyPreference.sourceHanSerif:
        return 'SourceHanSerifSC';
      case ReaderFontFamilyPreference.wenKai:
        return 'LXGWWenKai';
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
      case ReaderFontFamilyPreference.miSans:
        return 'MiSans';
      case ReaderFontFamilyPreference.sourceHanSerif:
        return '思源宋体';
      case ReaderFontFamilyPreference.wenKai:
        return '霞鹜文楷';
    }
  }

  String? get assetPath {
    return switch (this) {
      ReaderFontFamilyPreference.miSans => 'assets/fonts/MiSans-Regular.ttf',
      ReaderFontFamilyPreference.sourceHanSerif =>
        'assets/fonts/SourceHanSerifSC-Regular.otf',
      ReaderFontFamilyPreference.wenKai =>
        'assets/fonts/LXGWWenKai-Regular.ttf',
      _ => null,
    };
  }

  String? get licenseNotice {
    return switch (this) {
      ReaderFontFamilyPreference.miSans =>
        '本软件内置使用小米 MiSans 字体，依据 MiSans 字体知识产权许可协议使用。',
      ReaderFontFamilyPreference.sourceHanSerif =>
        '本软件内置使用 Adobe 思源宋体，依据 SIL Open Font License 1.1 使用。',
      ReaderFontFamilyPreference.wenKai =>
        '本软件内置使用霞鹜文楷，依据 SIL Open Font License 1.1 使用。',
      _ => null,
    };
  }

  static ReaderFontFamilyPreference fromStorage(String? value) {
    return ReaderFontFamilyPreference.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ReaderFontFamilyPreference.system,
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

extension ReaderColumnLayoutX on ReaderColumnLayout {
  String get storageValue => name;

  String get label => switch (this) {
    ReaderColumnLayout.single => '单栏',
    ReaderColumnLayout.double => '双栏',
  };

  static ReaderColumnLayout fromStorage(String? value) {
    return ReaderColumnLayout.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ReaderColumnLayout.double,
    );
  }
}

extension ReaderRenderingEngineX on ReaderRenderingEngine {
  String get storageValue => name;

  static ReaderRenderingEngine fromStorage(String? value) {
    return ReaderRenderingEngine.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ReaderRenderingEngine.flutter,
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
    required this.tabletPageTurnAnimation,
    this.columnLayout = ReaderColumnLayout.double,
    this.glassMaterialMode = GlassMaterialMode.lightweight,
    this.renderingEngine = ReaderRenderingEngine.flutter,
    this.pageMarginScale = 1,
  });

  final ReaderThemeMode themeMode;
  final double fontScale;
  final double lineHeight;
  final ReaderFontFamilyPreference fontFamily;
  final TabletPageTurnAnimation tabletPageTurnAnimation;
  final ReaderColumnLayout columnLayout;
  final GlassMaterialMode glassMaterialMode;
  final ReaderRenderingEngine renderingEngine;
  final double pageMarginScale;

  ReaderPreferences copyWith({
    ReaderThemeMode? themeMode,
    double? fontScale,
    double? lineHeight,
    ReaderFontFamilyPreference? fontFamily,
    TabletPageTurnAnimation? tabletPageTurnAnimation,
    ReaderColumnLayout? columnLayout,
    GlassMaterialMode? glassMaterialMode,
    ReaderRenderingEngine? renderingEngine,
    double? pageMarginScale,
  }) {
    return ReaderPreferences(
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      tabletPageTurnAnimation:
          tabletPageTurnAnimation ?? this.tabletPageTurnAnimation,
      columnLayout: columnLayout ?? this.columnLayout,
      glassMaterialMode: glassMaterialMode ?? this.glassMaterialMode,
      renderingEngine: renderingEngine ?? this.renderingEngine,
      pageMarginScale: pageMarginScale ?? this.pageMarginScale,
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
    tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
    columnLayout: ReaderColumnLayout.double,
    glassMaterialMode: GlassMaterialMode.lightweight,
  );

  ReaderPreferences get value => _preferences;
  ReaderThemeMode get themeMode => _preferences.themeMode;
  double get fontScale => _preferences.fontScale;
  double get lineHeight => _preferences.lineHeight;
  ReaderFontFamilyPreference get fontFamily => _preferences.fontFamily;
  TabletPageTurnAnimation get tabletPageTurnAnimation =>
      _preferences.tabletPageTurnAnimation;
  ReaderColumnLayout get columnLayout => _preferences.columnLayout;
  GlassMaterialMode get glassMaterialMode => _preferences.glassMaterialMode;
  ReaderRenderingEngine get renderingEngine => _preferences.renderingEngine;
  double get pageMarginScale => _preferences.pageMarginScale;

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

  Future<void> setTabletPageTurnAnimation(TabletPageTurnAnimation value) async {
    _preferences = _preferences.copyWith(tabletPageTurnAnimation: value);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> setColumnLayout(ReaderColumnLayout value) async {
    _preferences = _preferences.copyWith(columnLayout: value);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> setGlassMaterialMode(GlassMaterialMode value) async {
    _preferences = _preferences.copyWith(glassMaterialMode: value);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> setRenderingEngine(ReaderRenderingEngine value) async {
    _preferences = _preferences.copyWith(renderingEngine: value);
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> setPageMarginScale(double value) async {
    _preferences = _preferences.copyWith(
      pageMarginScale: value.clamp(0.5, 1.5),
    );
    notifyListeners();
    await _settingsStorage.save(_preferences);
  }

  Future<void> _load() async {
    _preferences = await _settingsStorage.read();
    notifyListeners();
  }
}
