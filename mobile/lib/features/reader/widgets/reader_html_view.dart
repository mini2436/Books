import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/models/book_models.dart';
import '../../../data/models/sync_models.dart';
import '../../../features/settings/reader_preferences_controller.dart';
import '../../../shared/theme/reader_theme_extension.dart';
import '../reader_controller.dart';
import '../models/annotation_anchor.dart';
import 'reader_blocks.dart';

const List<String> _webAnnotationColors = [
  '#C3924A',
  '#7A4A24',
  '#4A6B3F',
  '#9C3C34',
  '#C86B3C',
  '#D0A43F',
  '#437A7D',
  '#5A63A3',
  '#7E4A9E',
  '#2D6A4F',
  '#B85C7A',
  '#6E727A',
];

class ReaderHtmlView extends StatefulWidget {
  const ReaderHtmlView({
    super.key,
    required this.chapter,
    required this.annotations,
    required this.preferences,
    required this.palette,
    required this.uiVisible,
    required this.pagedMode,
    required this.dualColumn,
    required this.anchorJumpVersion,
    required this.onHighlight,
    required this.onAnnotate,
    required this.onSaveAnnotation,
    required this.onOpenAnnotations,
    required this.onPageBoundaryPrevious,
    required this.onPageBoundaryNext,
    required this.onToggleUi,
    required this.onMenuRequest,
    required this.viewportTapZoneVersion,
    this.viewportTapZone,
    this.focusedAnchor,
  });

  final BookContentChapter chapter;
  final List<AnnotationView> annotations;
  final ReaderPreferences preferences;
  final AppReaderPalette palette;
  final bool uiVisible;
  final bool pagedMode;
  final bool dualColumn;
  final int anchorJumpVersion;
  final String? focusedAnchor;
  final Future<void> Function(
    AnnotationSelection selection,
    AnnotationView? existingAnnotation,
  )
  onHighlight;
  final Future<void> Function(
    AnnotationSelection selection,
    AnnotationView? existingAnnotation,
  )
  onAnnotate;
  final Future<void> Function(
    AnnotationSelection selection,
    AnnotationView? existingAnnotation, {
    required String? noteText,
    required String color,
    required AnnotationUnderlineStyle underlineStyle,
  })
  onSaveAnnotation;
  final Future<void> Function(List<AnnotationView> annotations)
  onOpenAnnotations;
  final Future<void> Function() onPageBoundaryPrevious;
  final Future<void> Function() onPageBoundaryNext;
  final VoidCallback onToggleUi;
  final VoidCallback onMenuRequest;
  final int viewportTapZoneVersion;
  final String? viewportTapZone;

  @override
  State<ReaderHtmlView> createState() => _ReaderHtmlViewState();
}

class _ReaderHtmlViewState extends State<ReaderHtmlView> {
  late final WebViewController _controller;
  late String _lastHtml;
  bool _pageReady = false;
  bool _useFlutterFallback = false;
  int? _pendingBoundaryAnimationDirection;
  int _lastAnchorJumpVersion = -1;
  final Map<String, GlobalKey> _fallbackAnchorKeys = <String, GlobalKey>{};
  final List<String> _pendingTapZones = <String>[];
  final ScrollController _fallbackScrollController = ScrollController();
  Timer? _blankPageGuard;

  bool get _forceFlutterReader =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  bool get _allowFlutterFallback => _forceFlutterReader || !widget.pagedMode;

  @override
  void initState() {
    super.initState();
    _lastHtml = _buildHtml();
    if (_forceFlutterReader) {
      _useFlutterFallback = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollFallbackToFocusedAnchor(force: true);
      });
      return;
    }
    _controller =
        WebViewController.fromPlatformCreationParams(
            const PlatformWebViewControllerCreationParams(),
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(widget.palette.background)
          ..setNavigationDelegate(
            NavigationDelegate(
              onWebResourceError: (error) {
                _handleWebViewFailure(
                  reason:
                      'Web resource error: ${error.errorCode} ${error.description}',
                );
              },
              onPageFinished: (_) async {
                await _controller.runJavaScript(
                  'if (window.readerSetChromeVisible) { window.readerSetChromeVisible(${widget.uiVisible ? 'true' : 'false'}); }',
                );
                await _controller.runJavaScript(
                  'if (window.readerApplyLayout) { window.readerApplyLayout(); }',
                );
              },
            ),
          )
          ..addJavaScriptChannel(
            'ReaderBridge',
            onMessageReceived: _handleBridgeMessage,
          )
          ..loadHtmlString(_lastHtml);
    if (defaultTargetPlatform == TargetPlatform.android) {
      final dynamic platformController = _controller.platform;
      unawaited(platformController.setVerticalScrollBarEnabled(false));
      unawaited(platformController.setHorizontalScrollBarEnabled(false));
    }
    _armBlankPageGuard();
  }

  @override
  void didUpdateWidget(covariant ReaderHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final chapterChanged = oldWidget.chapter.anchor != widget.chapter.anchor;
    final nextHtml = _buildHtml();
    if (_forceFlutterReader) {
      _lastHtml = nextHtml;
      if (chapterChanged ||
          widget.anchorJumpVersion != oldWidget.anchorJumpVersion ||
          widget.focusedAnchor != oldWidget.focusedAnchor) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollFallbackToFocusedAnchor(force: chapterChanged);
        });
      }
      if (widget.viewportTapZoneVersion != oldWidget.viewportTapZoneVersion) {
        _handleViewportTapZone();
      }
      return;
    }
    if (nextHtml != _lastHtml) {
      _lastHtml = nextHtml;
      _pageReady = false;
      _useFlutterFallback = false;
      _pendingBoundaryAnimationDirection = chapterChanged
          ? _boundaryAnimationDirectionForAnchor(widget.focusedAnchor)
          : null;
      _pendingTapZones.clear();
      _blankPageGuard?.cancel();
      _controller
        ..setBackgroundColor(widget.palette.background)
        ..loadHtmlString(_lastHtml);
      _armBlankPageGuard();
      return;
    }
    if (widget.anchorJumpVersion != oldWidget.anchorJumpVersion ||
        widget.focusedAnchor != oldWidget.focusedAnchor) {
      _scrollToFocusedAnchor();
    }
    if (widget.viewportTapZoneVersion != oldWidget.viewportTapZoneVersion) {
      _handleViewportTapZone();
    }
    if (widget.uiVisible != oldWidget.uiVisible) {
      _controller.runJavaScript(
        'window.readerSetChromeVisible(${widget.uiVisible ? 'true' : 'false'});',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_useFlutterFallback) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) => _handleFallbackViewportTap(
              details.localPosition.dx,
              constraints.maxWidth,
            ),
            child: SingleChildScrollView(
              controller: _fallbackScrollController,
              padding: const EdgeInsets.only(bottom: 12),
              child: ReaderBlocksView(
                blocks: widget.chapter.blocks,
                annotations: widget.annotations,
                preferences: widget.preferences,
                keyForAnchor: _fallbackKeyForAnchor,
                onHighlight: widget.onHighlight,
                onAnnotate: widget.onAnnotate,
                onOpenAnnotations: widget.onOpenAnnotations,
              ),
            ),
          );
        },
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: widget.palette.background),
      child: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (!_pageReady)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: widget.palette.background,
                  child: _ReaderLoadingOverlay(
                    chapter: widget.chapter,
                    annotations: widget.annotations,
                    preferences: widget.preferences,
                    palette: widget.palette,
                    pagedMode: widget.pagedMode,
                    onHighlight: widget.onHighlight,
                    onAnnotate: widget.onAnnotate,
                    onOpenAnnotations: widget.onOpenAnnotations,
                    keyForAnchor: _fallbackKeyForAnchor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _blankPageGuard?.cancel();
    _fallbackScrollController.dispose();
    super.dispose();
  }

  Future<void> _handleBridgeMessage(JavaScriptMessage message) async {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (payload['type']) {
      case 'ready':
        await _handlePageReady();
        break;
      case 'toggleUi':
        widget.onToggleUi();
        break;
      case 'showMenu':
        widget.onMenuRequest();
        break;
      case 'previousChapter':
        await widget.onPageBoundaryPrevious();
        break;
      case 'nextChapter':
        await widget.onPageBoundaryNext();
        break;
      case 'highlight':
      case 'annotate':
      case 'saveAnnotation':
        final selection = _selectionFromPayload(payload);
        if (selection == null) {
          return;
        }
        final intent = _resolveSelectionIntent(selection);
        if (payload['type'] == 'highlight') {
          await widget.onHighlight(intent.selection, intent.existingAnnotation);
        } else if (payload['type'] == 'annotate') {
          await widget.onAnnotate(intent.selection, intent.existingAnnotation);
        } else {
          final rawNote = payload['noteText'] as String?;
          final noteText = rawNote == null || rawNote.trim().isEmpty
              ? null
              : rawNote.trim();
          final color = payload['color'] as String?;
          await widget.onSaveAnnotation(
            intent.selection,
            intent.existingAnnotation,
            noteText: noteText,
            color: _normalizeAnnotationColor(color),
            underlineStyle: AnnotationUnderlineStyle.fromValue(
              payload['underlineStyle'] as String?,
            ),
          );
        }
        unawaited(_clearSelectionUi());
        break;
      case 'annotationTap':
        final ids = ((payload['annotationIds'] as List<dynamic>?) ?? const [])
            .map((item) => (item as num).toInt())
            .toSet();
        final tapped =
            widget.annotations
                .where((annotation) => ids.contains(annotation.id))
                .toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (tapped.isNotEmpty) {
          await widget.onOpenAnnotations(tapped);
        }
        break;
    }
  }

  Future<void> _clearSelectionUi() async {
    if (!_pageReady) {
      return;
    }
    await _controller.runJavaScript('window.readerClearSelectionUi();');
  }

  Future<void> _handleExternalTapZone(String zone) async {
    if (_useFlutterFallback) {
      await _handleFallbackTapZone(zone);
      return;
    }
    if (!_pageReady) {
      if (zone == 'center') {
        widget.onMenuRequest();
        return;
      }
      _pendingTapZones.add(zone);
      return;
    }
    final escapedZone = jsonEncode(zone);
    await _controller.runJavaScript(
      'window.readerHandleTapZone($escapedZone);',
    );
  }

  void _handleFallbackViewportTap(double localDx, double width) {
    if (width <= 0 || !widget.pagedMode) {
      widget.onToggleUi();
      return;
    }
    final ratio = localDx / width;
    if (ratio <= 0.32) {
      unawaited(_handleFallbackTapZone('left'));
      return;
    }
    if (ratio >= 0.68) {
      unawaited(_handleFallbackTapZone('right'));
      return;
    }
    unawaited(_handleFallbackTapZone('center'));
  }

  Future<void> _handleFallbackTapZone(String zone) async {
    switch (zone) {
      case 'left':
        await _turnFallbackPage(-1);
        return;
      case 'right':
        await _turnFallbackPage(1);
        return;
      case 'center':
        widget.onToggleUi();
        return;
    }
  }

  Future<void> _turnFallbackPage(int direction) async {
    if (!_fallbackScrollController.hasClients) {
      if (direction < 0) {
        await widget.onPageBoundaryPrevious();
      } else {
        await widget.onPageBoundaryNext();
      }
      return;
    }

    final position = _fallbackScrollController.position;
    const boundaryTolerance = 4.0;
    if (direction < 0 &&
        position.pixels <= position.minScrollExtent + boundaryTolerance) {
      await widget.onPageBoundaryPrevious();
      return;
    }
    if (direction > 0 &&
        position.pixels >= position.maxScrollExtent - boundaryTolerance) {
      await widget.onPageBoundaryNext();
      return;
    }

    final pageStep = (position.viewportDimension * 0.92).clamp(
      120.0,
      double.infinity,
    );
    final target = (position.pixels + direction * pageStep).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    await _fallbackScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollFallbackToFocusedAnchor({bool force = false}) async {
    if (!_useFlutterFallback ||
        !_fallbackScrollController.hasClients ||
        (!force && _lastAnchorJumpVersion == widget.anchorJumpVersion)) {
      return;
    }
    _lastAnchorJumpVersion = widget.anchorJumpVersion;

    final rawAnchor = widget.focusedAnchor ?? '';
    if (rawAnchor == readerChapterEndMarker) {
      _fallbackScrollController.jumpTo(
        _fallbackScrollController.position.maxScrollExtent,
      );
      return;
    }
    if (rawAnchor == readerChapterStartMarker || rawAnchor.isEmpty) {
      _fallbackScrollController.jumpTo(
        _fallbackScrollController.position.minScrollExtent,
      );
      return;
    }

    final anchor = AnnotationAnchor.parse(rawAnchor).blockAnchor;
    final targetContext = _fallbackAnchorKeys[anchor]?.currentContext;
    if (targetContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.2,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handlePageReady() async {
    if (_pageReady || _useFlutterFallback) {
      return;
    }
    await _verifyRenderedContent();
    if (!mounted || _useFlutterFallback) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _pageReady = true;
    });
    await _scrollToFocusedAnchor();
    await _playPendingBoundaryAnimation();
    await _flushPendingTapZones();
  }

  Future<void> _handleViewportTapZone() async {
    final zone = widget.viewportTapZone;
    if (zone == null || zone.isEmpty) {
      return;
    }
    await _handleExternalTapZone(zone);
  }

  Future<void> _verifyRenderedContent() async {
    if (_useFlutterFallback) {
      return;
    }
    final expectedTextLength = widget.chapter.blocks
        .map((block) => block.renderedText.trim())
        .where((text) => text.isNotEmpty)
        .fold<int>(0, (sum, text) => sum + text.length);
    if (expectedTextLength == 0) {
      return;
    }
    try {
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          var root = document.getElementById("reader-root");
          if (!root || !root.innerText) {
            return 0;
          }
          return root.innerText.trim().length;
        })();
        ''');
      final renderedLength = int.tryParse(
        result.toString().replaceAll('"', ''),
      );
      if (renderedLength == null || renderedLength <= 0) {
        _handleWebViewFailure(
          reason:
              'Rendered content verification failed with length=$renderedLength',
        );
        return;
      }
      _blankPageGuard?.cancel();
    } catch (error, stackTrace) {
      _handleWebViewFailure(
        reason: 'Rendered content verification threw',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _armBlankPageGuard() {
    _blankPageGuard?.cancel();
    _blankPageGuard = Timer(const Duration(seconds: 2), () async {
      if (!mounted || _useFlutterFallback || _pageReady) {
        return;
      }
      await _handlePageReady();
    });
  }

  void _handleWebViewFailure({
    required String reason,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      reason,
      name: 'ReaderHtmlView',
      error: error,
      stackTrace: stackTrace,
    );
    if (!_allowFlutterFallback) {
      developer.log(
        'Paged reader mode keeps WebView active; suppressing Flutter fallback.',
        name: 'ReaderHtmlView',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _useFlutterFallback = true;
    });
  }

  Future<void> _flushPendingTapZones() async {
    if (!_pageReady || _pendingTapZones.isEmpty) {
      return;
    }
    final pending = List<String>.from(_pendingTapZones);
    _pendingTapZones.clear();
    for (final zone in pending) {
      await _handleExternalTapZone(zone);
    }
  }

  Future<void> _scrollToFocusedAnchor() async {
    if (!_pageReady) {
      return;
    }
    if (_lastAnchorJumpVersion == widget.anchorJumpVersion) {
      return;
    }
    _lastAnchorJumpVersion = widget.anchorJumpVersion;
    final rawAnchor = widget.focusedAnchor ?? '';
    if (rawAnchor == readerChapterEndMarker ||
        rawAnchor == readerChapterStartMarker) {
      final boundary = rawAnchor == readerChapterEndMarker ? 'end' : 'start';
      await _controller.runJavaScript(
        'window.readerScrollToBoundary(${jsonEncode(boundary)});',
      );
      return;
    }
    final anchor = AnnotationAnchor.parse(rawAnchor).blockAnchor;
    if (anchor.isEmpty) {
      return;
    }
    final escapedAnchor = jsonEncode(anchor);
    await _controller.runJavaScript(
      'window.readerScrollToAnchor($escapedAnchor);',
    );
  }

  int? _boundaryAnimationDirectionForAnchor(String? anchor) {
    if (anchor == readerChapterStartMarker) {
      return 1;
    }
    if (anchor == readerChapterEndMarker) {
      return -1;
    }
    return null;
  }

  Future<void> _playPendingBoundaryAnimation() async {
    final direction = _pendingBoundaryAnimationDirection;
    _pendingBoundaryAnimationDirection = null;
    if (!_pageReady || !widget.pagedMode || direction == null) {
      return;
    }
    await _controller.runJavaScript(
      'window.readerPlayBoundaryTransition(${direction >= 0 ? 1 : -1});',
    );
  }

  AnnotationSelection? _selectionFromPayload(Map<String, dynamic> payload) {
    final blockAnchor =
        payload['startBlockAnchor'] as String? ??
        payload['blockAnchor'] as String? ??
        '';
    final endBlockAnchor = payload['endBlockAnchor'] as String? ?? blockAnchor;
    final startOffset = (payload['startOffset'] as num?)?.toInt();
    final endOffset = (payload['endOffset'] as num?)?.toInt();
    if (blockAnchor.isEmpty || startOffset == null || endOffset == null) {
      return null;
    }
    final blocks = widget.chapter.blocks;
    final block = blocks.cast<BookContentBlock?>().firstWhere(
      (item) => item?.anchor == blockAnchor,
      orElse: () => null,
    );
    final endBlock = blocks.cast<BookContentBlock?>().firstWhere(
      (item) => item?.anchor == endBlockAnchor,
      orElse: () => null,
    );
    if (block == null || endBlock == null) {
      return null;
    }
    final blockText = block.renderedText;
    final endBlockText = endBlock.renderedText;
    final startIndex = blocks.indexWhere((item) => item.anchor == blockAnchor);
    final endIndex = blocks.indexWhere((item) => item.anchor == endBlockAnchor);
    if (startIndex < 0 || endIndex < 0 || startIndex > endIndex) {
      return null;
    }

    final sameBlock = blockAnchor == endBlockAnchor;
    final normalizedStart = sameBlock && startOffset > endOffset
        ? endOffset
        : startOffset;
    final normalizedEnd = sameBlock && startOffset > endOffset
        ? startOffset
        : endOffset;
    if (normalizedStart < 0 ||
        normalizedStart > blockText.length ||
        normalizedEnd < 0 ||
        normalizedEnd > endBlockText.length ||
        (sameBlock && normalizedStart == normalizedEnd)) {
      return null;
    }

    final selectedText = payload['selectedText'] as String?;
    if ((selectedText == null || selectedText.isEmpty) &&
        normalizedStart == normalizedEnd &&
        !sameBlock) {
      return null;
    }
    return AnnotationSelection(
      blockAnchor: blockAnchor,
      blockText: blockText,
      startOffset: normalizedStart,
      endOffset: normalizedEnd,
      endBlockAnchor: endBlockAnchor,
      endBlockText: endBlockText,
      selectedText: selectedText,
    );
  }

  _SelectionIntent _resolveSelectionIntent(AnnotationSelection selection) {
    if (selection.spansMultipleBlocks) {
      return _SelectionIntent(selection: selection, existingAnnotation: null);
    }

    final orderedBlockAnchors = widget.chapter.blocks
        .map((block) => block.anchor)
        .toList(growable: false);
    final blockAnnotations = widget.annotations
        .map(
          (annotation) => ResolvedAnnotation.fromAnnotation(
            annotation,
            selection.blockText,
            currentBlockAnchor: selection.blockAnchor,
            orderedBlockAnchors: orderedBlockAnchors,
          ),
        )
        .whereType<ResolvedAnnotation>()
        .where(
          (annotation) =>
              !annotation.anchor.spansMultipleBlocks &&
              annotation.anchor.blockAnchor == selection.blockAnchor,
        )
        .toList();

    final containing =
        blockAnnotations
            .where(
              (annotation) => annotation.anchor.containsRange(
                start: selection.startOffset,
                end: selection.endOffset,
                text: selection.blockText,
              ),
            )
            .toList()
          ..sort(
            (left, right) => left.range.length.compareTo(right.range.length),
          );
    if (containing.isNotEmpty) {
      return _SelectionIntent(
        selection: selection,
        existingAnnotation: containing.first.annotation,
      );
    }

    final overlapping =
        blockAnnotations
            .where(
              (annotation) => annotation.anchor.overlapsOrTouches(
                start: selection.startOffset,
                end: selection.endOffset,
                text: selection.blockText,
              ),
            )
            .toList()
          ..sort(
            (left, right) => left.range.start.compareTo(right.range.start),
          );
    if (overlapping.isNotEmpty) {
      final target = overlapping.first;
      final expandedRange = selection.range.union(target.range);
      return _SelectionIntent(
        selection: AnnotationSelection(
          blockAnchor: selection.blockAnchor,
          blockText: selection.blockText,
          startOffset: expandedRange.start,
          endOffset: expandedRange.end,
        ),
        existingAnnotation: target.annotation,
      );
    }

    return _SelectionIntent(selection: selection, existingAnnotation: null);
  }

  String _buildHtml() {
    final bodyClasses = <String>[
      if (widget.pagedMode) 'reader-paged',
      if (widget.dualColumn) 'reader-dual-column',
    ].join(' ');
    final paragraphStyle = _fontCss(
      fontSize: 17 * widget.preferences.fontScale,
      lineHeight: widget.preferences.lineHeight / 1.4,
    );
    final quoteStyle = _fontCss(
      fontSize: 17 * widget.preferences.fontScale,
      lineHeight: widget.preferences.lineHeight / 1.6,
      fontStyle: 'italic',
    );
    final headingSize = 30 * widget.preferences.fontScale;
    final orderedBlockAnchors = widget.chapter.blocks
        .map((block) => block.anchor)
        .toList(growable: false);
    final htmlBlocks = widget.chapter.blocks
        .map((block) => _buildBlockHtml(block, orderedBlockAnchors))
        .join();

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    :root {
      --reader-bg: ${_cssColor(widget.palette.background)};
      --reader-bg-soft: ${_cssColor(widget.palette.backgroundSoft)};
      --reader-ink: ${_cssColor(widget.palette.ink)};
      --reader-ink-secondary: ${_cssColor(widget.palette.inkSecondary)};
      --reader-accent: ${_cssColor(widget.palette.accent)};
      --reader-line: ${_cssColor(widget.palette.line)};
      --reader-selection: ${_cssColor(widget.palette.selection)};
      --reader-mask: ${_cssColor(widget.palette.mask)};
    }
    * { box-sizing: border-box; }
    html, body {
      height: 100%;
      margin: 0;
      padding: 0;
      background: var(--reader-bg);
      color: var(--reader-ink);
      overscroll-behavior: none;
      -webkit-tap-highlight-color: transparent;
      font-family: ${_fontStackCss()};
    }
    body {
      padding: 0;
      overflow: hidden;
      user-select: text;
      -webkit-user-select: text;
    }
    body.reader-paged {
      padding: 0;
      overflow: hidden;
      perspective: 1800px;
      perspective-origin: center center;
    }
    ::selection {
      background: var(--reader-selection);
    }
    #reader-stage {
      position: relative;
      width: 100%;
      height: 100%;
      overflow-x: hidden;
      overflow-y: auto;
      scrollbar-width: none;
      -ms-overflow-style: none;
      -webkit-overflow-scrolling: touch;
      background: var(--reader-bg);
      padding: 0 0 28px;
    }
    #reader-stage::-webkit-scrollbar {
      display: none;
      width: 0;
      height: 0;
    }
    #reader-root {
      padding: 0;
      will-change: transform;
    }
    body.reader-paged #reader-stage {
      padding: 24px 28px 28px;
      overflow: hidden;
      transform-style: preserve-3d;
      backface-visibility: hidden;
      will-change: transform, opacity, filter;
    }
    body.reader-paged #reader-root {
      height: 100%;
      column-fill: auto;
      column-gap: 36px;
      transition: none;
    }
    body.reader-paged.reader-dual-column #reader-root {
      column-width: calc((100vw - 56px - 36px) / 2);
    }
    body.reader-paged:not(.reader-dual-column) #reader-root {
      column-width: calc(100vw - 56px);
    }
    .reader-block {
      position: relative;
      color: var(--reader-ink);
      white-space: pre-wrap;
      word-break: break-word;
      overflow-wrap: anywhere;
    }
    .reader-block + .reader-block {
      margin-top: 16px;
    }
    .reader-block[data-type="heading"] {
      font-size: ${headingSize.toStringAsFixed(2)}px;
      line-height: 1.25;
      font-weight: 700;
      margin-bottom: 22px;
    }
    .reader-block[data-type="paragraph"] {
      $paragraphStyle
      text-align: justify;
      margin: 0 0 16px;
    }
    .reader-block[data-type="quote"] {
      $quoteStyle
      text-align: justify;
      margin: 0 0 18px;
      padding: 14px 16px;
      border-left: 3px solid var(--reader-accent);
      border-radius: 12px;
      background: var(--reader-bg-soft);
      color: var(--reader-ink-secondary);
    }
    .reader-block[data-type="divider"] {
      text-align: center;
      letter-spacing: 6px;
      color: var(--reader-ink-secondary);
      margin: 24px 0;
      font-size: ${((17 * widget.preferences.fontScale) * 0.95).toStringAsFixed(2)}px;
    }
    .reader-block.legacy-highlight {
      padding: 6px 10px;
      border-radius: 14px;
    }
    .annot {
      --annot-bg: transparent;
      --annot-gap: 0.14em;
      border-radius: 4px;
      box-decoration-break: clone;
      -webkit-box-decoration-break: clone;
      cursor: pointer;
      background-color: transparent !important;
      background-image: linear-gradient(
        to bottom,
        transparent 0,
        transparent var(--annot-gap),
        var(--annot-bg) var(--annot-gap),
        var(--annot-bg) calc(100% - var(--annot-gap)),
        transparent calc(100% - var(--annot-gap)),
        transparent 100%
      );
    }
    .annot.has-underline {
      text-decoration-line: underline;
      text-decoration-thickness: 2px;
      text-underline-offset: 0.18em;
    }
    .annot.underline-solid { text-decoration-style: solid; }
    .annot.underline-dotted { text-decoration-style: dotted; }
    .annot.underline-wavy { text-decoration-style: wavy; }
    .reader-anchor-pulse {
      animation: reader-pulse 1.2s ease-out 1;
    }
    @keyframes reader-pulse {
      0% { box-shadow: 0 0 0 0 ${_cssColor(widget.palette.accent.withValues(alpha: 0.28))}; }
      100% { box-shadow: 0 0 0 14px rgba(0,0,0,0); }
    }
    .reader-toolbar {
      position: fixed;
      z-index: 2147483647;
      display: none;
      max-width: calc(100vw - 24px);
      border-radius: 16px;
      background: var(--reader-bg-soft);
      background: color-mix(in srgb, var(--reader-bg) 88%, #111 12%);
      border: 1px solid var(--reader-line);
      border: 1px solid color-mix(in srgb, var(--reader-line) 78%, transparent);
      box-shadow: 0 14px 34px rgba(0, 0, 0, 0.22);
      overflow: hidden;
      color: var(--reader-ink);
      transform: translateY(0);
    }
    .reader-quickbar {
      display: flex;
      gap: 6px;
      padding: 6px;
    }
    .reader-toolbar button,
    .reader-toolbar textarea {
      font-family: ${_fontStackCss()};
    }
    .reader-toolbar button {
      border: 0;
      border-radius: 12px;
      padding: 9px 14px;
      font-size: 14px;
      color: var(--reader-ink);
      background: transparent;
    }
    .reader-toolbar button:disabled {
      opacity: 0.54;
    }
    .reader-toolbar button:active {
      transform: translateY(1px);
    }
    .reader-toolbar button.primary {
      background: ${_cssColor(widget.palette.accent)};
      color: ${_cssColor(widget.palette.background)};
      font-weight: 600;
    }
    .reader-composer {
      display: none;
      width: min(340px, calc(100vw - 24px));
      padding: 12px;
      gap: 10px;
    }
    .reader-toolbar.composing .reader-quickbar {
      display: none;
    }
    .reader-toolbar.composing .reader-composer {
      display: grid;
    }
    .reader-composer-quote {
      max-height: 64px;
      overflow: hidden;
      padding: 10px;
      border-radius: 12px;
      background: var(--reader-bg-soft);
      color: var(--reader-ink-secondary);
      font-size: 13px;
      line-height: 1.45;
    }
    .reader-composer textarea {
      width: 100%;
      min-height: 92px;
      resize: none;
      border: 1px solid var(--reader-line);
      border-radius: 12px;
      padding: 10px 12px;
      background: var(--reader-bg);
      color: var(--reader-ink);
      font-size: 15px;
      line-height: 1.45;
      outline: none;
    }
    .reader-composer textarea:focus {
      border-color: var(--reader-accent);
      box-shadow: 0 0 0 3px color-mix(in srgb, var(--reader-accent) 22%, transparent);
    }
    .reader-composer-label {
      margin: 0;
      font-size: 12px;
      font-weight: 700;
      color: var(--reader-ink-secondary);
    }
    .reader-color-row,
    .reader-underline-row,
    .reader-action-row {
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .reader-color-row {
      overflow-x: auto;
      scrollbar-width: none;
      padding-bottom: 1px;
    }
    .reader-color-row::-webkit-scrollbar {
      display: none;
    }
    .reader-color-button {
      flex: 0 0 auto;
      width: 26px;
      height: 26px;
      padding: 0 !important;
      border-radius: 999px !important;
      border: 2px solid transparent !important;
      box-shadow: inset 0 0 0 1px rgba(0,0,0,0.12);
    }
    .reader-color-button.selected {
      border-color: var(--reader-ink) !important;
      box-shadow: 0 0 0 2px var(--reader-bg), inset 0 0 0 1px rgba(0,0,0,0.12);
    }
    .reader-underline-row {
      flex-wrap: wrap;
    }
    .reader-underline-row button {
      padding: 7px 10px;
      border: 1px solid var(--reader-line);
      background: var(--reader-bg-soft);
      font-size: 13px;
    }
    .reader-underline-row button.selected {
      border-color: var(--reader-accent);
      color: var(--reader-accent);
      font-weight: 700;
    }
    .reader-action-row {
      justify-content: flex-end;
      padding-top: 2px;
    }
    .reader-selection-overlay {
      position: fixed;
      inset: 0;
      pointer-events: none;
      z-index: 2147483646;
      display: none;
    }
    .reader-selection-overlay .segment {
      position: fixed;
      border-radius: 6px;
      background: var(--reader-selection);
    }
    .reader-page-turn-shadow {
      position: absolute;
      inset: 0;
      pointer-events: none;
      z-index: 2;
      opacity: 0;
      background: transparent;
    }
  </style>
</head>
<body${bodyClasses.isEmpty ? '' : ' class="$bodyClasses"'}>
  <div id="reader-stage">
    <div id="reader-root">$htmlBlocks</div>
  </div>
  <div id="reader-page-turn-shadow" class="reader-page-turn-shadow"></div>
  <div id="reader-selection-overlay" class="reader-selection-overlay"></div>
  <div id="reader-toolbar" class="reader-toolbar">
    <div class="reader-quickbar">
      <button type="button" data-action="highlight">高亮</button>
      <button type="button" class="primary" data-action="compose">批注</button>
    </div>
    <div class="reader-composer">
      <div id="reader-composer-quote" class="reader-composer-quote"></div>
      <textarea id="reader-composer-note" placeholder="写下批注"></textarea>
      <p class="reader-composer-label">颜色</p>
      <div id="reader-color-row" class="reader-color-row"></div>
      <p class="reader-composer-label">下划线</p>
      <div id="reader-underline-row" class="reader-underline-row"></div>
      <div class="reader-action-row">
        <button type="button" data-action="cancelCompose">取消</button>
        <button type="button" class="primary" data-action="saveAnnotation">保存</button>
      </div>
    </div>
  </div>
  <script>
    (function() {
      const bridge = window.ReaderBridge;
      const stage = document.getElementById('reader-stage');
      const root = document.getElementById('reader-root');
      const turnShadow = document.getElementById('reader-page-turn-shadow');
      const toolbar = document.getElementById('reader-toolbar');
      const overlay = document.getElementById('reader-selection-overlay');
      const quotePreview = document.getElementById('reader-composer-quote');
      const noteInput = document.getElementById('reader-composer-note');
      const colorRow = document.getElementById('reader-color-row');
      const underlineRow = document.getElementById('reader-underline-row');
      const pagedMode = ${widget.pagedMode ? 'true' : 'false'};
      const pageTurnAxis = ${jsonEncode(widget.preferences.tabletPageTurnAxis.storageValue)};
      const pageTurnAnimation = ${jsonEncode(widget.preferences.tabletPageTurnAnimation.storageValue)};
      const annotationColors = ${jsonEncode(_webAnnotationColors)};
      const defaultAnnotationColor = ${jsonEncode(_defaultAnnotationColor(widget.preferences.themeMode))};
      const underlineOptions = [
        { value: 'none', label: '无线条' },
        { value: 'solid', label: '直线' },
        { value: 'dotted', label: '点线' },
        { value: 'wavy', label: '波浪线' }
      ];
      let currentSelection = null;
      let composerOpen = false;
      let selectedColor = defaultAnnotationColor;
      let selectedUnderline = 'none';
      let nativeSelectionClearTimer = null;
      let preservingSelectionUi = false;
      let readySent = false;
      let currentPage = 0;
      let pageCount = 1;
      let pageSpan = 0;
      let currentOffset = 0;
      let pageAnimationBusy = false;
      let touchStartX = 0;
      let touchStartY = 0;
      let touchStartAt = 0;
      let touchMoved = false;
      let touchTracking = false;
      let lastTouchHandledAt = 0;
      let selectionRefreshTimer = null;

      function send(payload) {
        if (!bridge || !bridge.postMessage) return;
        bridge.postMessage(JSON.stringify(payload));
      }

      function sendReady() {
        if (readySent) {
          return;
        }
        readySent = true;
        send({ type: 'ready' });
      }

      function afterStableLayout(callback) {
        const finalize = function() {
          window.requestAnimationFrame(function() {
            window.requestAnimationFrame(callback);
          });
        };
        if (document.fonts && document.fonts.ready && typeof document.fonts.ready.then === 'function') {
          document.fonts.ready.then(finalize).catch(finalize);
          return;
        }
        finalize();
      }

      function afterTwoFrames(callback) {
        window.requestAnimationFrame(function() {
          window.requestAnimationFrame(callback);
        });
      }

      function directionalTransform(distance) {
        if (pageTurnAxis === 'horizontal') {
          return 'translate3d(' + distance + 'px,0,0)';
        }
        return 'translate3d(0,' + distance + 'px,0)';
      }

      function clearTurnShadow() {
        if (!turnShadow) {
          return;
        }
        turnShadow.style.transition = 'none';
        turnShadow.style.opacity = '0';
        turnShadow.style.background = 'transparent';
      }

      function updateTurnShadow(direction, intensity, incoming) {
        if (!turnShadow) {
          return;
        }
        const shadowStrength = Math.max(0, Math.min(0.28, intensity));
        if (shadowStrength <= 0.001) {
          clearTurnShadow();
          return;
        }
        let gradient;
        if (pageTurnAxis === 'horizontal') {
          if (direction > 0) {
            gradient = incoming
              ? 'linear-gradient(270deg, rgba(0,0,0,' + (shadowStrength * 0.92) + ') 0%, rgba(0,0,0,' + (shadowStrength * 0.38) + ') 18%, rgba(255,255,255,' + (shadowStrength * 0.28) + ') 48%, rgba(255,255,255,0) 74%)'
              : 'linear-gradient(90deg, rgba(255,255,255,' + (shadowStrength * 0.22) + ') 0%, rgba(0,0,0,' + (shadowStrength * 0.72) + ') 24%, rgba(0,0,0,0) 62%)';
          } else {
            gradient = incoming
              ? 'linear-gradient(90deg, rgba(0,0,0,' + (shadowStrength * 0.92) + ') 0%, rgba(0,0,0,' + (shadowStrength * 0.38) + ') 18%, rgba(255,255,255,' + (shadowStrength * 0.28) + ') 48%, rgba(255,255,255,0) 74%)'
              : 'linear-gradient(270deg, rgba(255,255,255,' + (shadowStrength * 0.22) + ') 0%, rgba(0,0,0,' + (shadowStrength * 0.72) + ') 24%, rgba(0,0,0,0) 62%)';
          }
        } else if (direction > 0) {
          gradient = incoming
            ? 'linear-gradient(180deg, rgba(0,0,0,' + (shadowStrength * 0.9) + ') 0%, rgba(0,0,0,' + (shadowStrength * 0.34) + ') 18%, rgba(255,255,255,' + (shadowStrength * 0.2) + ') 42%, rgba(255,255,255,0) 70%)'
            : 'linear-gradient(0deg, rgba(255,255,255,' + (shadowStrength * 0.18) + ') 0%, rgba(0,0,0,' + (shadowStrength * 0.72) + ') 22%, rgba(0,0,0,0) 58%)';
        } else {
          gradient = incoming
            ? 'linear-gradient(0deg, rgba(0,0,0,' + (shadowStrength * 0.9) + ') 0%, rgba(0,0,0,' + (shadowStrength * 0.34) + ') 18%, rgba(255,255,255,' + (shadowStrength * 0.2) + ') 42%, rgba(255,255,255,0) 70%)'
            : 'linear-gradient(180deg, rgba(255,255,255,' + (shadowStrength * 0.18) + ') 0%, rgba(0,0,0,' + (shadowStrength * 0.72) + ') 22%, rgba(0,0,0,0) 58%)';
        }
        turnShadow.style.background = gradient;
        turnShadow.style.opacity = '1';
      }

      function clearStageAnimationState() {
        if (!stage) {
          clearTurnShadow();
          return;
        }
        stage.style.transition = 'none';
        stage.style.transformOrigin = 'center center';
        stage.style.transform = 'translate3d(0,0,0)';
        stage.style.opacity = '1';
        stage.style.filter = 'none';
        clearTurnShadow();
      }

      function hasActiveDomSelection() {
        const selection = window.getSelection();
        return !!selection &&
          selection.rangeCount > 0 &&
          !selection.isCollapsed &&
          selection.toString().length > 0;
      }

      function selectionData() {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          return null;
        }
        const range = selection.getRangeAt(0);
        const startParent = range.startContainer && range.startContainer.parentElement
          ? range.startContainer.parentElement
          : null;
        const endParent = range.endContainer && range.endContainer.parentElement
          ? range.endContainer.parentElement
          : null;
        const startBlock = startParent ? startParent.closest('[data-block-anchor]') : null;
        const endBlock = endParent ? endParent.closest('[data-block-anchor]') : null;
        if (!startBlock || !endBlock) {
          return null;
        }
        const measureStart = document.createRange();
        measureStart.selectNodeContents(startBlock);
        measureStart.setEnd(range.startContainer, range.startOffset);
        const measureEnd = document.createRange();
        measureEnd.selectNodeContents(endBlock);
        measureEnd.setEnd(range.endContainer, range.endOffset);
        const startOffset = measureStart.toString().length;
        const endOffset = measureEnd.toString().length;
        if (startBlock === endBlock && startOffset === endOffset) {
          return null;
        }
        const rects = Array.from(range.getClientRects())
          .filter(rect => rect.width > 0 && rect.height > 0)
          .map(rect => ({
            top: rect.top,
            left: rect.left,
            width: rect.width,
            height: rect.height
          }));
        if (rects.length === 0) {
          return null;
        }
        const rect = rects.reduce((acc, item) => ({
          top: Math.min(acc.top, item.top),
          left: Math.min(acc.left, item.left),
          right: Math.max(acc.right, item.left + item.width),
          bottom: Math.max(acc.bottom, item.top + item.height)
        }), {
          top: rects[0].top,
          left: rects[0].left,
          right: rects[0].left + rects[0].width,
          bottom: rects[0].top + rects[0].height
        });
        return {
          blockAnchor: startBlock.dataset.blockAnchor,
          startBlockAnchor: startBlock.dataset.blockAnchor,
          endBlockAnchor: endBlock.dataset.blockAnchor,
          startOffset: startBlock === endBlock
            ? Math.min(startOffset, endOffset)
            : startOffset,
          endOffset: startBlock === endBlock
            ? Math.max(startOffset, endOffset)
            : endOffset,
          selectedText: range.toString(),
          top: rect.top,
          left: rect.left,
          right: rect.right,
          bottom: rect.bottom,
          width: rect.right - rect.left,
          height: rect.bottom - rect.top,
          rects
        };
      }

      function pageBounds() {
        if (!stage || !root) {
          const viewportWidth = window.innerWidth || 1;
          return { viewportWidth, maxOffset: 0 };
        }
        const stageRect = stage.getBoundingClientRect();
        const stageStyles = window.getComputedStyle(stage);
        const paddingLeft = Number.parseFloat(stageStyles.paddingLeft || '0') || 0;
        const paddingRight = Number.parseFloat(stageStyles.paddingRight || '0') || 0;
        const viewportWidth = Math.max(
          1,
          Math.round(stageRect.width - paddingLeft - paddingRight),
        );
        const scrollWidth = Math.max(root.scrollWidth, viewportWidth);
        const maxOffset = Math.max(0, scrollWidth - viewportWidth);
        return { viewportWidth, maxOffset };
      }

      function applyPagedOffset() {
        if (!pagedMode || !root) {
          return;
        }
        root.style.transform = 'translate3d(' + (-currentOffset) + 'px, 0, 0)';
      }

      function updatePagedMetrics() {
        if (!pagedMode || !root || !stage) {
          pageCount = 1;
          currentPage = 0;
          currentOffset = 0;
          return;
        }
        const styles = window.getComputedStyle(root);
        const gap = Number.parseFloat(styles.columnGap || '0') || 0;
        const bounds = pageBounds();
        pageSpan = bounds.viewportWidth + gap;
        const safePageSpan = Math.max(pageSpan, 1);
        pageCount = Math.max(
          1,
          (bounds.maxOffset <= 1
            ? 0
            : Math.floor((bounds.maxOffset - 1) / safePageSpan) + 1) + 1,
        );
        currentPage = Math.max(0, Math.min(currentPage, pageCount - 1));
        currentOffset = Math.min(bounds.maxOffset, currentPage * pageSpan);
        applyPagedOffset();
      }

      function animatePagedCommit(direction, commit) {
        if (!stage || pageAnimationBusy) {
          commit();
          return;
        }
        pageAnimationBusy = true;
        if (pageTurnAnimation === 'roll') {
          const outgoingDistance = pageTurnAxis === 'horizontal' ? 10 : 12;
          const incomingDistance = pageTurnAxis === 'horizontal' ? 18 : 20;
          const outgoingShift = direction > 0 ? -outgoingDistance : outgoingDistance;
          const incomingShift = direction > 0 ? incomingDistance : -incomingDistance;
          const outgoingAngle = direction > 0 ? -14 : 14;
          const incomingAngle = direction > 0 ? 11 : -11;
          const rotateAxis = pageTurnAxis === 'horizontal' ? 'Y' : 'X';
          stage.style.transformOrigin = pageTurnAxis === 'horizontal'
            ? (direction > 0 ? 'right center' : 'left center')
            : (direction > 0 ? 'center top' : 'center bottom');
          stage.style.transition = 'transform 170ms cubic-bezier(0.45, 0, 0.68, 1), opacity 170ms ease, filter 170ms ease';
          stage.style.opacity = '0.93';
          stage.style.filter = 'brightness(0.97)';
          stage.style.transform =
            'perspective(1800px) ' +
            directionalTransform(outgoingShift) +
            ' rotate' + rotateAxis + '(' + outgoingAngle + 'deg) scale(0.986, 0.996)';
          updateTurnShadow(direction, 0.24, false);

          window.setTimeout(function() {
            commit();
            stage.style.transition = 'none';
            stage.style.opacity = '0.985';
            stage.style.filter = 'brightness(1.015)';
            stage.style.transform =
              'perspective(1800px) ' +
              directionalTransform(incomingShift) +
              ' rotate' + rotateAxis + '(' + incomingAngle + 'deg) scale(0.992, 1)';
            updateTurnShadow(direction, 0.18, true);
            afterTwoFrames(function() {
              stage.style.transition = 'transform 260ms cubic-bezier(0.2, 0.72, 0.18, 1), opacity 240ms ease-out, filter 240ms ease-out';
              stage.style.opacity = '1';
              stage.style.filter = 'none';
              stage.style.transform = 'translate3d(0,0,0)';
              if (turnShadow) {
                turnShadow.style.transition = 'opacity 240ms ease-out';
                turnShadow.style.opacity = '0';
              }
              window.setTimeout(function() {
                clearStageAnimationState();
                pageAnimationBusy = false;
              }, 260);
            });
          }, 150);
          return;
        }

        const outgoingDistance = pageTurnAxis === 'horizontal' ? 18 : 24;
        const incomingDistance = pageTurnAxis === 'horizontal' ? 12 : 16;
        const outgoingShift = direction > 0 ? -outgoingDistance : outgoingDistance;
        const incomingShift = direction > 0 ? incomingDistance : -incomingDistance;
        stage.style.transformOrigin = 'center center';
        stage.style.transition = 'transform 150ms cubic-bezier(0.38, 0, 0.7, 1), opacity 150ms linear, filter 150ms ease';
        stage.style.opacity = '0.9';
        stage.style.filter = 'blur(0.7px)';
        stage.style.transform = directionalTransform(outgoingShift);
        updateTurnShadow(direction, 0.12, false);

        window.setTimeout(function() {
          commit();
          stage.style.transition = 'none';
          stage.style.opacity = '0.985';
          stage.style.filter = 'blur(0.45px)';
          stage.style.transform = directionalTransform(incomingShift);
          updateTurnShadow(direction, 0.08, true);
          afterTwoFrames(function() {
            stage.style.transition = 'transform 230ms cubic-bezier(0.22, 0.61, 0.36, 1), opacity 230ms ease-out, filter 230ms ease-out';
            stage.style.opacity = '1';
            stage.style.filter = 'none';
            stage.style.transform = 'translate3d(0,0,0)';
            if (turnShadow) {
              turnShadow.style.transition = 'opacity 220ms ease-out';
              turnShadow.style.opacity = '0';
            }
            window.setTimeout(function() {
              clearStageAnimationState();
              pageAnimationBusy = false;
            }, 230);
          });
        }, 110);
      }

      function playBoundaryTransition(direction) {
        if (!stage || pageAnimationBusy) {
          return;
        }
        pageAnimationBusy = true;
        if (pageTurnAnimation === 'roll') {
          const incomingDistance = pageTurnAxis === 'horizontal' ? 20 : 22;
          const incomingShift = direction > 0 ? incomingDistance : -incomingDistance;
          const incomingAngle = direction > 0 ? 12 : -12;
          const rotateAxis = pageTurnAxis === 'horizontal' ? 'Y' : 'X';
          stage.style.transformOrigin = pageTurnAxis === 'horizontal'
            ? (direction > 0 ? 'right center' : 'left center')
            : (direction > 0 ? 'center bottom' : 'center top');
          stage.style.transition = 'none';
          stage.style.opacity = '0.985';
          stage.style.filter = 'brightness(1.02)';
          stage.style.transform =
            'perspective(1800px) ' +
            directionalTransform(incomingShift) +
            ' rotate' + rotateAxis + '(' + incomingAngle + 'deg) scale(0.992, 1)';
          updateTurnShadow(direction, 0.18, true);
          afterTwoFrames(function() {
            stage.style.transition = 'transform 250ms cubic-bezier(0.2, 0.72, 0.18, 1), opacity 240ms ease-out, filter 240ms ease-out';
            stage.style.opacity = '1';
            stage.style.filter = 'none';
            stage.style.transform = 'translate3d(0,0,0)';
            if (turnShadow) {
              turnShadow.style.transition = 'opacity 220ms ease-out';
              turnShadow.style.opacity = '0';
            }
            window.setTimeout(function() {
              clearStageAnimationState();
              pageAnimationBusy = false;
            }, 250);
          });
          return;
        }

        const incomingDistance = pageTurnAxis === 'horizontal' ? 12 : 16;
        const incomingShift = direction > 0 ? incomingDistance : -incomingDistance;
        stage.style.transformOrigin = 'center center';
        stage.style.transition = 'none';
        stage.style.opacity = '0.985';
        stage.style.filter = 'blur(0.45px)';
        stage.style.transform = directionalTransform(incomingShift);
        updateTurnShadow(direction, 0.08, true);
        afterTwoFrames(function() {
          stage.style.transition = 'transform 220ms cubic-bezier(0.22, 0.61, 0.36, 1), opacity 220ms ease-out, filter 220ms ease-out';
          stage.style.opacity = '1';
          stage.style.filter = 'none';
          stage.style.transform = 'translate3d(0,0,0)';
          if (turnShadow) {
            turnShadow.style.transition = 'opacity 200ms ease-out';
            turnShadow.style.opacity = '0';
          }
          window.setTimeout(function() {
            clearStageAnimationState();
            pageAnimationBusy = false;
          }, 220);
        });
      }

      function goToPage(targetPage, animate) {
        if (!pagedMode) {
          return false;
        }
        const nextPage = Math.max(0, Math.min(targetPage, pageCount - 1));
        if (nextPage === currentPage) {
          return false;
        }
        const direction = nextPage > currentPage ? 1 : -1;
        const commit = function() {
          currentPage = nextPage;
          const bounds = pageBounds();
          currentOffset = Math.min(bounds.maxOffset, currentPage * pageSpan);
          applyPagedOffset();
        };
        if (!animate) {
          commit();
          return true;
        }
        animatePagedCommit(direction, commit);
        return true;
      }

      function handlePageTurn(direction) {
        if (!pagedMode) {
          return false;
        }
        const targetPage = currentPage + direction;
        if (targetPage < 0) {
          send({ type: 'previousChapter' });
          return true;
        }
        if (targetPage >= pageCount) {
          send({ type: 'nextChapter' });
          return true;
        }
        return goToPage(targetPage, true);
      }

      function mobilePageStep() {
        if (!stage) {
          return window.innerHeight * 0.82;
        }
        return Math.max(120, stage.clientHeight * 0.82);
      }

      function mobileScrollBoundary() {
        if (!stage) {
          return { top: true, bottom: true };
        }
        const maxScroll = Math.max(0, stage.scrollHeight - stage.clientHeight);
        return {
          top: stage.scrollTop <= 4,
          bottom: stage.scrollTop >= (maxScroll - 4)
        };
      }

      function handleMobilePageTurn(direction) {
        if (!stage || pagedMode) {
          return false;
        }
        const step = mobilePageStep();
        const boundary = mobileScrollBoundary();
        if (direction < 0 && boundary.top) {
          send({ type: 'previousChapter' });
          return true;
        }
        if (direction > 0 && boundary.bottom) {
          send({ type: 'nextChapter' });
          return true;
        }
        const nextTop = Math.max(
          0,
          Math.min(
            stage.scrollTop + (direction * step),
            Math.max(0, stage.scrollHeight - stage.clientHeight),
          ),
        );
        stage.scrollTo({
          top: nextTop,
          behavior: 'smooth',
        });
        return true;
      }

      function renderSelectionOverlay(data) {
        if (!overlay) return;
        overlay.replaceChildren();
        for (const rect of data.rects || []) {
          const verticalInset = Math.min(4, rect.height * 0.14);
          const segment = document.createElement('div');
          segment.className = 'segment';
          segment.style.top = (rect.top + verticalInset) + 'px';
          segment.style.left = rect.left + 'px';
          segment.style.width = rect.width + 'px';
          segment.style.height = Math.max(8, rect.height - (verticalInset * 2)) + 'px';
          overlay.appendChild(segment);
        }
        overlay.style.display = 'block';
      }

      function cancelNativeSelectionClear() {
        if (nativeSelectionClearTimer) {
          window.clearTimeout(nativeSelectionClearTimer);
          nativeSelectionClearTimer = null;
        }
      }

      function clearNativeSelectionOnly() {
        preservingSelectionUi = true;
        const selection = window.getSelection();
        if (selection) {
          selection.removeAllRanges();
        }
      }

      function scheduleNativeSelectionClear(delay) {
        cancelNativeSelectionClear();
        nativeSelectionClearTimer = window.setTimeout(function() {
          clearNativeSelectionOnly();
          nativeSelectionClearTimer = null;
        }, delay);
      }

      function cancelSelectionRefresh() {
        if (selectionRefreshTimer) {
          window.clearTimeout(selectionRefreshTimer);
          selectionRefreshTimer = null;
        }
      }

      function scheduleSelectionRefresh(delay) {
        cancelSelectionRefresh();
        selectionRefreshTimer = window.setTimeout(function() {
          selectionRefreshTimer = null;
          handleSelectionChange();
        }, delay);
      }

      function viewportMetrics() {
        const visualViewport = window.visualViewport;
        if (!visualViewport) {
          return {
            width: window.innerWidth || document.documentElement.clientWidth || 1,
            height: window.innerHeight || document.documentElement.clientHeight || 1,
            offsetLeft: 0,
            offsetTop: 0
          };
        }
        return {
          width: visualViewport.width,
          height: visualViewport.height,
          offsetLeft: visualViewport.offsetLeft,
          offsetTop: visualViewport.offsetTop
        };
      }

      function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
      }

      function selectionPayload() {
        if (!currentSelection) {
          return null;
        }
        return {
          blockAnchor: currentSelection.blockAnchor,
          startBlockAnchor: currentSelection.startBlockAnchor || currentSelection.blockAnchor,
          endBlockAnchor: currentSelection.endBlockAnchor || currentSelection.blockAnchor,
          startOffset: currentSelection.startOffset,
          endOffset: currentSelection.endOffset,
          selectedText: currentSelection.selectedText
        };
      }

      function sendSelectionAction(type, extras) {
        const payload = selectionPayload();
        if (!payload) {
          return;
        }
        send(Object.assign({ type: type }, payload, extras || {}));
      }

      function setSelectedColor(color) {
        selectedColor = color || defaultAnnotationColor;
        if (!colorRow) {
          return;
        }
        Array.from(colorRow.querySelectorAll('button[data-color]')).forEach(function(button) {
          button.classList.toggle('selected', button.dataset.color === selectedColor);
        });
      }

      function setSelectedUnderline(style) {
        selectedUnderline = style || 'none';
        if (!underlineRow) {
          return;
        }
        Array.from(underlineRow.querySelectorAll('button[data-underline]')).forEach(function(button) {
          button.classList.toggle('selected', button.dataset.underline === selectedUnderline);
        });
      }

      function buildComposerControls() {
        if (colorRow && colorRow.children.length === 0) {
          annotationColors.forEach(function(color) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'reader-color-button';
            button.dataset.color = color;
            button.style.background = color;
            button.setAttribute('aria-label', '选择颜色 ' + color);
            colorRow.appendChild(button);
          });
        }
        if (underlineRow && underlineRow.children.length === 0) {
          underlineOptions.forEach(function(option) {
            const button = document.createElement('button');
            button.type = 'button';
            button.dataset.underline = option.value;
            button.textContent = option.label;
            underlineRow.appendChild(button);
          });
        }
        setSelectedColor(selectedColor);
        setSelectedUnderline(selectedUnderline);
      }

      function placeToolbar(data, mode) {
        if (!toolbar) return;
        const metrics = viewportMetrics();
        const safe = 12;
        toolbar.style.display = 'block';
        toolbar.style.visibility = 'hidden';
        toolbar.classList.toggle('composing', mode === 'composer');
        if (mode !== 'composer') {
          toolbar.style.width = '';
        }
        const rect = toolbar.getBoundingClientRect();
        const width = Math.min(rect.width || (mode === 'composer' ? 340 : 158), metrics.width - (safe * 2));
        const height = rect.height || (mode === 'composer' ? 300 : 46);
        const centered = data.left + (data.width / 2) - (width / 2);
        const left = metrics.offsetLeft + clamp(centered, safe, metrics.width - width - safe);
        const above = data.top - height - 10;
        const below = data.bottom + 10;
        const topWithinVisualViewport = metrics.offsetTop + safe;
        const bottomWithinVisualViewport = metrics.offsetTop + metrics.height - height - safe;
        const top = above >= topWithinVisualViewport
          ? above
          : clamp(below, topWithinVisualViewport, bottomWithinVisualViewport);
        toolbar.style.width = mode === 'composer' ? width + 'px' : '';
        toolbar.style.left = left + 'px';
        toolbar.style.top = top + 'px';
        toolbar.style.visibility = 'visible';
      }

      function showQuickbar(data) {
        if (!toolbar) return;
        composerOpen = false;
        toolbar.classList.remove('composing');
        if (noteInput) {
          noteInput.value = '';
        }
        placeToolbar(data, 'quickbar');
      }

      function showComposer() {
        if (!toolbar || !currentSelection) {
          return;
        }
        composerOpen = true;
        buildComposerControls();
        if (quotePreview) {
          quotePreview.textContent = currentSelection.selectedText || '';
        }
        if (noteInput) {
          noteInput.value = '';
        }
        selectedColor = defaultAnnotationColor;
        selectedUnderline = 'none';
        setSelectedColor(selectedColor);
        setSelectedUnderline(selectedUnderline);
        placeToolbar(currentSelection, 'composer');
        window.setTimeout(function() {
          if (!currentSelection) {
            return;
          }
          if (noteInput) {
            noteInput.focus({ preventScroll: true });
          }
          placeToolbar(currentSelection, 'composer');
        }, 60);
      }

      function clearSelectionUi() {
        currentSelection = null;
        composerOpen = false;
        preservingSelectionUi = false;
        cancelNativeSelectionClear();
        if (toolbar) {
          toolbar.style.display = 'none';
          toolbar.style.visibility = 'visible';
          toolbar.style.width = '';
          toolbar.classList.remove('composing');
        }
        if (overlay) {
          overlay.replaceChildren();
          overlay.style.display = 'none';
        }
      }

      function handleSelectionChange() {
        cancelNativeSelectionClear();
        const data = selectionData();
        if (!data) {
          if (
            composerOpen &&
            currentSelection &&
            toolbar &&
            toolbar.contains(document.activeElement)
          ) {
            preservingSelectionUi = false;
            return;
          }
          if (preservingSelectionUi && currentSelection) {
            preservingSelectionUi = false;
            return;
          }
          clearSelectionUi();
          return;
        }
        preservingSelectionUi = false;
        currentSelection = data;
        renderSelectionOverlay(data);
        if (composerOpen) {
          placeToolbar(data, 'composer');
        } else {
          showQuickbar(data);
        }
      }

      function handleDocumentTap(target, clientX) {
        const annotationTarget = target && typeof target.closest === 'function'
          ? target.closest('[data-annotation-ids]')
          : null;
        if (annotationTarget) {
          clearSelectionUi();
          const ids = (annotationTarget.dataset.annotationIds || '')
            .split(',')
            .map(item => Number(item))
            .filter(item => Number.isFinite(item));
          send({ type: 'annotationTap', annotationIds: ids });
          return;
        }

        const selection = window.getSelection();
        if (selection && !selection.isCollapsed) {
          return;
        }
        const toolbarTarget = target && typeof target.closest === 'function'
          ? target.closest('#reader-toolbar')
          : null;
        if (toolbarTarget) {
          return;
        }
        if (currentSelection) {
          clearSelectionUi();
          return;
        }
        if (pagedMode) {
          const ratio = window.innerWidth <= 0 ? 0.5 : clientX / window.innerWidth;
          if (ratio <= 0.32) {
            handlePageTurn(-1);
            return;
          }
          if (ratio >= 0.68) {
            handlePageTurn(1);
            return;
          }
          send({ type: 'toggleUi' });
          return;
        }
        const ratio = window.innerWidth <= 0 ? 0.5 : clientX / window.innerWidth;
        if (ratio <= 0.18) {
          handleMobilePageTurn(-1);
          return;
        }
        if (ratio >= 0.82) {
          handleMobilePageTurn(1);
          return;
        }
        send({ type: 'toggleUi' });
      }

      document.addEventListener('selectionchange', handleSelectionChange);
      document.addEventListener('touchstart', function(event) {
        cancelNativeSelectionClear();
        cancelSelectionRefresh();
        const touch = event.touches && event.touches.length > 0 ? event.touches[0] : null;
        if (!touch) {
          touchTracking = false;
          touchMoved = false;
          return;
        }
        touchTracking = true;
        touchMoved = false;
        touchStartX = touch.clientX;
        touchStartY = touch.clientY;
        touchStartAt = Date.now();
      }, { passive: true });
      document.addEventListener('touchmove', function(event) {
        if (!touchTracking) {
          return;
        }
        cancelSelectionRefresh();
        const touch = event.touches && event.touches.length > 0 ? event.touches[0] : null;
        if (!touch) {
          return;
        }
        if (Math.abs(touch.clientX - touchStartX) > 12 || Math.abs(touch.clientY - touchStartY) > 12) {
          touchMoved = true;
        }
      }, { passive: true });
      document.addEventListener('touchcancel', function() {
        touchTracking = false;
        touchMoved = false;
        touchStartAt = 0;
      }, { passive: true });
      document.addEventListener('touchend', function(event) {
        const touch = event.changedTouches && event.changedTouches.length > 0
          ? event.changedTouches[0]
          : null;
        const touchDuration = touchStartAt > 0 ? Date.now() - touchStartAt : 0;
        const selectionGesture = touchDuration >= 280;
        const domSelectionActive = hasActiveDomSelection();
        scheduleSelectionRefresh(selectionGesture ? 20 : 60);
        if (!currentSelection && !domSelectionActive && !selectionGesture) {
          if (touchTracking && !touchMoved && touch) {
            lastTouchHandledAt = Date.now();
            handleDocumentTap(event.target, touch.clientX);
          }
          touchTracking = false;
          touchMoved = false;
          touchStartAt = 0;
          return;
        }
        if (currentSelection || domSelectionActive) {
          scheduleNativeSelectionClear(260);
        }
        touchTracking = false;
        touchMoved = false;
        touchStartAt = 0;
      }, { passive: true });
      document.addEventListener('mouseup', function() {
        scheduleSelectionRefresh(20);
      });
      document.addEventListener('scroll', function(event) {
        if (toolbar && event.target && toolbar.contains(event.target)) {
          return;
        }
        clearSelectionUi();
      }, true);
      if (stage) {
        stage.addEventListener('scroll', clearSelectionUi, { passive: true });
      }
      window.addEventListener('resize', function() {
        if (currentSelection) {
          placeToolbar(currentSelection, composerOpen ? 'composer' : 'quickbar');
        } else {
          clearSelectionUi();
        }
        updatePagedMetrics();
      });
      if (window.visualViewport) {
        window.visualViewport.addEventListener('resize', function() {
          if (currentSelection) {
            placeToolbar(currentSelection, composerOpen ? 'composer' : 'quickbar');
          }
        });
        window.visualViewport.addEventListener('scroll', function() {
          if (currentSelection) {
            placeToolbar(currentSelection, composerOpen ? 'composer' : 'quickbar');
          }
        });
      }
      document.addEventListener('contextmenu', function(event) {
        const data = selectionData();
        if (!data) {
          return;
        }
        event.preventDefault();
        currentSelection = data;
        renderSelectionOverlay(data);
        showQuickbar(data);
        scheduleNativeSelectionClear(120);
      });

      if (toolbar) {
        ['pointerdown', 'touchstart', 'mousedown'].forEach(function(eventName) {
          toolbar.addEventListener(eventName, function(event) {
            event.stopPropagation();
            cancelNativeSelectionClear();
            const target = event.target;
            const editableTarget = target && typeof target.closest === 'function'
              ? target.closest('textarea')
              : null;
            if (!editableTarget) {
              event.preventDefault();
            }
          }, { passive: false });
        });
        toolbar.addEventListener('click', function(event) {
          const target = event.target;
          const button = target && typeof target.closest === 'function'
            ? target.closest('button[data-action]')
            : null;
          if (!button || !currentSelection) {
            return;
          }
          event.preventDefault();
          event.stopPropagation();
          const action = button.dataset.action;
          if (action === 'compose') {
            showComposer();
            return;
          }
          if (action === 'cancelCompose') {
            showQuickbar(currentSelection);
            return;
          }
          if (action === 'saveAnnotation') {
            sendSelectionAction('saveAnnotation', {
              noteText: noteInput ? noteInput.value : '',
              color: selectedColor,
              underlineStyle: selectedUnderline
            });
            button.disabled = true;
            window.setTimeout(function() {
              button.disabled = false;
            }, 900);
            return;
          }
          sendSelectionAction(action);
        });
      }

      if (colorRow) {
        colorRow.addEventListener('click', function(event) {
          const target = event.target;
          const button = target && typeof target.closest === 'function'
            ? target.closest('button[data-color]')
            : null;
          if (!button) {
            return;
          }
          event.preventDefault();
          event.stopPropagation();
          setSelectedColor(button.dataset.color);
        });
      }

      if (underlineRow) {
        underlineRow.addEventListener('click', function(event) {
          const target = event.target;
          const button = target && typeof target.closest === 'function'
            ? target.closest('button[data-underline]')
            : null;
          if (!button) {
            return;
          }
          event.preventDefault();
          event.stopPropagation();
          setSelectedUnderline(button.dataset.underline);
        });
      }

      document.addEventListener('click', function(event) {
        if (Date.now() - lastTouchHandledAt < 400) {
          return;
        }
        handleDocumentTap(event.target, event.clientX);
      });

      window.readerClearSelectionUi = function() {
        clearNativeSelectionOnly();
        clearSelectionUi();
      };

      window.readerSetChromeVisible = function(visible) {
        document.body.classList.toggle('reader-ui-hidden', !visible);
      };

      window.readerApplyLayout = function() {
        updatePagedMetrics();
      };

      window.readerPlayBoundaryTransition = function(direction) {
        if (!pagedMode) {
          return;
        }
        playBoundaryTransition(direction >= 0 ? 1 : -1);
      };

      window.readerHandleTapZone = function(zone) {
        if (zone === 'left') {
          handlePageTurn(-1);
          return;
        }
        if (zone === 'right') {
          handlePageTurn(1);
          return;
        }
        send({ type: 'toggleUi' });
      };

      window.readerScrollToBoundary = function(boundary) {
        if (!pagedMode) {
          if (boundary === 'end' && stage) {
            stage.scrollTo({
              top: Math.max(0, stage.scrollHeight - stage.clientHeight),
              behavior: 'auto',
            });
            return;
          }
          if (boundary === 'start' && stage) {
            stage.scrollTo({ top: 0, behavior: 'auto' });
          }
          return;
        }
        updatePagedMetrics();
        if (boundary === 'end') {
          goToPage(Math.max(0, pageCount - 1), false);
          return;
        }
        goToPage(0, false);
      };

      window.readerScrollToAnchor = function(anchor) {
        if (!anchor) return;
        const target = Array.from(document.querySelectorAll('[data-anchor], [data-block-anchor]'))
          .find(node => node.dataset.anchor === anchor || node.dataset.blockAnchor === anchor);
        if (!target) return;
        if (pagedMode && stage) {
          updatePagedMetrics();
          const stageRect = stage.getBoundingClientRect();
          const targetRect = target.getBoundingClientRect();
          const absoluteX = currentOffset + Math.max(0, targetRect.left - stageRect.left);
          const targetPage = Math.max(
            0,
            Math.min(pageCount - 1, Math.floor(absoluteX / Math.max(pageSpan, 1))),
          );
          goToPage(targetPage, false);
        }
        target.classList.remove('reader-anchor-pulse');
        if (!pagedMode) {
          target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
        window.setTimeout(() => target.classList.add('reader-anchor-pulse'), 40);
      };

      afterStableLayout(function() {
        updatePagedMetrics();
        sendReady();
      });
    })();
  </script>
</body>
</html>
''';
  }

  String _buildBlockHtml(
    BookContentBlock block,
    List<String> orderedBlockAnchors,
  ) {
    final blockText = block.renderedText;
    final blockAnnotations =
        widget.annotations
            .where(
              (annotation) =>
                  AnnotationAnchor.parse(annotation.anchor).affectsBlock(
                    currentBlockAnchor: block.anchor,
                    orderedBlockAnchors: orderedBlockAnchors,
                  ),
            )
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    final legacyHighlight = blockAnnotations.firstWhere(
      (annotation) =>
          !AnnotationAnchor.parse(annotation.anchor).hasExplicitRange,
      orElse: () => const AnnotationView(
        id: -1,
        bookId: -1,
        quoteText: null,
        noteText: null,
        color: null,
        anchor: '',
        version: 0,
        deleted: false,
        updatedAt: '',
      ),
    );
    final legacyStyle =
        legacyHighlight.id > 0 || legacyHighlight.anchor.isNotEmpty
        ? ' style="background:${_cssColor(_annotationBackgroundColor(legacyHighlight))};"'
        : '';
    final content = switch (block.type) {
      'divider' => _escapeHtml(blockText.isEmpty ? '···' : blockText),
      _ => _buildAnnotatedInlineHtml(
        block,
        blockAnnotations,
        orderedBlockAnchors,
      ),
    };

    final tag = switch (block.type) {
      'heading' => 'h2',
      'quote' => 'blockquote',
      'divider' => 'div',
      _ => 'p',
    };
    final extraClass =
        legacyHighlight.id > 0 || legacyHighlight.anchor.isNotEmpty
        ? ' legacy-highlight'
        : '';
    return '<$tag class="reader-block$extraClass" data-type="${_escapeHtml(block.type)}" data-block-anchor="${_escapeHtml(block.anchor)}" data-anchor="${_escapeHtml(block.anchor)}"$legacyStyle>$content</$tag>';
  }

  String _buildAnnotatedInlineHtml(
    BookContentBlock block,
    List<AnnotationView> annotations,
    List<String> orderedBlockAnchors,
  ) {
    final blockText = block.renderedText;
    final explicit =
        annotations
            .map((annotation) {
              final resolved = ResolvedAnnotation.fromAnnotation(
                annotation,
                blockText,
                currentBlockAnchor: block.anchor,
                orderedBlockAnchors: orderedBlockAnchors,
              );
              if (resolved == null || !resolved.anchor.hasExplicitRange) {
                return null;
              }
              return resolved;
            })
            .whereType<ResolvedAnnotation>()
            .toList()
          ..sort(
            (left, right) => left.range.start.compareTo(right.range.start),
          );

    if (explicit.isEmpty) {
      return _escapeHtml(blockText);
    }

    final buffer = StringBuffer();
    var cursor = 0;
    for (final annotation in explicit) {
      final start = annotation.range.start.clamp(0, blockText.length);
      final end = annotation.range.end.clamp(0, blockText.length);
      if (end <= start || start < cursor) {
        continue;
      }
      if (start > cursor) {
        buffer.write(_escapeHtml(blockText.substring(cursor, start)));
      }
      final chunk = blockText.substring(start, end);
      final color = _annotationLineColor(annotation.annotation);
      final background = _annotationBackgroundColor(annotation.annotation);
      final underlineClass = switch (annotation.anchor.underlineStyle) {
        AnnotationUnderlineStyle.none => '',
        AnnotationUnderlineStyle.solid => ' has-underline underline-solid',
        AnnotationUnderlineStyle.dotted => ' has-underline underline-dotted',
        AnnotationUnderlineStyle.wavy => ' has-underline underline-wavy',
      };
      buffer.write(
        '<span class="annot$underlineClass" '
        'data-annotation-ids="${annotation.annotation.id}" '
        'style="--annot-bg:${_cssColor(background)};'
        '${annotation.anchor.underlineStyle == AnnotationUnderlineStyle.none ? '' : 'text-decoration-color:${_cssColor(color)};'}">'
        '${_escapeHtml(chunk)}</span>',
      );
      cursor = end;
    }
    if (cursor < blockText.length) {
      buffer.write(_escapeHtml(blockText.substring(cursor)));
    }
    return buffer.toString();
  }

  Color _annotationLineColor(AnnotationView annotation) {
    if (annotation.color == null || annotation.color!.isEmpty) {
      return const Color(0xFFC3924A);
    }
    return Color(int.parse('0xFF${annotation.color!.substring(1)}'));
  }

  Color _annotationBackgroundColor(AnnotationView annotation) {
    return _annotationLineColor(annotation).withValues(alpha: 0.2);
  }

  String _defaultAnnotationColor(ReaderThemeMode themeMode) {
    return switch (themeMode) {
      ReaderThemeMode.eyeCare => '#4A6B3F',
      ReaderThemeMode.night => '#C3924A',
      ReaderThemeMode.paper || ReaderThemeMode.kraft => '#7A4A24',
    };
  }

  String _normalizeAnnotationColor(String? color) {
    final candidate = color?.trim();
    if (candidate == null ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(candidate)) {
      return _defaultAnnotationColor(widget.preferences.themeMode);
    }
    return candidate.toUpperCase();
  }

  String _fontCss({
    required double fontSize,
    required double lineHeight,
    String fontStyle = 'normal',
  }) {
    return '''
font-size: ${fontSize.toStringAsFixed(2)}px;
line-height: ${lineHeight.toStringAsFixed(3)};
font-style: $fontStyle;
font-family: ${_fontStackCss()};
''';
  }

  String _fontStackCss() {
    return switch (widget.preferences.fontFamily) {
      ReaderFontFamilyPreference.sans =>
        '"Noto Sans SC", "PingFang SC", "Microsoft YaHei", sans-serif',
      ReaderFontFamilyPreference.serif =>
        '"Noto Serif SC", "Source Han Serif SC", "Songti SC", serif',
      ReaderFontFamilyPreference.system =>
        '"PingFang SC", "Microsoft YaHei", "Noto Sans SC", sans-serif',
    };
  }

  String _cssColor(Color color) {
    final alpha = color.a.clamp(0, 1).toStringAsFixed(3);
    final red = (color.r * 255.0).round().clamp(0, 255);
    final green = (color.g * 255.0).round().clamp(0, 255);
    final blue = (color.b * 255.0).round().clamp(0, 255);
    return 'rgba($red, $green, $blue, $alpha)';
  }

  String _escapeHtml(String text) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(text);
  }

  GlobalKey _fallbackKeyForAnchor(String anchor) {
    return _fallbackAnchorKeys.putIfAbsent(anchor, GlobalKey.new);
  }
}

class _ReaderLoadingOverlay extends StatelessWidget {
  const _ReaderLoadingOverlay({
    required this.chapter,
    required this.annotations,
    required this.preferences,
    required this.palette,
    required this.pagedMode,
    required this.onHighlight,
    required this.onAnnotate,
    required this.onOpenAnnotations,
    required this.keyForAnchor,
  });

  final BookContentChapter chapter;
  final List<AnnotationView> annotations;
  final ReaderPreferences preferences;
  final AppReaderPalette palette;
  final bool pagedMode;
  final Future<void> Function(
    AnnotationSelection selection,
    AnnotationView? existingAnnotation,
  )
  onHighlight;
  final Future<void> Function(
    AnnotationSelection selection,
    AnnotationView? existingAnnotation,
  )
  onAnnotate;
  final Future<void> Function(List<AnnotationView> annotations)
  onOpenAnnotations;
  final GlobalKey Function(String anchor) keyForAnchor;

  @override
  Widget build(BuildContext context) {
    if (pagedMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(44, 40, 44, 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReaderLoadingBar(
                  widthFactor: 0.36,
                  color: palette.line.withValues(alpha: 0.55),
                  height: 18,
                ),
                const SizedBox(height: 28),
                _ReaderLoadingBar(
                  widthFactor: 1,
                  color: palette.line.withValues(alpha: 0.28),
                ),
                const SizedBox(height: 16),
                _ReaderLoadingBar(
                  widthFactor: 0.96,
                  color: palette.line.withValues(alpha: 0.24),
                ),
                const SizedBox(height: 16),
                _ReaderLoadingBar(
                  widthFactor: 0.92,
                  color: palette.line.withValues(alpha: 0.24),
                ),
                const SizedBox(height: 28),
                _ReaderLoadingBar(
                  widthFactor: 0.94,
                  color: palette.line.withValues(alpha: 0.24),
                ),
                const SizedBox(height: 16),
                _ReaderLoadingBar(
                  widthFactor: 0.98,
                  color: palette.line.withValues(alpha: 0.24),
                ),
                const SizedBox(height: 16),
                _ReaderLoadingBar(
                  widthFactor: 0.9,
                  color: palette.line.withValues(alpha: 0.24),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Opacity(
        opacity: 0.96,
        child: ReaderBlocksView(
          blocks: chapter.blocks,
          annotations: annotations,
          preferences: preferences,
          onHighlight: onHighlight,
          onAnnotate: onAnnotate,
          onOpenAnnotations: onOpenAnnotations,
          keyForAnchor: keyForAnchor,
        ),
      ),
    );
  }
}

class _ReaderLoadingBar extends StatelessWidget {
  const _ReaderLoadingBar({
    required this.widthFactor,
    required this.color,
    this.height = 14,
  });

  final double widthFactor;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: SizedBox(height: height),
      ),
    );
  }
}

class _SelectionIntent {
  const _SelectionIntent({
    required this.selection,
    required this.existingAnnotation,
  });

  final AnnotationSelection selection;
  final AnnotationView? existingAnnotation;
}
