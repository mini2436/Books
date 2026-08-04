import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/models/sync_models.dart';
import 'package:private_reader_mobile/features/reader/models/annotation_anchor.dart';
import 'package:private_reader_mobile/features/reader/widgets/reader_blocks.dart';
import 'package:private_reader_mobile/features/reader/widgets/reader_html_view.dart';
import 'package:private_reader_mobile/features/settings/reader_preferences_controller.dart';
import 'package:private_reader_mobile/shared/theme/reader_theme_extension.dart';

void main() {
  test('web page-turn zones grow on phone and wide viewports', () {
    expect(
      readerTapZoneForPosition(localDx: 100, viewportWidth: 400, web: true),
      'left',
    );
    expect(
      readerTapZoneForPosition(localDx: 300, viewportWidth: 400, web: true),
      'right',
    );
    expect(
      readerTapZoneForPosition(localDx: 360, viewportWidth: 1600, web: true),
      'left',
    );
    expect(
      readerTapZoneForPosition(localDx: 800, viewportWidth: 1600, web: true),
      'center',
    );
  });

  test('reader chrome does not change paged content insets', () {
    for (final twoColumnContent in [false, true]) {
      final visibleInsets = readerPagedContentInsets(
        uiVisible: true,
        twoColumnContent: twoColumnContent,
      );
      final hiddenInsets = readerPagedContentInsets(
        uiVisible: false,
        twoColumnContent: twoColumnContent,
      );

      expect(visibleInsets, hiddenInsets);
      expect(visibleInsets, const EdgeInsets.symmetric(vertical: 12));
    }
  });

  test('wide Flutter reader caps and scales horizontal page margins', () {
    expect(
      readerPagedHorizontalMargin(
        viewportWidth: 1600,
        twoColumnContent: true,
        scale: 1,
      ),
      210,
    );
    expect(
      readerPagedHorizontalMargin(
        viewportWidth: 1920,
        twoColumnContent: true,
        scale: 1,
      ),
      220,
    );
    expect(
      readerPagedHorizontalMargin(
        viewportWidth: 1920,
        twoColumnContent: true,
        scale: 0.5,
      ),
      110,
    );
    expect(
      readerPagedHorizontalMargin(
        viewportWidth: 400,
        twoColumnContent: false,
        scale: 1,
      ),
      12,
    );
  });

  test('paged text moves a fitting annotation wholly to the next page', () {
    const annotation = AnnotationTextRange(start: 8, end: 24);

    expect(
      readerAdjustedPagedSplit(
        sourceOffset: 0,
        proposedLocalEnd: 14,
        annotationRanges: const [annotation],
        fitsFreshColumn: (_) => true,
      ),
      8,
    );
    expect(
      readerAdjustedPagedSplit(
        sourceOffset: 8,
        proposedLocalEnd: 6,
        annotationRanges: const [annotation],
        fitsFreshColumn: (_) => true,
      ),
      6,
      reason: 'an annotation already starting this page may still be split',
    );
    expect(
      readerAdjustedPagedSplit(
        sourceOffset: 0,
        proposedLocalEnd: 14,
        annotationRanges: const [annotation],
        fitsFreshColumn: (_) => false,
      ),
      14,
      reason: 'annotations taller than a page must remain splittable',
    );
  });

  testWidgets('tapping selectable Flutter text toggles reader chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });

    var toggleCount = 0;
    final paragraphText = List.filled(8, '点击正文文字也应该打开阅读控制窗口。').join();
    final palette = AppReaderPalette.resolve(ReaderThemeMode.paper);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [palette]),
        home: Scaffold(
          body: ReaderHtmlView(
            chapter: BookContentChapter(
              bookId: 1,
              contentModel: 'structured',
              contentVersionId: 1,
              hasStructuredContent: true,
              chapterIndex: 0,
              title: '文字点击测试',
              anchor: 'chapter-0',
              blocks: <BookContentBlock>[
                BookContentBlock(
                  blockIndex: 0,
                  type: 'paragraph',
                  anchor: 'chapter-0-paragraph',
                  text: paragraphText,
                  plainText: paragraphText,
                  meta: {},
                ),
              ],
            ),
            imageResources: const {},
            failedImageResourceIds: const {},
            annotations: const <AnnotationView>[],
            preferences: _preferences,
            palette: palette,
            uiVisible: false,
            autoScrollEnabled: false,
            autoScrollPixelsPerSecond: 0,
            pagedMode: true,
            dualColumn: false,
            anchorJumpVersion: 0,
            onHighlight: (_, _) async {},
            onAnnotate: (_, _) async {},
            onSaveAnnotation:
                (
                  _,
                  _, {
                  required noteText,
                  required color,
                  required underlineStyle,
                }) async {},
            onOpenAnnotations: (_) async {},
            onRetryImages: () async {},
            onVisibleAnchorChanged: (_) {},
            onPageBoundaryPrevious: () async {},
            onPageBoundaryNext: () async {},
            onToggleUi: () => toggleCount += 1,
            onMenuRequest: () {},
            onAutoScrollInterrupted: () {},
            onAutoScrollBoundaryNext: () async {},
            viewportTapZoneVersion: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paragraph = find.text(paragraphText);
    expect(paragraph, findsOneWidget);
    await tester.tap(paragraph);
    await tester.pump();
    expect(toggleCount, 1);

    await tester.longPress(paragraph);
    await tester.pump();
    expect(toggleCount, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tapping a Flutter annotation does not also turn the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });

    const paragraphText = '点击这段批注只应打开编辑窗口';
    const blockAnchor = 'chapter-0-annotation';
    final annotation = AnnotationView(
      id: 9,
      bookId: 1,
      quoteText: paragraphText,
      noteText: '批注内容',
      color: '#7A4A24',
      anchor: const AnnotationAnchor(
        blockAnchor: blockAnchor,
        startOffset: 0,
        endOffset: paragraphText.length,
        underlineStyle: AnnotationUnderlineStyle.wavy,
      ).serialize(),
      version: 1,
      deleted: false,
      updatedAt: '',
    );
    var openedCount = 0;
    var toggleCount = 0;
    var boundaryTurnCount = 0;
    final palette = AppReaderPalette.resolve(ReaderThemeMode.paper);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [palette]),
        home: Scaffold(
          body: ReaderHtmlView(
            chapter: const BookContentChapter(
              bookId: 1,
              contentModel: 'structured',
              contentVersionId: 1,
              hasStructuredContent: true,
              chapterIndex: 0,
              title: '批注点击测试',
              anchor: 'chapter-0',
              blocks: <BookContentBlock>[
                BookContentBlock(
                  blockIndex: 0,
                  type: 'paragraph',
                  anchor: blockAnchor,
                  text: paragraphText,
                  plainText: paragraphText,
                  meta: {},
                ),
              ],
            ),
            imageResources: const {},
            failedImageResourceIds: const {},
            annotations: [annotation],
            preferences: _preferences,
            palette: palette,
            uiVisible: false,
            autoScrollEnabled: false,
            autoScrollPixelsPerSecond: 0,
            pagedMode: true,
            dualColumn: false,
            anchorJumpVersion: 0,
            onHighlight: (_, _) async {},
            onAnnotate: (_, _) async {},
            onSaveAnnotation:
                (
                  _,
                  _, {
                  required noteText,
                  required color,
                  required underlineStyle,
                }) async {},
            onOpenAnnotations: (_) async => openedCount += 1,
            onRetryImages: () async {},
            onVisibleAnchorChanged: (_) {},
            onPageBoundaryPrevious: () async => boundaryTurnCount += 1,
            onPageBoundaryNext: () async => boundaryTurnCount += 1,
            onToggleUi: () => toggleCount += 1,
            onMenuRequest: () {},
            onAutoScrollInterrupted: () {},
            onAutoScrollBoundaryNext: () async {},
            viewportTapZoneVersion: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(paragraphText));
    await tester.pumpAndSettle();

    expect(openedCount, 1);
    expect(toggleCount, 0);
    expect(boundaryTurnCount, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('wide text chapters use a two-column spread', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });

    final palette = AppReaderPalette.resolve(ReaderThemeMode.paper);
    final chapterText = List.filled(220, '宽屏阅读应该让正文自然填满左右两栏。').join();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [palette]),
        home: Scaffold(
          body: ReaderHtmlView(
            chapter: BookContentChapter(
              bookId: 1,
              contentModel: 'structured',
              contentVersionId: 1,
              hasStructuredContent: true,
              chapterIndex: 0,
              title: '长文本章节',
              anchor: 'chapter-0',
              blocks: [
                BookContentBlock(
                  blockIndex: 0,
                  type: 'paragraph',
                  anchor: 'chapter-0-paragraph',
                  text: chapterText,
                  plainText: chapterText,
                  meta: const {},
                ),
              ],
            ),
            imageResources: const {},
            failedImageResourceIds: const {},
            annotations: const <AnnotationView>[],
            preferences: _preferences,
            palette: palette,
            uiVisible: true,
            autoScrollEnabled: false,
            autoScrollPixelsPerSecond: 0,
            pagedMode: true,
            dualColumn: true,
            anchorJumpVersion: 0,
            onHighlight: (_, _) async {},
            onAnnotate: (_, _) async {},
            onSaveAnnotation:
                (
                  _,
                  _, {
                  required noteText,
                  required color,
                  required underlineStyle,
                }) async {},
            onOpenAnnotations: (_) async {},
            onRetryImages: () async {},
            onVisibleAnchorChanged: (_) {},
            onPageBoundaryPrevious: () async {},
            onPageBoundaryNext: () async {},
            onToggleUi: () {},
            onMenuRequest: () {},
            onAutoScrollInterrupted: () {},
            onAutoScrollBoundaryNext: () async {},
            viewportTapZoneVersion: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fragments = find.byType(SelectableText);
    expect(fragments, findsAtLeastNWidgets(2));
    final firstFragment = tester.widget<SelectableText>(fragments.first);
    expect(
      firstFragment.style?.height,
      closeTo(_preferences.lineHeight / 1.4, 0.001),
    );
    expect(firstFragment.textScaler?.scale(16), 16);
    final firstPosition = tester.getTopLeft(fragments.at(0));
    final secondPosition = tester.getTopLeft(fragments.at(1));
    expect(secondPosition.dx, greaterThan(firstPosition.dx));
    expect(secondPosition.dy, closeTo(firstPosition.dy, 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('chapter boundaries animate out and settle the next chapter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });

    final chapterIndex = ValueNotifier<int>(0);
    addTearDown(chapterIndex.dispose);
    final palette = AppReaderPalette.resolve(ReaderThemeMode.paper);
    BookContentChapter chapter(int index) {
      final text = index == 0 ? '第一章唯一一页' : '第二章第一页';
      return BookContentChapter(
        bookId: 1,
        contentModel: 'structured',
        contentVersionId: 1,
        hasStructuredContent: true,
        chapterIndex: index,
        title: '第 ${index + 1} 章',
        anchor: 'chapter-$index',
        blocks: [
          BookContentBlock(
            blockIndex: 0,
            type: 'paragraph',
            anchor: 'chapter-$index-paragraph',
            text: text,
            plainText: text,
            meta: const {},
          ),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [palette]),
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: chapterIndex,
            builder: (context, index, _) => ReaderHtmlView(
              chapter: chapter(index),
              imageResources: const {},
              failedImageResourceIds: const {},
              annotations: const <AnnotationView>[],
              preferences: _preferences,
              palette: palette,
              uiVisible: true,
              autoScrollEnabled: false,
              autoScrollPixelsPerSecond: 0,
              pagedMode: true,
              dualColumn: false,
              anchorJumpVersion: index,
              onHighlight: (_, _) async {},
              onAnnotate: (_, _) async {},
              onSaveAnnotation:
                  (
                    _,
                    _, {
                    required noteText,
                    required color,
                    required underlineStyle,
                  }) async {},
              onOpenAnnotations: (_) async {},
              onRetryImages: () async {},
              onVisibleAnchorChanged: (_) {},
              onPageBoundaryPrevious: () async {},
              onPageBoundaryNext: () async => chapterIndex.value = 1,
              onToggleUi: () {},
              onMenuRequest: () {},
              onAutoScrollInterrupted: () {},
              onAutoScrollBoundaryNext: () async {},
              viewportTapZoneVersion: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstChapter = find.text('第一章唯一一页');
    final initialPosition = tester.getTopLeft(firstChapter);
    final boundaryDrag = await tester.startGesture(const Offset(700, 300));
    await boundaryDrag.moveBy(const Offset(-180, 0));
    await tester.pump();
    expect(tester.getTopLeft(firstChapter).dx, lessThan(initialPosition.dx));
    await boundaryDrag.up();
    await tester.pump(const Duration(milliseconds: 75));
    expect(tester.getTopLeft(firstChapter).dx, lessThan(initialPosition.dx));

    await tester.pumpAndSettle();
    final secondChapter = find.text('第二章第一页');
    expect(secondChapter, findsOneWidget);
    expect(tester.getTopLeft(secondChapter).dx, closeTo(initialPosition.dx, 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'paged Flutter reader follows drag, rebounds, and keeps its page',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      });

      final pageTexts = <String>[];
      final blocks = <BookContentBlock>[];
      final resources = <String, Uint8List>{};
      for (var index = 0; index < 4; index += 1) {
        final caption = '连续页 ${index + 1}';
        final resourceId = 'image-$index';
        pageTexts.add(caption);
        blocks.add(
          BookContentBlock(
            blockIndex: index,
            type: 'image',
            anchor: 'chapter-0-page-$index-image',
            text: '',
            plainText: '',
            meta: {
              'resourceId': resourceId,
              'mediaType': 'image/png',
              'width': 1,
              'height': 1,
              'caption': caption,
            },
          ),
        );
      }
      final palette = AppReaderPalette.resolve(ReaderThemeMode.paper);
      final dualColumn = ValueNotifier<bool>(true);
      addTearDown(dualColumn.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [palette]),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: dualColumn,
              builder: (context, useDualColumn, _) => ReaderHtmlView(
                chapter: BookContentChapter(
                  bookId: 1,
                  contentModel: 'structured',
                  contentVersionId: 1,
                  hasStructuredContent: true,
                  chapterIndex: 0,
                  title: '漫画章节',
                  anchor: 'chapter-0',
                  blocks: blocks,
                ),
                imageResources: resources,
                failedImageResourceIds: const {},
                annotations: const <AnnotationView>[],
                preferences: _preferences,
                palette: palette,
                uiVisible: true,
                autoScrollEnabled: false,
                autoScrollPixelsPerSecond: 0,
                pagedMode: true,
                dualColumn: useDualColumn,
                anchorJumpVersion: 0,
                onHighlight: (_, _) async {},
                onAnnotate: (_, _) async {},
                onSaveAnnotation:
                    (
                      _,
                      _, {
                      required noteText,
                      required color,
                      required underlineStyle,
                    }) async {},
                onOpenAnnotations: (_) async {},
                onRetryImages: () async {},
                onVisibleAnchorChanged: (_) {},
                onPageBoundaryPrevious: () async {},
                onPageBoundaryNext: () async {},
                onToggleUi: () {},
                onMenuRequest: () {},
                onAutoScrollInterrupted: () {},
                onAutoScrollBoundaryNext: () async {},
                viewportTapZoneVersion: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstPage = find.text(pageTexts[0]);
      final secondPage = find.text(pageTexts[1]);
      final thirdPage = find.text(pageTexts[2]);
      final initialFirstPosition = tester.getTopLeft(firstPage);
      final initialSecondPosition = tester.getTopLeft(secondPage);
      final initialThirdPosition = tester.getTopLeft(thirdPage);

      expect(initialSecondPosition.dx, greaterThan(initialFirstPosition.dx));
      expect(initialSecondPosition.dy, initialFirstPosition.dy);
      expect(initialThirdPosition.dx, greaterThan(initialSecondPosition.dx));
      expect(initialThirdPosition.dy, initialFirstPosition.dy);

      final shortDrag = await tester.startGesture(const Offset(600, 350));
      await shortDrag.moveBy(const Offset(-20, 0));
      await shortDrag.moveBy(const Offset(-20, 0));
      await tester.pump();
      expect(
        tester.getTopLeft(firstPage).dx,
        lessThan(initialFirstPosition.dx),
      );
      await shortDrag.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(firstPage).dx, initialFirstPosition.dx);

      final committedDrag = await tester.startGesture(const Offset(700, 350));
      await committedDrag.moveBy(const Offset(-20, 0));
      await committedDrag.moveBy(const Offset(-160, 0));
      await tester.pump();
      expect(
        tester.getTopLeft(firstPage).dx,
        lessThan(initialFirstPosition.dx),
      );
      await committedDrag.up();
      await tester.pumpAndSettle();
      final nextSpreadPosition = tester.getTopLeft(thirdPage);
      expect(nextSpreadPosition.dx, initialFirstPosition.dx);
      expect(nextSpreadPosition.dy, initialFirstPosition.dy);

      dualColumn.value = false;
      await tester.pumpAndSettle();
      final positionAfterColumnSwitch = tester.getTopLeft(thirdPage);
      expect(positionAfterColumnSwitch.dx, inInclusiveRange(0, 1200));
      expect(positionAfterColumnSwitch.dy, inInclusiveRange(0, 700));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('restores the focused spread after comic images finish loading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    });

    const targetAnchor = 'chapter-0-target';
    const targetText = '我从哪里来？我要到哪里去？';
    final blocks = <BookContentBlock>[];
    final resources = <String, Uint8List>{};
    for (var index = 0; index < 8; index += 1) {
      if (index == 6) {
        blocks.add(
          const BookContentBlock(
            blockIndex: 6,
            type: 'paragraph',
            anchor: targetAnchor,
            text: targetText,
            plainText: targetText,
            meta: {},
          ),
        );
      }
      blocks.add(
        BookContentBlock(
          blockIndex: blocks.length,
          type: 'image',
          anchor: 'chapter-0-image-$index',
          text: '',
          plainText: '',
          meta: {'resourceId': 'image-$index', 'mediaType': 'image/png'},
        ),
      );
    }
    final resourceVersion = ValueNotifier<int>(0);
    final reportedAnchors = <String>[];
    addTearDown(resourceVersion.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [AppReaderPalette.resolve(ReaderThemeMode.paper)],
        ),
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: resourceVersion,
            builder: (context, version, _) => ReaderHtmlView(
              chapter: BookContentChapter(
                bookId: 1,
                contentModel: 'structured',
                contentVersionId: 1,
                hasStructuredContent: true,
                chapterIndex: 0,
                title: '漫画章节',
                anchor: 'chapter-0',
                blocks: blocks,
              ),
              imageResources: resources,
              failedImageResourceIds: const {},
              annotations: const <AnnotationView>[],
              preferences: _preferences,
              palette: AppReaderPalette.resolve(ReaderThemeMode.paper),
              uiVisible: true,
              autoScrollEnabled: false,
              autoScrollPixelsPerSecond: 0,
              pagedMode: true,
              dualColumn: true,
              anchorJumpVersion: version + 1,
              focusedAnchor: version < 2 ? targetAnchor : reportedAnchors.last,
              onHighlight: (_, _) async {},
              onAnnotate: (_, _) async {},
              onSaveAnnotation:
                  (
                    _,
                    _, {
                    required noteText,
                    required color,
                    required underlineStyle,
                  }) async {},
              onOpenAnnotations: (_) async {},
              onRetryImages: () async {},
              onVisibleAnchorChanged: reportedAnchors.add,
              onPageBoundaryPrevious: () async {},
              onPageBoundaryNext: () async {},
              onToggleUi: () {},
              onMenuRequest: () {},
              onAutoScrollInterrupted: () {},
              onAutoScrollBoundaryNext: () async {},
              viewportTapZoneVersion: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    // Images after the target deliberately remain unresolved. They cannot
    // affect the target's position and must not delay progress restoration.
    for (var index = 0; index < 6; index += 1) {
      resources['image-$index'] = imageBytes;
    }
    resourceVersion.value += 1;
    await tester.pumpAndSettle();

    final targetPosition = tester.getTopLeft(find.text(targetText));
    expect(targetPosition.dx, inInclusiveRange(0, 1200));
    expect(targetPosition.dy, inInclusiveRange(0, 700));
    expect(reportedAnchors, isNotEmpty);
    expect(reportedAnchors.last, 'chapter-0-image-4');

    resourceVersion.value += 1;
    await tester.pumpAndSettle();
    final restoredFromSavedAnchorPosition = tester.getTopLeft(
      find.text(targetText),
    );
    expect(restoredFromSavedAnchorPosition.dx, inInclusiveRange(0, 1200));
    expect(restoredFromSavedAnchorPosition.dy, inInclusiveRange(0, 700));
    debugDefaultTargetPlatformOverride = null;
  });
}

const ReaderPreferences _preferences = ReaderPreferences(
  themeMode: ReaderThemeMode.paper,
  fontScale: 1,
  lineHeight: 1.8,
  fontFamily: ReaderFontFamilyPreference.system,
  tabletPageTurnAnimation: TabletPageTurnAnimation.smooth,
);
