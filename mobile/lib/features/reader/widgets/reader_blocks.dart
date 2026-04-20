import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/models/book_models.dart';
import '../../../data/models/sync_models.dart';
import '../../../features/settings/reader_preferences_controller.dart';
import '../../../shared/theme/reader_theme_extension.dart';
import '../models/annotation_anchor.dart';

class ReaderBlocksView extends StatelessWidget {
  const ReaderBlocksView({
    super.key,
    required this.blocks,
    required this.annotations,
    required this.preferences,
    required this.keyForAnchor,
    required this.onHighlight,
    required this.onAnnotate,
    required this.onOpenAnnotations,
  });

  final List<BookContentBlock> blocks;
  final List<AnnotationView> annotations;
  final ReaderPreferences preferences;
  final GlobalKey Function(String anchor) keyForAnchor;
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

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks.map((block) {
        final blockAnnotations = _annotationsForBlock(block);
        final highlightColor = _blockHighlightColor(blockAnnotations, palette);
        Widget blockView;
        switch (block.type) {
          case 'heading':
            blockView = Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: _BlockHighlightFrame(
                highlightColor: highlightColor,
                  child: Text(
                  block.renderedText,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ),
            );
            break;
          case 'divider':
            blockView = Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '···',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  letterSpacing: 6,
                  color: palette.inkTertiary,
                ),
              ),
            );
            break;
          case 'quote':
            blockView = Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: palette.accent, width: 3),
                  ),
                  color: highlightColor ?? palette.backgroundSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: _SelectableBlockText(
                    text: block.renderedText,
                    anchor: block.anchor,
                    annotations: blockAnnotations,
                    preferences: preferences,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: palette.inkSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                    onHighlight: onHighlight,
                    onAnnotate: onAnnotate,
                  ),
                ),
              ),
            );
            break;
          case 'paragraph':
          default:
            blockView = Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _BlockHighlightFrame(
                highlightColor: highlightColor,
                child: _SelectableBlockText(
                  text: block.renderedText,
                  anchor: block.anchor,
                  annotations: blockAnnotations,
                  preferences: preferences,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: palette.ink,
                    height: preferences.lineHeight / 1.4,
                  ),
                  onHighlight: onHighlight,
                  onAnnotate: onAnnotate,
                ),
              ),
            );
            break;
        }
        if (blockAnnotations.isNotEmpty) {
          blockView = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpenAnnotations(blockAnnotations),
            child: blockView,
          );
        }
        return KeyedSubtree(key: keyForAnchor(block.anchor), child: blockView);
      }).toList(),
    );
  }

  List<AnnotationView> _annotationsForBlock(BookContentBlock block) {
    final blockText = block.renderedText;
    return annotations.where((annotation) {
      final parsedAnchor = AnnotationAnchor.parse(annotation.anchor);
      return parsedAnchor.blockAnchor == block.anchor;
    }).toList()
      ..sort((left, right) {
        final leftAnchor = AnnotationAnchor.parse(left.anchor);
        final rightAnchor = AnnotationAnchor.parse(right.anchor);
        final leftRange = leftAnchor.normalizedRangeIn(blockText);
        final rightRange = rightAnchor.normalizedRangeIn(blockText);
        return leftRange.start.compareTo(rightRange.start);
      });
  }

  Color? _blockHighlightColor(
    List<AnnotationView> blockAnnotations,
    AppReaderPalette palette,
  ) {
    if (blockAnnotations.isEmpty) {
      return null;
    }
    final annotation = blockAnnotations.firstWhere(
      (item) => !AnnotationAnchor.parse(item.anchor).hasExplicitRange,
      orElse: () => blockAnnotations.first,
    );
    if (AnnotationAnchor.parse(annotation.anchor).hasExplicitRange) {
      return null;
    }
    if (annotation.color == null || annotation.color!.isEmpty) {
      return palette.highlight;
    }
    return Color(
      int.parse('0xFF${annotation.color!.substring(1)}'),
    ).withValues(alpha: 0.12);
  }
}

class _BlockHighlightFrame extends StatelessWidget {
  const _BlockHighlightFrame({
    required this.child,
    this.highlightColor,
  });

  final Widget child;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    if (highlightColor == null) {
      return child;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlightColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: child,
      ),
    );
  }
}

class _SelectableBlockText extends StatelessWidget {
  const _SelectableBlockText({
    required this.text,
    required this.anchor,
    required this.annotations,
    required this.preferences,
    required this.style,
    required this.onHighlight,
    required this.onAnnotate,
  });

  final String text;
  final String anchor;
  final List<AnnotationView> annotations;
  final ReaderPreferences preferences;
  final TextStyle? style;
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

  @override
  Widget build(BuildContext context) {
    final resolvedAnnotations = annotations
        .map((annotation) => ResolvedAnnotation.fromAnnotation(annotation, text))
        .whereType<ResolvedAnnotation>()
        .toList();
    final baseStyle = (style ?? const TextStyle()).copyWith(
      fontSize: 17 * preferences.fontScale,
      fontFamily: preferences.fontFamily.fontFamily,
      height: preferences.lineHeight / 1.6,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _AnnotationPainter(
                text: text,
                style: baseStyle,
                textDirection: Directionality.of(context),
                annotations: resolvedAnnotations,
                drawBackgrounds: true,
                drawUnderlines: false,
              ),
            ),
          ),
        ),
        SelectableText(
          text,
          textAlign: TextAlign.justify,
          style: baseStyle,
          contextMenuBuilder: (context, editableTextState) {
            final selection = editableTextState.textEditingValue.selection;
            final selectedText = selection.textInside(
              editableTextState.textEditingValue.text,
            );
            final normalizedSelection = _normalizeSelection(selection);
            final copyItems = editableTextState.contextMenuButtonItems
                .where((item) => item.type == ContextMenuButtonType.copy)
                .toList();

            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: [
                ...copyItems,
                ContextMenuButtonItem(
                  label: '高亮',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    if (selectedText.trim().isEmpty ||
                        normalizedSelection == null) {
                      return;
                    }
                    final intent = _resolveSelectionIntent(
                      normalizedSelection,
                      resolvedAnnotations,
                    );
                    onHighlight(
                      intent.selection,
                      intent.existingAnnotation,
                    );
                  },
                ),
                ContextMenuButtonItem(
                  label: '批注',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    if (selectedText.trim().isEmpty ||
                        normalizedSelection == null) {
                      return;
                    }
                    final intent = _resolveSelectionIntent(
                      normalizedSelection,
                      resolvedAnnotations,
                    );
                    onAnnotate(
                      intent.selection,
                      intent.existingAnnotation,
                    );
                  },
                ),
              ],
            );
          },
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _AnnotationPainter(
                text: text,
                style: baseStyle,
                textDirection: Directionality.of(context),
                annotations: resolvedAnnotations,
                drawBackgrounds: false,
                drawUnderlines: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  AnnotationSelection? _normalizeSelection(TextSelection selection) {
    final start = selection.start;
    final end = selection.end;
    if (start < 0 || end < 0 || start == end) {
      return null;
    }
    final normalizedStart = start < end ? start : end;
    final normalizedEnd = start < end ? end : start;
    if (normalizedStart >= text.length || normalizedEnd > text.length) {
      return null;
    }
    return AnnotationSelection(
      blockAnchor: anchor,
      blockText: text,
      startOffset: normalizedStart,
      endOffset: normalizedEnd,
    );
  }

  _SelectionIntent _resolveSelectionIntent(
    AnnotationSelection selection,
    List<ResolvedAnnotation> resolvedAnnotations,
  ) {
    final containing = resolvedAnnotations
        .where(
          (annotation) => annotation.anchor.containsRange(
            start: selection.startOffset,
            end: selection.endOffset,
            text: text,
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

    final overlapping = resolvedAnnotations
        .where(
          (annotation) => annotation.anchor.overlapsOrTouches(
            start: selection.startOffset,
            end: selection.endOffset,
            text: text,
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
}

class _SelectionIntent {
  const _SelectionIntent({
    required this.selection,
    required this.existingAnnotation,
  });

  final AnnotationSelection selection;
  final AnnotationView? existingAnnotation;
}

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.annotations,
    required this.drawBackgrounds,
    required this.drawUnderlines,
  });

  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final List<ResolvedAnnotation> annotations;
  final bool drawBackgrounds;
  final bool drawUnderlines;

  @override
  void paint(Canvas canvas, Size size) {
    if (annotations.isEmpty) {
      return;
    }

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textAlign: TextAlign.justify,
    )..layout(maxWidth: size.width);

    for (final annotation in annotations) {
      final boxes = textPainter.getBoxesForSelection(
        TextSelection(
          baseOffset: annotation.range.start,
          extentOffset: annotation.range.end,
        ),
        boxHeightStyle: ui.BoxHeightStyle.tight,
        boxWidthStyle: ui.BoxWidthStyle.tight,
      );
      if (boxes.isEmpty) {
        continue;
      }
      final mergedBoxes = _mergeBoxes(boxes);
      final backgroundLineRects = _resolveBackgroundLineRects(
        lineRects: mergedBoxes,
        canvasHeight: size.height,
      );
      final lineColor = annotation.annotation.color == null ||
              annotation.annotation.color!.isEmpty
          ? const Color(0xFFC3924A)
          : Color(int.parse('0xFF${annotation.annotation.color!.substring(1)}'));
      final highlightColor = annotation.annotation.color == null ||
              annotation.annotation.color!.isEmpty
          ? const Color(0x33C3924A)
          : lineColor.withValues(alpha: 0.22);

      if (drawBackgrounds) {
        final paint = Paint()..color = highlightColor;
        _paintSelectionStyleHighlights(
          canvas,
          size,
          backgroundLineRects.isEmpty ? mergedBoxes : backgroundLineRects,
          paint,
        );
      }

      if (drawUnderlines &&
          annotation.anchor.underlineStyle != AnnotationUnderlineStyle.none) {
        for (final rect in mergedBoxes) {
          final baselineY = math.min(size.height, rect.bottom + 1.8);
          switch (annotation.anchor.underlineStyle) {
            case AnnotationUnderlineStyle.none:
              break;
            case AnnotationUnderlineStyle.solid:
              final paint = Paint()
                ..color = lineColor
                ..strokeWidth = 1.8
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round;
              canvas.drawLine(
                Offset(rect.left, baselineY),
                Offset(rect.right, baselineY),
                paint,
              );
              break;
            case AnnotationUnderlineStyle.dotted:
              final paint = Paint()
                ..color = lineColor
                ..style = PaintingStyle.fill;
              const gap = 5.0;
              const radius = 1.3;
              for (double x = rect.left; x <= rect.right; x += gap) {
                canvas.drawCircle(Offset(x, baselineY), radius, paint);
              }
              break;
            case AnnotationUnderlineStyle.wavy:
              final paint = Paint()
                ..color = lineColor
                ..strokeWidth = 1.6
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round;
              final path = Path()..moveTo(rect.left, baselineY);
              const waveLength = 8.0;
              const amplitude = 2.0;
              double x = rect.left;
              while (x < rect.right) {
                final nextX = math.min(x + waveLength / 2, rect.right);
                final controlX = x + waveLength / 4;
                path.quadraticBezierTo(
                  controlX,
                  baselineY - amplitude,
                  nextX,
                  baselineY,
                );
                if (nextX >= rect.right) {
                  break;
                }
                final endX = math.min(nextX + waveLength / 2, rect.right);
                final nextControlX = nextX + waveLength / 4;
                path.quadraticBezierTo(
                  nextControlX,
                  baselineY + amplitude,
                  endX,
                  baselineY,
                );
                x = endX;
              }
              canvas.drawPath(path, paint);
              break;
          }
        }
      }
    }
  }

  List<Rect> _mergeBoxes(List<TextBox> boxes) {
    final rects = boxes
        .map((box) => box.toRect())
        .where((rect) => rect.width > 0 && rect.height > 0)
        .toList()
      ..sort((left, right) {
        final topCompare = left.top.compareTo(right.top);
        if (topCompare != 0) {
          return topCompare;
        }
        return left.left.compareTo(right.left);
      });
    if (rects.isEmpty) {
      return const [];
    }

    final merged = <Rect>[];
    final groupedByLine = <List<Rect>>[];
    for (final rect in rects) {
      final existingLine = groupedByLine.cast<List<Rect>?>().firstWhere(
        (line) {
          if (line == null || line.isEmpty) {
            return false;
          }
          final probe = line.first;
          return (rect.top - probe.top).abs() < 1.5 &&
              (rect.bottom - probe.bottom).abs() < 1.5;
        },
        orElse: () => null,
      );
      if (existingLine != null) {
        existingLine.add(rect);
      } else {
        groupedByLine.add([rect]);
      }
    }

    for (final lineRects in groupedByLine) {
      lineRects.sort((left, right) => left.left.compareTo(right.left));
      var lineLeft = lineRects.first.left;
      var lineTop = lineRects.first.top;
      var lineRight = lineRects.first.right;
      var lineBottom = lineRects.first.bottom;
      for (final rect in lineRects.skip(1)) {
        lineLeft = math.min(lineLeft, rect.left);
        lineTop = math.min(lineTop, rect.top);
        lineRight = math.max(lineRight, rect.right);
        lineBottom = math.max(lineBottom, rect.bottom);
      }
      merged.add(
        Rect.fromLTRB(lineLeft, lineTop, lineRight, lineBottom),
      );
    }
    return merged;
  }

  List<Rect> _resolveBackgroundLineRects({
    required List<Rect> lineRects,
    required double canvasHeight,
  }) {
    if (lineRects.isEmpty) {
      return const [];
    }
    return List<Rect>.generate(lineRects.length, (index) {
      final rect = lineRects[index];
      final previous = index == 0 ? null : lineRects[index - 1];
      final next = index == lineRects.length - 1 ? null : lineRects[index + 1];
      final previousGap = previous == null
          ? 0.0
          : math.max(0.0, rect.top - previous.bottom);
      final nextGap =
          next == null ? 0.0 : math.max(0.0, next.top - rect.bottom);
      final topPadding = previous == null
          ? 0.7
          : math.min(1.6, math.max(0.35, previousGap * 0.38));
      final bottomPadding = next == null
          ? 1.0
          : math.min(1.6, math.max(0.35, nextGap * 0.38));
      return Rect.fromLTRB(
        rect.left,
        math.max(0, rect.top - topPadding),
        rect.right,
        math.min(canvasHeight, rect.bottom + bottomPadding),
      );
    });
  }

  void _paintSelectionStyleHighlights(
    Canvas canvas,
    Size size,
    List<Rect> lineRects,
    Paint paint,
  ) {
    if (lineRects.isEmpty) {
      return;
    }

    if (lineRects.length == 1) {
      final rect = lineRects.first;
      final expanded = Rect.fromLTRB(
        rect.left - 1.2,
        math.max(0, rect.top - 0.6),
        rect.right + 1.2,
        math.min(size.height, rect.bottom + 0.6),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(expanded, const Radius.circular(2)),
        paint,
      );
      return;
    }

    for (var index = 0; index < lineRects.length; index++) {
      final rect = lineRects[index];
      final expanded = Rect.fromLTRB(
        rect.left - 1.2,
        math.max(0, rect.top - (index == 0 ? 0.2 : 0)),
        rect.right + 1.2,
        math.min(
          size.height,
          rect.bottom + (index == lineRects.length - 1 ? 0.2 : 0),
        ),
      );
      final isFirst = index == 0;
      final isLast = index == lineRects.length - 1;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          expanded,
          topLeft: isFirst ? const Radius.circular(2) : Radius.zero,
          topRight: isFirst ? const Radius.circular(2) : Radius.zero,
          bottomLeft: isLast ? const Radius.circular(2) : Radius.zero,
          bottomRight: isLast ? const Radius.circular(2) : Radius.zero,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return text != oldDelegate.text ||
        style != oldDelegate.style ||
        textDirection != oldDelegate.textDirection ||
        drawBackgrounds != oldDelegate.drawBackgrounds ||
        drawUnderlines != oldDelegate.drawUnderlines ||
        annotations.length != oldDelegate.annotations.length ||
        !_sameAnnotations(annotations, oldDelegate.annotations);
  }

  bool _sameAnnotations(
    List<ResolvedAnnotation> left,
    List<ResolvedAnnotation> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      final current = left[index];
      final previous = right[index];
      if (current.annotation.id != previous.annotation.id ||
          current.annotation.updatedAt != previous.annotation.updatedAt ||
          current.range.start != previous.range.start ||
          current.range.end != previous.range.end ||
          current.anchor.underlineStyle != previous.anchor.underlineStyle) {
        return false;
      }
    }
    return true;
  }
}
