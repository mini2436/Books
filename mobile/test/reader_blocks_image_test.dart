import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/features/reader/widgets/reader_blocks.dart';
import 'package:private_reader_mobile/features/reader/models/annotation_anchor.dart';
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
          onRetryImages: () async {},
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
          onRetryImages: () async {},
        ),
      ),
    );

    expect(find.text('图片无法加载'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('ReaderBlocksView lays image pages out in two columns', (
    tester,
  ) async {
    const blocks = [
      BookContentBlock(
        blockIndex: 0,
        type: 'image',
        anchor: 'chapter-0-block-1',
        text: '',
        plainText: '',
        meta: {
          'resourceId': 'image-1',
          'mediaType': 'image/png',
          'width': 1,
          'height': 1,
        },
      ),
      BookContentBlock(
        blockIndex: 1,
        type: 'image',
        anchor: 'chapter-0-block-2',
        text: '',
        plainText: '',
        meta: {
          'resourceId': 'image-2',
          'mediaType': 'image/png',
          'width': 1,
          'height': 1,
        },
      ),
    ];
    final anchorKeys = <String, GlobalKey>{};

    await tester.pumpWidget(
      _testApp(
        SizedBox(
          width: 760,
          child: ReaderBlocksView(
            blocks: blocks,
            imageResources: {'image-1': _onePixelPng, 'image-2': _onePixelPng},
            failedImageResourceIds: const {},
            constrainImagesToViewport: true,
            annotations: const <AnnotationView>[],
            preferences: _preferences,
            keyForAnchor: (anchor) =>
                anchorKeys.putIfAbsent(anchor, GlobalKey.new),
            onHighlight: (_, _) async {},
            onAnnotate: (_, _) async {},
            onOpenAnnotations: (_) async {},
            onRetryImages: () async {},
            twoColumnContent: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstPosition = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-1']!),
    );
    final secondPosition = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-2']!),
    );
    expect(secondPosition.dx, greaterThan(firstPosition.dx));
    expect(secondPosition.dy, firstPosition.dy);
  });

  testWidgets('ReaderBlocksView keeps mixed text with its following image', (
    tester,
  ) async {
    const blocks = [
      BookContentBlock(
        blockIndex: 0,
        type: 'paragraph',
        anchor: 'chapter-0-block-1',
        text: '左栏说明',
        plainText: '左栏说明',
        meta: {},
      ),
      BookContentBlock(
        blockIndex: 1,
        type: 'image',
        anchor: 'chapter-0-block-2',
        text: '',
        plainText: '',
        meta: {
          'resourceId': 'image-1',
          'mediaType': 'image/png',
          'width': 1,
          'height': 1,
        },
      ),
      BookContentBlock(
        blockIndex: 2,
        type: 'paragraph',
        anchor: 'chapter-0-block-3',
        text: '右栏说明',
        plainText: '右栏说明',
        meta: {},
      ),
      BookContentBlock(
        blockIndex: 3,
        type: 'image',
        anchor: 'chapter-0-block-4',
        text: '',
        plainText: '',
        meta: {
          'resourceId': 'image-2',
          'mediaType': 'image/png',
          'width': 1,
          'height': 1,
        },
      ),
    ];
    final anchorKeys = <String, GlobalKey>{};

    await tester.pumpWidget(
      _testApp(
        SizedBox(
          width: 760,
          child: ReaderBlocksView(
            blocks: blocks,
            imageResources: {'image-1': _onePixelPng, 'image-2': _onePixelPng},
            failedImageResourceIds: const {},
            constrainImagesToViewport: true,
            annotations: const <AnnotationView>[],
            preferences: _preferences,
            keyForAnchor: (anchor) =>
                anchorKeys.putIfAbsent(anchor, GlobalKey.new),
            onHighlight: (_, _) async {},
            onAnnotate: (_, _) async {},
            onOpenAnnotations: (_) async {},
            onRetryImages: () async {},
            twoColumnContent: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final leftText = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-1']!),
    );
    final leftImage = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-2']!),
    );
    final rightText = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-3']!),
    );
    final rightImage = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-4']!),
    );
    expect(leftImage.dx, leftText.dx);
    expect(rightImage.dx, rightText.dx);
    expect(rightText.dx, greaterThan(leftText.dx));
    expect(rightText.dy, leftText.dy);
  });

  testWidgets('paged columns fill remaining space below landscape images', (
    tester,
  ) async {
    const blocks = [
      BookContentBlock(
        blockIndex: 0,
        type: 'image',
        anchor: 'chapter-0-block-1',
        text: '',
        plainText: '',
        meta: {
          'resourceId': 'image-1',
          'mediaType': 'image/png',
          'width': 2,
          'height': 1,
        },
      ),
      BookContentBlock(
        blockIndex: 1,
        type: 'paragraph',
        anchor: 'chapter-0-block-2',
        text: '图片下方的连续文字',
        plainText: '图片下方的连续文字',
        meta: {},
      ),
      BookContentBlock(
        blockIndex: 2,
        type: 'image',
        anchor: 'chapter-0-block-3',
        text: '',
        plainText: '',
        meta: {
          'resourceId': 'image-2',
          'mediaType': 'image/png',
          'width': 1,
          'height': 1,
        },
      ),
    ];
    final anchorKeys = <String, GlobalKey>{};

    await tester.pumpWidget(
      _testApp(
        SizedBox(
          width: 760,
          height: 500,
          child: ReaderBlocksView(
            blocks: blocks,
            imageResources: {'image-1': _onePixelPng, 'image-2': _onePixelPng},
            failedImageResourceIds: const {},
            constrainImagesToViewport: true,
            annotations: const <AnnotationView>[],
            preferences: _preferences,
            keyForAnchor: (anchor) =>
                anchorKeys.putIfAbsent(anchor, GlobalKey.new),
            onHighlight: (_, _) async {},
            onAnnotate: (_, _) async {},
            onOpenAnnotations: (_) async {},
            pagedViewportWidth: 760,
            pagedColumnHeight: 500,
            pagedColumnCount: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstImage = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-1']!),
    );
    final paragraph = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-2']!),
    );
    final secondImage = tester.getTopLeft(
      find.byKey(anchorKeys['chapter-0-block-3']!),
    );
    expect(paragraph.dx, firstImage.dx);
    expect(paragraph.dy, greaterThan(firstImage.dy));
    expect(secondImage.dx, greaterThan(firstImage.dx));
    expect(secondImage.dy, firstImage.dy);
  });

  testWidgets('ReaderBlocksView shows annotation actions after selection', (
    tester,
  ) async {
    const block = BookContentBlock(
      blockIndex: 0,
      type: 'paragraph',
      anchor: 'chapter-0-block-1',
      text: '选择这段文字进行批注',
      plainText: '选择这段文字进行批注',
      meta: {},
    );
    AnnotationSelection? highlightedSelection;

    await tester.pumpWidget(
      _testApp(
        ReaderBlocksView(
          blocks: const [block],
          imageResources: const {},
          failedImageResourceIds: const {},
          constrainImagesToViewport: false,
          annotations: const <AnnotationView>[],
          preferences: _preferences,
          keyForAnchor: (_) => GlobalKey(),
          onHighlight: (selection, _) async {
            highlightedSelection = selection;
          },
          onAnnotate: (_, _) async {},
          onOpenAnnotations: (_) async {},
          onRetryImages: () async {},
        ),
      ),
    );

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    selectable.onSelectionChanged!(
      const TextSelection(baseOffset: 0, extentOffset: 4),
      SelectionChangedCause.drag,
    );
    await tester.pump();

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('高亮'), findsOneWidget);
    expect(find.text('批注'), findsOneWidget);

    await tester.tap(find.text('高亮'));
    await tester.pump();

    expect(highlightedSelection?.selectedText, '选择这段');
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('explicit annotation opens only from its painted text', (
    tester,
  ) async {
    const block = BookContentBlock(
      blockIndex: 0,
      type: 'paragraph',
      anchor: 'chapter-0-block-annotation',
      text: '点击这段批注文字',
      plainText: '点击这段批注文字',
      meta: {},
    );
    final blockKey = GlobalKey();
    final openedAnnotations = <AnnotationView>[];
    final annotation = AnnotationView(
      id: 7,
      bookId: 1,
      quoteText: block.text,
      noteText: '测试批注',
      color: '#7A4A24',
      anchor: const AnnotationAnchor(
        blockAnchor: 'chapter-0-block-annotation',
        startOffset: 0,
        endOffset: 8,
        underlineStyle: AnnotationUnderlineStyle.wavy,
      ).serialize(),
      version: 1,
      deleted: false,
      updatedAt: '',
    );

    await tester.pumpWidget(
      _testApp(
        ReaderBlocksView(
          blocks: const [block],
          imageResources: const {},
          failedImageResourceIds: const {},
          constrainImagesToViewport: false,
          annotations: [annotation],
          preferences: _preferences,
          keyForAnchor: (_) => blockKey,
          onHighlight: (_, _) async {},
          onAnnotate: (_, _) async {},
          onOpenAnnotations: (annotations) async {
            openedAnnotations.addAll(annotations);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textRect = tester.getRect(find.byType(SelectableText));
    await tester.tapAt(textRect.center);
    await tester.pump();
    expect(openedAnnotations.map((item) => item.id), [7]);

    openedAnnotations.clear();
    final blockRect = tester.getRect(find.byKey(blockKey));
    await tester.tapAt(Offset(blockRect.center.dx, blockRect.bottom - 2));
    await tester.pump();
    expect(openedAnnotations, isEmpty);

    await tester.dragFrom(textRect.center, const Offset(40, 0));
    await tester.pump();
    expect(openedAnnotations, isEmpty);
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
