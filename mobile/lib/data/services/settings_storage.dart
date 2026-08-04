import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/reader_preferences_controller.dart';
import '../../shared/theme/glass_theme.dart';

class SettingsStorage {
  static const String _themeKey = 'reader.theme';
  static const String _fontScaleKey = 'reader.fontScale';
  static const String _lineHeightKey = 'reader.lineHeight';
  static const String _fontFamilyKey = 'reader.fontFamily';
  static const String _legacyTabletPageTurnAxisKey =
      'reader.tabletPageTurnAxis';
  static const String _tabletPageTurnAnimationKey =
      'reader.tabletPageTurnAnimation';
  static const String _columnLayoutKey = 'reader.columnLayout';
  static const String _glassMaterialModeKey = 'ui.glassMaterialMode';
  static const String _renderingEngineKey = 'reader.renderingEngine';
  static const String _pageMarginScaleKey = 'reader.pageMarginScale';

  Future<ReaderPreferences> read() async {
    final preferences = await SharedPreferences.getInstance();
    return ReaderPreferences(
      themeMode: ReaderThemePreferenceX.fromStorage(
        preferences.getString(_themeKey),
      ),
      fontScale: preferences.getDouble(_fontScaleKey) ?? 1,
      lineHeight: preferences.getDouble(_lineHeightKey) ?? 1.8,
      fontFamily: ReaderFontFamilyPreferenceX.fromStorage(
        preferences.getString(_fontFamilyKey),
      ),
      tabletPageTurnAnimation: TabletPageTurnAnimationX.fromStorage(
        preferences.getString(_tabletPageTurnAnimationKey),
      ),
      columnLayout: ReaderColumnLayoutX.fromStorage(
        preferences.getString(_columnLayoutKey),
      ),
      glassMaterialMode: GlassMaterialModeX.fromStorage(
        preferences.getString(_glassMaterialModeKey),
      ),
      renderingEngine: ReaderRenderingEngineX.fromStorage(
        preferences.getString(_renderingEngineKey),
      ),
      pageMarginScale: (preferences.getDouble(_pageMarginScaleKey) ?? 1)
          .clamp(0.5, 1.5)
          .toDouble(),
    );
  }

  Future<void> save(ReaderPreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeKey, value.themeMode.storageValue);
    await preferences.setDouble(_fontScaleKey, value.fontScale);
    await preferences.setDouble(_lineHeightKey, value.lineHeight);
    await preferences.setString(_fontFamilyKey, value.fontFamily.storageValue);
    await preferences.remove(_legacyTabletPageTurnAxisKey);
    await preferences.setString(
      _tabletPageTurnAnimationKey,
      value.tabletPageTurnAnimation.storageValue,
    );
    await preferences.setString(
      _columnLayoutKey,
      value.columnLayout.storageValue,
    );
    await preferences.setString(
      _glassMaterialModeKey,
      value.glassMaterialMode.storageValue,
    );
    await preferences.setString(
      _renderingEngineKey,
      value.renderingEngine.storageValue,
    );
    await preferences.setDouble(_pageMarginScaleKey, value.pageMarginScale);
  }
}
