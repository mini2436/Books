import 'dart:async';
import 'dart:convert';

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
    required this.anchorJumpVersion,
    required this.onHighlight,
    required this.onAnnotate,
    required this.onOpenAnnotations,
    required this.onToggleUi,
    this.focusedAnchor,
  });

  final BookContentChapter chapter;
  final List<AnnotationView> annotations;
  final ReaderPreferences preferences;
  final AppReaderPalette palette;
  final bool uiVisible;
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
  final Future<void> Function(List<AnnotationView> annotations) onOpenAnnotations;
  final VoidCallback onToggleUi;

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

  @override
  void initState() {
    super.initState();
    _lastHtml = _buildHtml();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.palette.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _useFlutterFallback = true;
            });
          },
          onPageFinished: (_) async {
            _pageReady = true;
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
        final tapped = widget.annotations
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
      final result = await _controller.runJavaScriptReturningResult(
        'document.getElementById("reader-root")?.innerText?.trim().length ?? 0;',
      );
      final renderedLength = int.tryParse(
        result.toString().replaceAll('"', ''),
      );
      if (renderedLength == null || renderedLength <= 0) {
        if (!mounted) {
          return;
        }
        setState(() {
          _useFlutterFallback = true;
        });
        return;
      }
      _blankPageGuard?.cancel();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _useFlutterFallback = true;
      });
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

  Future<void> _scrollToFocusedAnchor() async {
    if (!_pageReady) {
      return;
    }
    if (_lastAnchorJumpVersion == widget.anchorJumpVersion) {
      return;
    }
    _lastAnchorJumpVersion = widget.anchorJumpVersion;
    final anchor = AnnotationAnchor.parse(widget.focusedAnchor ?? '').blockAnchor;
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
        .where((annotation) => annotation.anchor.blockAnchor == selection.blockAnchor)
        .toList();

    final containing = blockAnnotations
        .where(
          (annotation) => annotation.anchor.containsRange(
            start: selection.startOffset,
            end: selection.endOffset,
            text: selection.blockText,
          ),
        )
        .toList()
      ..sort((left, right) => left.range.length.compareTo(right.range.length));
    if (containing.isNotEmpty) {
      return _SelectionIntent(
        selection: selection,
        existingAnnotation: containing.first.annotation,
      );
    }

    final overlapping = blockAnnotations
        .where(
          (annotation) => annotation.anchor.overlapsOrTouches(
            start: selection.startOffset,
            end: selection.endOffset,
            text: selection.blockText,
          ),
        )
        .toList()
      ..sort((left, right) => left.range.start.compareTo(right.range.start));
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
      margin: 0;
      padding: 0;
      background: var(--reader-bg);
      color: var(--reader-ink);
      overscroll-behavior: none;
      -webkit-tap-highlight-color: transparent;
      font-family: ${_fontStackCss()};
    }
    body {
      padding: 0 0 28px;
      user-select: text;
      -webkit-user-select: text;
    }
    ::selection {
      background: var(--reader-selection);
    }
    #reader-root {
      padding: 0;
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
      border-radius: 4px;
      box-decoration-break: clone;
      -webkit-box-decoration-break: clone;
      cursor: pointer;
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
<body${widget.uiVisible ? '' : ' class="reader-ui-hidden"'}> 
  <div id="reader-root">$htmlBlocks</div>
  <div id="reader-selection-overlay" class="reader-selection-overlay"></div>
  <div id="reader-toolbar" class="reader-toolbar">
    <button type="button" data-action="highlight">高亮</button>
    <button type="button" class="primary" data-action="annotate">批注</button>
  </div>
  <script>
    (function() {
      const bridge = window.ReaderBridge;
      const toolbar = document.getElementById('reader-toolbar');
      const overlay = document.getElementById('reader-selection-overlay');
      let currentSelection = null;
      let nativeSelectionClearTimer = null;
      let preservingSelectionUi = false;

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
        const startBlock = range.startContainer.parentElement?.closest('[data-block-anchor]');
        const endBlock = range.endContainer.parentElement?.closest('[data-block-anchor]');
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

      function renderSelectionOverlay(data) {
        if (!overlay) return;
        overlay.replaceChildren();
        for (const rect of data.rects || []) {
          const segment = document.createElement('div');
          segment.className = 'segment';
          segment.style.top = rect.top + 'px';
          segment.style.left = rect.left + 'px';
          segment.style.width = rect.width + 'px';
          segment.style.height = rect.height + 'px';
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

      document.addEventListener('selectionchange', handleSelectionChange);
      document.addEventListener('touchstart', function() {
        cancelNativeSelectionClear();
      }, { passive: true });
      document.addEventListener('touchend', function() {
        if (!currentSelection) {
          return;
        }
        scheduleNativeSelectionClear(260);
      }, { passive: true });
      document.addEventListener('scroll', clearSelectionUi, true);
      window.addEventListener('resize', clearSelectionUi);
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

      toolbar?.addEventListener('click', function(event) {
        const button = event.target.closest('button[data-action]');
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

      document.addEventListener('click', function(event) {
        const annotationTarget = event.target.closest('[data-annotation-ids]');
        if (annotationTarget) {
          event.preventDefault();
          event.stopPropagation();
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
        if (event.target.closest('#reader-toolbar')) {
          return;
        }
        send({ type: 'toggleUi' });
      });

      window.readerClearSelectionUi = function() {
        clearNativeSelectionOnly();
        clearSelectionUi();
      };

      window.readerSetChromeVisible = function(visible) {
        document.body.classList.toggle('reader-ui-hidden', !visible);
      };

      window.readerScrollToAnchor = function(anchor) {
        if (!anchor) return;
        const target = Array.from(document.querySelectorAll('[data-anchor], [data-block-anchor]'))
          .find(node => node.dataset.anchor === anchor || node.dataset.blockAnchor === anchor);
        if (!target) return;
        target.classList.remove('reader-anchor-pulse');
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        window.setTimeout(() => target.classList.add('reader-anchor-pulse'), 40);
      };
    })();
  </script>
</body>
</html>
''';
  }

  String _buildBlockHtml(BookContentBlock block) {
    final blockText = block.renderedText;
    final blockAnnotations = widget.annotations
        .where(
          (annotation) => AnnotationAnchor.parse(annotation.anchor).blockAnchor == block.anchor,
        )
        .toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    final legacyHighlight = blockAnnotations.firstWhere(
      (annotation) => !AnnotationAnchor.parse(annotation.anchor).hasExplicitRange,
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
    final explicit = annotations
        .map((annotation) {
          final resolved = ResolvedAnnotation.fromAnnotation(annotation, blockText);
          if (resolved == null || !resolved.anchor.hasExplicitRange) {
            return null;
          }
          return resolved;
        })
        .whereType<ResolvedAnnotation>()
        .toList()
      ..sort((left, right) => left.range.start.compareTo(right.range.start));

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
        'style="background:${_cssColor(background)};'
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
