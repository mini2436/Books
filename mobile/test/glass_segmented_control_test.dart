import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/shared/theme/reader_theme_extension.dart';
import 'package:private_reader_mobile/shared/widgets/glass_segmented_control.dart';

void main() {
  testWidgets('允许在滚动区域关闭实时背景模糊', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [AppReaderPalette.resolve(ReaderThemeMode.paper)],
        ),
        home: Scaffold(
          body: GlassSegmentedControl<int>(
            blur: false,
            segments: const [
              ButtonSegment(value: 1, label: Text('全部')),
              ButtonSegment(value: 2, label: Text('分组')),
            ],
            selected: const {1},
            onSelectionChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
  });
}
