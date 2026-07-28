import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/shared/localization/app_locale.dart';
import 'package:private_reader_mobile/shared/localization/app_localizations.dart';
import 'package:private_reader_mobile/shared/localization/localized_text.dart'
    as localized;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Chinese and English translations resolve static and dynamic copy', () {
    const chinese = AppLocalizations(Locale('zh', 'CN'));
    const english = AppLocalizations(Locale('en'));

    expect(chinese.tr('书架'), '书架');
    expect(english.tr('书架'), 'Library');
    expect(english.tr('12 本书'), '12 books');
    expect(english.tr('第 3 / 18 章'), 'Chapter 3 of 18');
    expect(english.tr('“Dune”已可离线阅读'), '“Dune” is available offline');
  });

  test('language preference persists across controller instances', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = AppLocaleStorage();
    final controller = AppLocaleController(storage: storage);

    await controller.setLanguage(AppLanguage.english);

    expect(controller.locale, const Locale('en'));
    expect(await storage.read(), AppLanguage.english);
  });

  testWidgets('localized text follows the active Material locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: localized.Text('登录')),
      ),
    );

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
  });
}
