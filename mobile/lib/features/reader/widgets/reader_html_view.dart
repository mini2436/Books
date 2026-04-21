import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/models/book_models.dart';
import '../../../data/models/sync_models.dart';
import '../../../features/settings/reader_preferences_controller.dart';
import '../../../shared/theme/reader_theme_extension.dart';
import '../models/annotation_anchor.dart';
import 'reader_blocks.dart';

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
  int _lastAnchorJumpVersion = -1;
  final Map<String, GlobalKey> _fallbackAnchorKeys = <String, GlobalKey>{};
  Timer? _blankPageGuard;

  bool get _allowFlutterFallback => !widget.pagedMode;

  @override
  void initState() {
    super.initState();
    _lastHtml = _buildHtml();
    _controller = WebViewController()
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
            _pageReady = true;
            await _controller.runJavaScript(
              'if (window.readerApplyLayout) { window.readerApplyLayout(); }',
            );
            await _controller.runJavaScript(
              'if (window.readerSetChromeVisible) { window.readerSetChromeVisible(${widget.uiVisible ? 'true' : 'false'}); }',
            );
            await _verifyRenderedContent();
            await _scrollToFocusedAnchor();
          },
        ),
      )
      ..addJavaScriptChannel(
        'ReaderBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..loadHtmlString(_lastHtml);
    _armBlankPageGuard();
  }

  @override
  void didUpdateWidget(covariant ReaderHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextHtml = _buildHtml();
    if (nextHtml != _lastHtml) {
      _lastHtml = nextHtml;
      _pageReady = false;
      _useFlutterFallback = false;
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
      return SingleChildScrollView(
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
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: widget.palette.background),
      child: WebViewWidget(controller: _controller),
    );
  }

  @override
  void dispose() {
    _blankPageGuard?.cancel();
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
        final selection = _selectionFromPayload(payload);
        if (selection == null) {
          return;
        }
        final intent = _resolveSelectionIntent(selection);
        if (payload['type'] == 'highlight') {
          await widget.onHighlight(intent.selection, intent.existingAnnotation);
        } else {
          await widget.onAnnotate(intent.selection, intent.existingAnnotation);
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
    if (!_pageReady) {
      if (zone == 'left') {
        await widget.onPageBoundaryPrevious();
        return;
      }
      if (zone == 'right') {
        await widget.onPageBoundaryNext();
        return;
      }
      widget.onMenuRequest();
      return;
    }
    final escapedZone = jsonEncode(zone);
    await _controller.runJavaScript(
      'window.readerHandleTapZone($escapedZone);',
    );
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
      if (!mounted || _useFlutterFallback) {
        return;
      }
      await _verifyRenderedContent();
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
        'Paged tablet mode keeps WebView active; suppressing Flutter fallback.',
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

  Future<void> _scrollToFocusedAnchor() async {
    if (!_pageReady) {
      return;
    }
    if (_lastAnchorJumpVersion == widget.anchorJumpVersion) {
      return;
    }
    _lastAnchorJumpVersion = widget.anchorJumpVersion;
    final anchor = AnnotationAnchor.parse(
      widget.focusedAnchor ?? '',
    ).blockAnchor;
    if (anchor.isEmpty) {
      return;
    }
    final escapedAnchor = jsonEncode(anchor);
    await _controller.runJavaScript(
      'window.readerScrollToAnchor($escapedAnchor);',
    );
  }

  AnnotationSelection? _selectionFromPayload(Map<String, dynamic> payload) {
    final blockAnchor = payload['blockAnchor'] as String? ?? '';
    final startOffset = (payload['startOffset'] as num?)?.toInt();
    final endOffset = (payload['endOffset'] as num?)?.toInt();
    if (blockAnchor.isEmpty || startOffset == null || endOffset == null) {
      return null;
    }
    final block = widget.chapter.blocks.cast<BookContentBlock?>().firstWhere(
      (item) => item?.anchor == blockAnchor,
      orElse: () => null,
    );
    if (block == null) {
      return null;
    }
    final blockText = block.renderedText;
    final normalizedStart = startOffset < endOffset ? startOffset : endOffset;
    final normalizedEnd = startOffset < endOffset ? endOffset : startOffset;
    if (normalizedStart < 0 ||
        normalizedEnd > blockText.length ||
        normalizedStart == normalizedEnd) {
      return null;
    }
    return AnnotationSelection(
      blockAnchor: blockAnchor,
      blockText: blockText,
      startOffset: normalizedStart,
      endOffset: normalizedEnd,
    );
  }

  _SelectionIntent _resolveSelectionIntent(AnnotationSelection selection) {
    final blockAnnotations = widget.annotations
        .map(
          (annotation) => ResolvedAnnotation.fromAnnotation(
            annotation,
            selection.blockText,
          ),
        )
        .whereType<ResolvedAnnotation>()
        .where(
          (annotation) =>
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
    final htmlBlocks = widget.chapter.blocks
        .map((block) => _buildBlockHtml(block))
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
      -webkit-overflow-scrolling: touch;
      background: var(--reader-bg);
      padding: 0 0 28px;
    }
    #reader-root {
      padding: 0;
      will-change: transform;
    }
    body.reader-paged #reader-stage {
      padding: 24px 28px 28px;
      overflow: hidden;
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
      gap: 8px;
      padding: 8px;
      border-radius: 999px;
      background: rgba(24, 24, 28, 0.94);
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.22);
    }
    .reader-toolbar button {
      border: 0;
      border-radius: 999px;
      padding: 8px 14px;
      font-size: 14px;
      color: #fff;
      background: transparent;
    }
    .reader-toolbar button.primary {
      background: ${_cssColor(widget.palette.accent)};
      color: ${_cssColor(widget.palette.background)};
      font-weight: 600;
    }
    body.reader-ui-hidden .reader-toolbar {
      display: none !important;
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
  </style>
</head>
<body${bodyClasses.isEmpty ? '' : ' class="$bodyClasses"'}>
  <div id="reader-stage">
    <div id="reader-root">$htmlBlocks</div>
  </div>
  <div id="reader-selection-overlay" class="reader-selection-overlay"></div>
  <div id="reader-toolbar" class="reader-toolbar">
    <button type="button" data-action="highlight">高亮</button>
    <button type="button" class="primary" data-action="annotate">批注</button>
  </div>
  <script>
    (function() {
      const bridge = window.ReaderBridge;
      const stage = document.getElementById('reader-stage');
      const root = document.getElementById('reader-root');
      const toolbar = document.getElementById('reader-toolbar');
      const overlay = document.getElementById('reader-selection-overlay');
      const pagedMode = ${widget.pagedMode ? 'true' : 'false'};
      const pageTurnAxis = ${jsonEncode(widget.preferences.tabletPageTurnAxis.storageValue)};
      const pageTurnAnimation = ${jsonEncode(widget.preferences.tabletPageTurnAnimation.storageValue)};
      let currentSelection = null;
      let nativeSelectionClearTimer = null;
      let preservingSelectionUi = false;
      let currentPage = 0;
      let pageCount = 1;
      let pageSpan = 0;
      let currentOffset = 0;
      let pageAnimationBusy = false;
      let touchStartX = 0;
      let touchStartY = 0;
      let touchMoved = false;
      let touchTracking = false;
      let lastTouchHandledAt = 0;

      function send(payload) {
        if (!bridge || !bridge.postMessage) return;
        bridge.postMessage(JSON.stringify(payload));
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
        if (!startBlock || !endBlock || startBlock !== endBlock) {
          return null;
        }
        const measureStart = document.createRange();
        measureStart.selectNodeContents(startBlock);
        measureStart.setEnd(range.startContainer, range.startOffset);
        const measureEnd = document.createRange();
        measureEnd.selectNodeContents(startBlock);
        measureEnd.setEnd(range.endContainer, range.endOffset);
        const startOffset = measureStart.toString().length;
        const endOffset = measureEnd.toString().length;
        if (startOffset === endOffset) {
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
          startOffset: Math.min(startOffset, endOffset),
          endOffset: Math.max(startOffset, endOffset),
          selectedText: range.toString(),
          top: rect.top,
          left: rect.left,
          width: rect.right - rect.left,
          rects
        };
      }

      function pageBounds() {
        const viewportWidth = (stage ? stage.clientWidth : 0) || window.innerWidth || 1;
        const scrollWidth = root ? root.scrollWidth : viewportWidth;
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
        pageCount = Math.max(
          1,
          Math.floor((bounds.maxOffset + gap + 1) / Math.max(pageSpan, 1)) + 1,
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
        const distance = pageTurnAxis === 'horizontal' ? 18 : 24;
        const outShift = direction > 0 ? -distance : distance;
        const inShift = -outShift;
        const outTransform = pageTurnAxis === 'horizontal'
          ? 'translate3d(' + outShift + 'px,0,0)'
          : 'translate3d(0,' + outShift + 'px,0)';
        const inTransform = pageTurnAxis === 'horizontal'
          ? 'translate3d(' + inShift + 'px,0,0)'
          : 'translate3d(0,' + inShift + 'px,0)';
        const scaleOut = pageTurnAnimation === 'roll'
          ? (pageTurnAxis === 'horizontal' ? ' scale(0.986, 0.992)' : ' scale(0.992, 0.968)')
          : '';
        const scaleIn = pageTurnAnimation === 'roll'
          ? (pageTurnAxis === 'horizontal' ? ' scale(1.01, 1)' : ' scale(1, 1.02)')
          : '';

        stage.style.transformOrigin = pageTurnAxis === 'horizontal'
          ? (direction > 0 ? 'right center' : 'left center')
          : (direction > 0 ? 'center top' : 'center bottom');
        stage.style.transition = 'transform 160ms ease, opacity 160ms ease';
        stage.style.opacity = pageTurnAnimation === 'roll' ? '0.96' : '0.985';
        stage.style.transform = outTransform + scaleOut;

        window.setTimeout(function() {
          stage.style.transition = 'none';
          commit();
          stage.style.transform = inTransform + scaleIn;
          window.requestAnimationFrame(function() {
            stage.style.transition = 'transform 220ms ease, opacity 220ms ease';
            stage.style.opacity = '1';
            stage.style.transform = 'translate3d(0,0,0)';
            window.setTimeout(function() {
              pageAnimationBusy = false;
            }, 220);
          });
        }, 140);
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

      function placeToolbar(data) {
        if (!toolbar) return;
        const estimatedWidth = 154;
        const left = Math.max(12, Math.min(window.innerWidth - estimatedWidth - 12, data.left + (data.width / 2) - (estimatedWidth / 2)));
        const top = Math.max(12, data.top - 52);
        toolbar.style.left = left + 'px';
        toolbar.style.top = top + 'px';
        toolbar.style.display = 'flex';
      }

      function clearSelectionUi() {
        currentSelection = null;
        preservingSelectionUi = false;
        cancelNativeSelectionClear();
        if (toolbar) {
          toolbar.style.display = 'none';
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
        placeToolbar(data);
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
      }, { passive: true });
      document.addEventListener('touchmove', function(event) {
        if (!touchTracking) {
          return;
        }
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
      }, { passive: true });
      document.addEventListener('touchend', function(event) {
        const touch = event.changedTouches && event.changedTouches.length > 0
          ? event.changedTouches[0]
          : null;
        if (!currentSelection) {
          if (touchTracking && !touchMoved && touch) {
            lastTouchHandledAt = Date.now();
            handleDocumentTap(event.target, touch.clientX);
          }
          touchTracking = false;
          touchMoved = false;
          return;
        }
        scheduleNativeSelectionClear(260);
        touchTracking = false;
        touchMoved = false;
      }, { passive: true });
      document.addEventListener('scroll', clearSelectionUi, true);
      if (stage) {
        stage.addEventListener('scroll', clearSelectionUi, { passive: true });
      }
      window.addEventListener('resize', function() {
        clearSelectionUi();
        updatePagedMetrics();
      });
      document.addEventListener('contextmenu', function(event) {
        const data = selectionData();
        if (!data) {
          return;
        }
        event.preventDefault();
        currentSelection = data;
        renderSelectionOverlay(data);
        placeToolbar(data);
        scheduleNativeSelectionClear(120);
      });

      if (toolbar) {
        toolbar.addEventListener('click', function(event) {
          const target = event.target;
          const button = target && typeof target.closest === 'function'
            ? target.closest('button[data-action]')
            : null;
          if (!button || !currentSelection) {
            return;
          }
          const action = button.dataset.action;
          send({
            type: action,
            blockAnchor: currentSelection.blockAnchor,
            startOffset: currentSelection.startOffset,
            endOffset: currentSelection.endOffset,
            selectedText: currentSelection.selectedText
          });
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

      updatePagedMetrics();
    })();
  </script>
</body>
</html>
''';
  }

  String _buildBlockHtml(BookContentBlock block) {
    final blockText = block.renderedText;
    final blockAnnotations =
        widget.annotations
            .where(
              (annotation) =>
                  AnnotationAnchor.parse(annotation.anchor).blockAnchor ==
                  block.anchor,
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
      _ => _buildAnnotatedInlineHtml(block, blockAnnotations),
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
  ) {
    final blockText = block.renderedText;
    final explicit =
        annotations
            .map((annotation) {
              final resolved = ResolvedAnnotation.fromAnnotation(
                annotation,
                blockText,
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

class _SelectionIntent {
  const _SelectionIntent({
    required this.selection,
    required this.existingAnnotation,
  });

  final AnnotationSelection selection;
  final AnnotationView? existingAnnotation;
}
