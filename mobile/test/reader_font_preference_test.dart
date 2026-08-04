import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/services/settings_storage.dart';
import 'package:private_reader_mobile/features/settings/reader_preferences_controller.dart';
import 'package:private_reader_mobile/shared/theme/glass_theme.dart';
import 'package:private_reader_mobile/shared/theme/reader_theme_extension.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('bundled reader fonts resolve to their Flutter font families', () {
    expect(ReaderFontFamilyPreference.miSans.fontFamily, 'MiSans');
    expect(ReaderFontFamilyPreference.miSans.label, 'MiSans');
    expect(
      ReaderFontFamilyPreference.miSans.assetPath,
      'assets/fonts/MiSans-Regular.ttf',
    );
    expect(
      ReaderFontFamilyPreference.sourceHanSerif.fontFamily,
      'SourceHanSerifSC',
    );
    expect(ReaderFontFamilyPreference.sourceHanSerif.label, '思源宋体');
    expect(
      ReaderFontFamilyPreference.sourceHanSerif.assetPath,
      'assets/fonts/SourceHanSerifSC-Regular.otf',
    );
    expect(ReaderFontFamilyPreference.wenKai.fontFamily, 'LXGWWenKai');
    expect(ReaderFontFamilyPreference.wenKai.label, '霞鹜文楷');
    expect(
      ReaderFontFamilyPreference.wenKai.assetPath,
      'assets/fonts/LXGWWenKai-Regular.ttf',
    );
  });

  test('bundled reader font preferences round-trip through storage', () {
    expect(
      ReaderFontFamilyPreferenceX.fromStorage('miSans'),
      ReaderFontFamilyPreference.miSans,
    );
    expect(
      ReaderFontFamilyPreferenceX.fromStorage('sourceHanSerif'),
      ReaderFontFamilyPreference.sourceHanSerif,
    );
    expect(
      ReaderFontFamilyPreferenceX.fromStorage('wenKai'),
      ReaderFontFamilyPreference.wenKai,
    );
  });

  test(
    'saving reader settings removes the legacy vertical paging option',
    () async {
      SharedPreferences.setMockInitialValues({
        'reader.tabletPageTurnAxis': 'vertical',
      });

      await SettingsStorage().save(
        const ReaderPreferences(
          themeMode: ReaderThemeMode.paper,
          fontScale: 1,
          lineHeight: 1.8,
          fontFamily: ReaderFontFamilyPreference.system,
          tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
        ),
      );

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('reader.tabletPageTurnAxis'), isFalse);
    },
  );

  test('glass material mode persists and defaults safely', () async {
    SharedPreferences.setMockInitialValues({});

    final defaults = await SettingsStorage().read();
    expect(defaults.glassMaterialMode, GlassMaterialMode.lightweight);

    await SettingsStorage().save(
      const ReaderPreferences(
        themeMode: ReaderThemeMode.paper,
        fontScale: 1,
        lineHeight: 1.8,
        fontFamily: ReaderFontFamilyPreference.system,
        tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
        glassMaterialMode: GlassMaterialMode.liquid,
      ),
    );

    final restored = await SettingsStorage().read();
    expect(restored.glassMaterialMode, GlassMaterialMode.liquid);
  });

  test('reader column layout persists and defaults to two columns', () async {
    SharedPreferences.setMockInitialValues({});

    final defaults = await SettingsStorage().read();
    expect(defaults.columnLayout, ReaderColumnLayout.double);

    await SettingsStorage().save(
      const ReaderPreferences(
        themeMode: ReaderThemeMode.paper,
        fontScale: 1,
        lineHeight: 1.8,
        fontFamily: ReaderFontFamilyPreference.system,
        tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
        columnLayout: ReaderColumnLayout.single,
      ),
    );

    final restored = await SettingsStorage().read();
    expect(restored.columnLayout, ReaderColumnLayout.single);
  });

  test('reader rendering engine defaults to Flutter and persists', () async {
    SharedPreferences.setMockInitialValues({});

    final defaults = await SettingsStorage().read();
    expect(defaults.renderingEngine, ReaderRenderingEngine.flutter);

    await SettingsStorage().save(
      const ReaderPreferences(
        themeMode: ReaderThemeMode.paper,
        fontScale: 1,
        lineHeight: 1.8,
        fontFamily: ReaderFontFamilyPreference.system,
        tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
        renderingEngine: ReaderRenderingEngine.webView,
      ),
    );

    final restored = await SettingsStorage().read();
    expect(restored.renderingEngine, ReaderRenderingEngine.webView);
  });

  test('reader page margin scale defaults safely and persists', () async {
    SharedPreferences.setMockInitialValues({});

    final defaults = await SettingsStorage().read();
    expect(defaults.pageMarginScale, 1);

    await SettingsStorage().save(
      const ReaderPreferences(
        themeMode: ReaderThemeMode.paper,
        fontScale: 1,
        lineHeight: 1.8,
        fontFamily: ReaderFontFamilyPreference.system,
        tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
        pageMarginScale: 0.75,
      ),
    );

    final restored = await SettingsStorage().read();
    expect(restored.pageMarginScale, 0.75);
  });

  test('reader rendering engine only switches Android and Windows', () {
    expect(
      usesFlutterReaderOnPlatform(
        isWeb: false,
        platform: TargetPlatform.android,
        preference: ReaderRenderingEngine.flutter,
      ),
      isTrue,
    );
    expect(
      usesFlutterReaderOnPlatform(
        isWeb: false,
        platform: TargetPlatform.android,
        preference: ReaderRenderingEngine.webView,
      ),
      isFalse,
    );
    expect(
      usesFlutterReaderOnPlatform(
        isWeb: false,
        platform: TargetPlatform.windows,
        preference: ReaderRenderingEngine.flutter,
      ),
      isTrue,
    );
    expect(
      usesFlutterReaderOnPlatform(
        isWeb: false,
        platform: TargetPlatform.windows,
        preference: ReaderRenderingEngine.webView,
      ),
      isFalse,
    );
    expect(
      usesFlutterReaderOnPlatform(
        isWeb: false,
        platform: TargetPlatform.iOS,
        preference: ReaderRenderingEngine.flutter,
      ),
      isFalse,
    );
    expect(
      usesFlutterReaderOnPlatform(
        isWeb: false,
        platform: TargetPlatform.macOS,
        preference: ReaderRenderingEngine.webView,
      ),
      isTrue,
    );
    expect(
      usesFlutterReaderOnPlatform(
        isWeb: true,
        platform: TargetPlatform.android,
        preference: ReaderRenderingEngine.webView,
      ),
      isTrue,
    );
  });
}
