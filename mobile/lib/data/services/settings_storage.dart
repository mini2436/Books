import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/reader_preferences_controller.dart';

class SettingsStorage {
  static const String _themeKey = 'reader.theme';
  static const String _fontScaleKey = 'reader.fontScale';
  static const String _lineHeightKey = 'reader.lineHeight';
  static const String _fontFamilyKey = 'reader.fontFamily';

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
    );
  }

  Future<void> save(ReaderPreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeKey, value.themeMode.storageValue);
    await preferences.setDouble(_fontScaleKey, value.fontScale);
    await preferences.setDouble(_lineHeightKey, value.lineHeight);
    await preferences.setString(_fontFamilyKey, value.fontFamily.storageValue);
  }
}
