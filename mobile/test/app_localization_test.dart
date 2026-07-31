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
    expect(english.tr('备份恢复'), 'Backup & restore');
    expect(english.tr('书籍 12'), 'Books 12');
    expect(english.tr('选择恢复范围'), 'Choose restore scope');
    expect(english.tr('定期备份'), 'Scheduled backups');
    expect(english.tr('备份历史'), 'Backup history');
    expect(english.tr('书籍备份已保存'), 'Book backup saved');
    expect(english.tr('用户数据备份已保存'), 'User-data backup saved');
    expect(english.tr('admin（备份文件中的用户）'), 'admin (user in backup file)');
    expect(english.tr('book（现在系统中的用户）'), 'book (user in current system)');
    expect(english.tr('导出批注'), 'Export annotations');
    expect(english.tr('液态玻璃样板'), 'Liquid Glass sample');
    expect(
      english.tr('切换应用导航与阅读工具栏的局部材质'),
      'Switch the material used by navigation and reader toolbars',
    );
    expect(
      english.tr('仅显示当前用户有批注的书籍。已选择 2 本，共 8 条批注。'),
      'Only books annotated by the current user are shown. 2 books and 8 annotations selected.',
    );
    expect(
      english.tr('已导出 2 本书的 8 条批注'),
      'Exported 8 annotations from 2 books',
    );
    expect(
      english.tr('共保留 3 份备份，可随时下载或清理。'),
      '3 backups retained. Download or clean them up at any time.',
    );
    expect(
      english.tr('将只替换已映射用户的“书签、阅读历史”。其他用户和未勾选的数据类型保持不变。'),
      'Replace only Bookmarks, Reading history for mapped users. Other users and unselected data types remain unchanged.',
    );
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
