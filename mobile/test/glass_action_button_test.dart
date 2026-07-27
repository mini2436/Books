import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/shared/theme/reader_theme_extension.dart';
import 'package:private_reader_mobile/shared/widgets/glass_action_button.dart';

void main() {
  testWidgets('GlassActionButton invokes its action', (tester) async {
    var pressed = false;

    await tester.pumpWidget(
      _testApp(
        GlassActionButton(
          label: '添加用户',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => pressed = true,
        ),
      ),
    );

    await tester.tap(find.text('添加用户'));

    expect(pressed, isTrue);
  });

  testWidgets('GlassActionButton shows loading state and blocks taps', (
    tester,
  ) async {
    var pressCount = 0;

    await tester.pumpWidget(
      _testApp(
        GlassActionButton(
          label: '重建结构化正文',
          loadingLabel: '正在重建...',
          icon: Icons.refresh_rounded,
          loading: true,
          onPressed: () => pressCount += 1,
        ),
      ),
    );

    expect(find.text('正在重建...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('正在重建...'));

    expect(pressCount, 0);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      extensions: [AppReaderPalette.resolve(ReaderThemeMode.paper)],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}
