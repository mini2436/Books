import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/features/reader/widgets/reader_blocks.dart';
import 'package:private_reader_mobile/features/settings/reader_preferences_controller.dart';
import 'package:private_reader_mobile/shared/theme/reader_theme_extension.dart';

void main() {
  testWidgets('ReaderBlocksView renders image blocks with captions', (
    tester,
  ) async {
    const block = BookContentBlock(
      blockIndex: 0,
      type: 'image',
      anchor: 'chapter-0-block-1',
      text: 'A caption',
      plainText: 'A caption',
      meta: {
        'resourceId': 'image-1',
        'mediaType': 'image/png',
        'alt': 'A picture',
        'caption': 'A caption',
        'width': 1,
        'height': 1,
      },
    );

    await tester.pumpWidget(
      _testApp(
        ReaderBlocksView(
          blocks: const [block],
          imageResources: {'image-1': _onePixelPng},
          failedImageResourceIds: const {},
          constrainImagesToViewport: false,
          annotations: const <AnnotationView>[],
          preferences: _preferences,
          keyForAnchor: (_) => GlobalKey(),
          onHighlight: (_, _) async {},
          onAnnotate: (_, _) async {},
          onOpenAnnotations: (_) async {},
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('A caption'), findsOneWidget);
  });

  testWidgets('ReaderBlocksView renders a failed image placeholder', (
    tester,
  ) async {
    const block = BookContentBlock(
      blockIndex: 0,
      type: 'image',
      anchor: 'chapter-0-block-1',
      text: '',
      plainText: '',
      meta: {'resourceId': 'missing-image'},
    );

    await tester.pumpWidget(
      _testApp(
        ReaderBlocksView(
          blocks: const [block],
          imageResources: const {},
          failedImageResourceIds: const {'missing-image'},
          constrainImagesToViewport: false,
          annotations: const <AnnotationView>[],
          preferences: _preferences,
          keyForAnchor: (_) => GlobalKey(),
          onHighlight: (_, _) async {},
          onAnnotate: (_, _) async {},
          onOpenAnnotations: (_) async {},
        ),
      ),
    );

    expect(find.text('图片无法加载'), findsOneWidget);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      extensions: [AppReaderPalette.resolve(ReaderThemeMode.paper)],
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

const ReaderPreferences _preferences = ReaderPreferences(
  themeMode: ReaderThemeMode.paper,
  fontScale: 1,
  lineHeight: 1.8,
  fontFamily: ReaderFontFamilyPreference.system,
  tabletPageTurnAxis: TabletPageTurnAxis.horizontal,
  tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
);

final Uint8List _onePixelPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
