import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/features/settings/reader_preferences_controller.dart';

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
}
