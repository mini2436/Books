import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:private_reader_mobile/shared/localization/localized_text.dart';
import 'package:flutter/services.dart';

import '../../../data/models/book_models.dart';
import '../../../data/models/sync_models.dart';
import '../../../features/settings/reader_preferences_controller.dart';
import '../../../shared/theme/reader_theme_extension.dart';
import '../../../shared/theme/glass_theme.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../models/annotation_anchor.dart';

class ReaderBlocksView extends StatelessWidget {
  const ReaderBlocksView({
    super.key,
    required this.blocks,
    required this.imageResources,
    required this.failedImageResourceIds,
    required this.constrainImagesToViewport,
    required this.annotations,
    required this.preferences,
    required this.keyForAnchor,
    required this.onHighlight,
    required this.onAnnotate,
    required this.onOpenAnnotations,
    this.onRetryImages,
    this.twoColumnContent = false,
    this.pagedViewportWidth,
    this.pagedColumnHeight,
    this.pagedColumnCount = 1,
  }) : assert(
         (pagedViewportWidth == null) == (pagedColumnHeight == null),
         'Paged viewport width and column height must be provided together.',
       );

  final List<BookContentBlock> blocks;
  final Map<String, Uint8List> imageResources;
  final Set<String> failedImageResourceIds;
  final bool constrainImagesToViewport;
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
  final Future<void> Function()? onRetryImages;
  final bool twoColumnContent;
  final double? pagedViewportWidth;
  final double? pagedColumnHeight;
  final int pagedColumnCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final orderedBlockAnchors = blocks
        .map((block) => block.anchor)
        .toList(growable: false);
    final blockViews = blocks
        .map((block) {
          final blockAnnotations = _annotationsForBlock(
            block,
            orderedBlockAnchors,
          );
          final highlightColor = _blockHighlightColor(
            blockAnnotations,
            palette,
          );
          Widget blockView;
          switch (block.type) {
            case 'image':
              blockView = Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _ImageBlockView(
                  block: block,
                  imageBytes: block.resourceId == null
                      ? null
                      : imageResources[block.resourceId],
                  failed:
                      block.resourceId == null ||
                      failedImageResourceIds.contains(block.resourceId),
                  constrainToViewport: constrainImagesToViewport,
                  maxImageHeight:
                      pagedColumnHeight != null && pagedColumnCount == 2
                      ? math.max(220, pagedColumnHeight! * 0.78)
                      : null,
                  onRetry: failedImageResourceIds.contains(block.resourceId)
                      ? onRetryImages
                      : null,
                ),
              );
              break;
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
                      fontFamily: preferences.fontFamily.fontFamily,
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
                      orderedBlockAnchors: orderedBlockAnchors,
                      preferences: preferences,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: palette.inkSecondary,
                        fontStyle: FontStyle.italic,
                        height: preferences.lineHeight / 1.6,
                      ),
                      onHighlight: onHighlight,
                      onAnnotate: onAnnotate,
                      onOpenAnnotations: onOpenAnnotations,
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
                    orderedBlockAnchors: orderedBlockAnchors,
                    preferences: preferences,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: palette.ink,
                      height: preferences.lineHeight / 1.4,
                    ),
                    onHighlight: onHighlight,
                    onAnnotate: onAnnotate,
                    onOpenAnnotations: onOpenAnnotations,
                  ),
                ),
              );
              break;
          }
          final legacyBlockAnnotations = blockAnnotations
              .where(
                (annotation) =>
                    !AnnotationAnchor.parse(annotation.anchor).hasExplicitRange,
              )
              .toList(growable: false);
          if (legacyBlockAnnotations.isNotEmpty) {
            blockView = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpenAnnotations(legacyBlockAnnotations),
              child: blockView,
            );
          }
          return KeyedSubtree(
            key: keyForAnchor(block.anchor),
            child: blockView,
          );
        })
        .toList(growable: false);

    final flowItems = <_ReaderFlowItem>[];
    var pendingGroup = <Widget>[];

    void flushPendingGroup() {
      if (pendingGroup.isEmpty) return;
      flowItems.add(
        _ReaderFlowItem(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: pendingGroup,
          ),
        ),
      );
      pendingGroup = <Widget>[];
    }

    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
      if (block.type == 'heading' || block.type == 'divider') {
        flushPendingGroup();
        flowItems.add(
          _ReaderFlowItem(child: blockViews[index], spansColumns: true),
        );
        continue;
      }
      pendingGroup.add(blockViews[index]);
      if (block.isImage) {
        flushPendingGroup();
      }
    }
    flushPendingGroup();

    final pageWidth = pagedViewportWidth;
    final columnHeight = pagedColumnHeight;
    if (pageWidth != null && columnHeight != null) {
      return _buildPagedFlow(
        context,
        blockViews: blockViews,
        orderedBlockAnchors: orderedBlockAnchors,
        pageWidth: pageWidth,
        columnHeight: columnHeight,
        columnCount: pagedColumnCount.clamp(1, 2),
      );
    }

    if (!twoColumnContent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blockViews,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const columnGap = 28.0;
        final columnWidth = math.max(
          0.0,
          (constraints.maxWidth - columnGap) / 2,
        );
        final rows = <Widget>[];
        _ReaderFlowItem? pendingColumn;

        void flushPendingColumn() {
          final item = pendingColumn;
          if (item == null) return;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [SizedBox(width: columnWidth, child: item.child)],
            ),
          );
          pendingColumn = null;
        }

        for (final item in flowItems) {
          if (item.spansColumns) {
            flushPendingColumn();
            rows.add(item.child);
            continue;
          }
          if (pendingColumn == null) {
            pendingColumn = item;
            continue;
          }
          final left = pendingColumn!;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: columnWidth, child: left.child),
                const SizedBox(width: columnGap),
                SizedBox(width: columnWidth, child: item.child),
              ],
            ),
          );
          pendingColumn = null;
        }
        flushPendingColumn();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _buildPagedFlow(
    BuildContext context, {
    required List<Widget> blockViews,
    required List<String> orderedBlockAnchors,
    required double pageWidth,
    required double columnHeight,
    required int columnCount,
  }) {
    const columnGap = 28.0;
    final columnWidth = math.max(
      0.0,
      (pageWidth - columnGap * (columnCount - 1)) / columnCount,
    );
    final palette = AppReaderPalette.of(context);
    final columns = <List<Widget>>[<Widget>[]];
    var currentColumn = columns.last;
    var usedHeight = 0.0;

    void startNextColumn() {
      if (currentColumn.isEmpty) return;
      currentColumn = <Widget>[];
      columns.add(currentColumn);
      usedHeight = 0;
    }

    void addFixedBlock(int index) {
      final estimatedHeight = _estimatePagedBlockHeight(
        context,
        blocks[index],
        columnWidth,
        columnHeight,
        columnCount,
      );
      if (currentColumn.isNotEmpty &&
          usedHeight + estimatedHeight > columnHeight) {
        startNextColumn();
      }
      currentColumn.add(SizedBox(width: columnWidth, child: blockViews[index]));
      usedHeight = math.min(columnHeight, usedHeight + estimatedHeight);
    }

    for (var index = 0; index < blocks.length; index += 1) {
      final block = blocks[index];
      final sourceText = block.renderedText;
      if (block.type != 'paragraph' || sourceText.isEmpty) {
        addFixedBlock(index);
        continue;
      }

      final blockAnnotations = _annotationsForBlock(block, orderedBlockAnchors);
      final highlightColor = _blockHighlightColor(blockAnnotations, palette);
      final paragraphStyle = _resolvedPagedParagraphStyle(context, palette);
      final textWidth = math.max(
        1.0,
        columnWidth - (highlightColor == null ? 0 : 20),
      );
      final frameHeight = highlightColor == null ? 0.0 : 12.0;
      var sourceOffset = 0;
      var firstFragment = true;

      while (sourceOffset < sourceText.length) {
        var remainingHeight = math.max(0.0, columnHeight - usedHeight);
        final remainingText = sourceText.substring(sourceOffset);
        final remainingTextHeight = _measurePagedTextHeight(
          context,
          remainingText,
          paragraphStyle,
          textWidth,
        );
        const finalBlockSpacing = 16.0;
        final completeHeight =
            remainingTextHeight + frameHeight + finalBlockSpacing;

        if (completeHeight <= remainingHeight + 0.5) {
          currentColumn.add(
            _buildPagedParagraphFragment(
              context,
              block: block,
              visibleText: remainingText,
              sourceText: sourceText,
              sourceOffset: sourceOffset,
              annotations: blockAnnotations,
              orderedBlockAnchors: orderedBlockAnchors,
              highlightColor: highlightColor,
              firstFragment: firstFragment,
              bottomSpacing: finalBlockSpacing,
            ),
          );
          usedHeight += completeHeight;
          sourceOffset = sourceText.length;
          continue;
        }

        final minimumLineHeight =
            _measurePagedTextHeight(context, '阅', paragraphStyle, textWidth) +
            frameHeight;
        if (currentColumn.isNotEmpty &&
            remainingHeight < minimumLineHeight - 0.5) {
          startNextColumn();
          continue;
        }

        remainingHeight = math.max(1.0, columnHeight - usedHeight);
        final fittingTextHeight = math.max(1.0, remainingHeight - frameHeight);
        var localEnd = _fittingPagedTextEnd(
          context,
          remainingText,
          paragraphStyle,
          textWidth,
          fittingTextHeight,
        );
        if (localEnd <= 0) {
          if (currentColumn.isNotEmpty) {
            startNextColumn();
            continue;
          }
          localEnd = _nextCodePointOffset(remainingText, 0);
        }
        final visibleText = remainingText.substring(0, localEnd);
        final visibleTextHeight = _measurePagedTextHeight(
          context,
          visibleText,
          paragraphStyle,
          textWidth,
        );
        final isFinalFragment = sourceOffset + localEnd >= sourceText.length;
        final bottomSpacing =
            isFinalFragment &&
                visibleTextHeight + frameHeight + finalBlockSpacing <=
                    remainingHeight + 0.5
            ? finalBlockSpacing
            : 0.0;
        currentColumn.add(
          _buildPagedParagraphFragment(
            context,
            block: block,
            visibleText: visibleText,
            sourceText: sourceText,
            sourceOffset: sourceOffset,
            annotations: blockAnnotations,
            orderedBlockAnchors: orderedBlockAnchors,
            highlightColor: highlightColor,
            firstFragment: firstFragment,
            bottomSpacing: bottomSpacing,
          ),
        );
        usedHeight += visibleTextHeight + frameHeight + bottomSpacing;
        sourceOffset += localEnd;
        firstFragment = false;
        if (!isFinalFragment) startNextColumn();
      }
    }

    if (columns.length > 1 && columns.last.isEmpty) {
      columns.removeLast();
    }
    while (columns.length % columnCount != 0) {
      columns.add(<Widget>[]);
    }

    final children = <Widget>[];
    for (var index = 0; index < columns.length; index += 1) {
      if (index > 0) children.add(const SizedBox(width: columnGap));
      children.add(
        SizedBox(
          width: columnWidth,
          height: columnHeight,
          child: ClipRect(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: columns[index],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: columnHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildPagedParagraphFragment(
    BuildContext context, {
    required BookContentBlock block,
    required String visibleText,
    required String sourceText,
    required int sourceOffset,
    required List<AnnotationView> annotations,
    required List<String> orderedBlockAnchors,
    required Color? highlightColor,
    required bool firstFragment,
    required double bottomSpacing,
  }) {
    Widget fragment = Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: _BlockHighlightFrame(
        highlightColor: highlightColor,
        child: _SelectableBlockText(
          text: visibleText,
          sourceText: sourceText,
          sourceOffset: sourceOffset,
          anchor: block.anchor,
          annotations: annotations,
          orderedBlockAnchors: orderedBlockAnchors,
          preferences: preferences,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppReaderPalette.of(context).ink,
            height: preferences.lineHeight / 1.4,
          ),
          onHighlight: onHighlight,
          onAnnotate: onAnnotate,
          onOpenAnnotations: onOpenAnnotations,
        ),
      ),
    );
    final legacyAnnotations = annotations
        .where(
          (annotation) =>
              !AnnotationAnchor.parse(annotation.anchor).hasExplicitRange,
        )
        .toList(growable: false);
    if (legacyAnnotations.isNotEmpty) {
      fragment = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpenAnnotations(legacyAnnotations),
        child: fragment,
      );
    }
    return KeyedSubtree(
      key: firstFragment
          ? keyForAnchor(block.anchor)
          : ValueKey('${block.anchor}@$sourceOffset'),
      child: fragment,
    );
  }

  TextStyle _resolvedPagedParagraphStyle(
    BuildContext context,
    AppReaderPalette palette,
  ) => (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
    color: palette.ink,
    fontSize: 17 * preferences.fontScale,
    fontFamily: preferences.fontFamily.fontFamily,
    height: preferences.lineHeight / 1.4,
  );

  double _measurePagedTextHeight(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.justify,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: width);
    return painter.height;
  }

  int _fittingPagedTextEnd(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
    double maximumHeight,
  ) {
    var low = 1;
    var high = text.length;
    var best = 0;
    while (low <= high) {
      var middle = (low + high) >> 1;
      if (middle < text.length && _isLowSurrogate(text.codeUnitAt(middle))) {
        middle -= 1;
      }
      if (middle <= 0) {
        low = 1;
        continue;
      }
      final height = _measurePagedTextHeight(
        context,
        text.substring(0, middle),
        style,
        width,
      );
      if (height <= maximumHeight + 0.5) {
        best = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return best;
  }

  int _nextCodePointOffset(String text, int offset) {
    if (offset >= text.length) return text.length;
    final first = text.codeUnitAt(offset);
    if (_isHighSurrogate(first) && offset + 1 < text.length) return offset + 2;
    return offset + 1;
  }

  bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  double _estimatePagedBlockHeight(
    BuildContext context,
    BookContentBlock block,
    double columnWidth,
    double columnHeight,
    int columnCount,
  ) {
    switch (block.type) {
      case 'heading':
        final style = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontFamily: preferences.fontFamily.fontFamily,
        );
        return _measurePagedTextHeight(
              context,
              block.renderedText,
              style ?? const TextStyle(),
              columnWidth,
            ) +
            22;
      case 'divider':
        return 64;
      case 'quote':
        final style =
            (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
                .copyWith(
                  fontSize: 17 * preferences.fontScale,
                  fontFamily: preferences.fontFamily.fontFamily,
                  height: preferences.lineHeight / 1.6,
                  fontStyle: FontStyle.italic,
                );
        return _measurePagedTextHeight(
              context,
              block.renderedText,
              style,
              math.max(1, columnWidth - 32),
            ) +
            46;
      case 'image':
        final hasLoadedImage =
            block.resourceId != null &&
            imageResources.containsKey(block.resourceId);
        final ratio =
            block.imageWidth != null &&
                block.imageHeight != null &&
                block.imageWidth! > 0 &&
                block.imageHeight! > 0
            ? (block.imageWidth! / block.imageHeight!).clamp(0.35, 3.2)
            : null;
        final maximumImageHeight = columnCount == 2
            ? math.max(220.0, columnHeight * 0.78)
            : math.max(220.0, columnHeight);
        final imageHeight = ratio == null
            ? (hasLoadedImage
                  ? maximumImageHeight
                  : math.min(180.0, maximumImageHeight))
            : math.min(columnWidth / ratio, maximumImageHeight);
        final captionHeight =
            (block.imageCaption ?? block.imageAlt ?? '').trim().isEmpty
            ? 0.0
            : 34.0;
        return imageHeight + captionHeight + 18;
      default:
        return columnHeight;
    }
  }

  List<AnnotationView> _annotationsForBlock(
    BookContentBlock block,
    List<String> orderedBlockAnchors,
  ) {
    final blockText = block.renderedText;
    return annotations.where((annotation) {
      final parsedAnchor = AnnotationAnchor.parse(annotation.anchor);
      return parsedAnchor.affectsBlock(
        currentBlockAnchor: block.anchor,
        orderedBlockAnchors: orderedBlockAnchors,
      );
    }).toList()..sort((left, right) {
      final leftAnchor = AnnotationAnchor.parse(left.anchor);
      final rightAnchor = AnnotationAnchor.parse(right.anchor);
      final leftRange =
          leftAnchor.rangeForBlock(
            currentBlockAnchor: block.anchor,
            blockText: blockText,
            orderedBlockAnchors: orderedBlockAnchors,
          ) ??
          const AnnotationTextRange(start: 0, end: 0);
      final rightRange =
          rightAnchor.rangeForBlock(
            currentBlockAnchor: block.anchor,
            blockText: blockText,
            orderedBlockAnchors: orderedBlockAnchors,
          ) ??
          const AnnotationTextRange(start: 0, end: 0);
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

class _ReaderFlowItem {
  const _ReaderFlowItem({required this.child, this.spansColumns = false});

  final Widget child;
  final bool spansColumns;
}

class _BlockHighlightFrame extends StatelessWidget {
  const _BlockHighlightFrame({required this.child, this.highlightColor});

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

class _ImageBlockView extends StatelessWidget {
  const _ImageBlockView({
    required this.block,
    required this.imageBytes,
    required this.failed,
    required this.constrainToViewport,
    this.maxImageHeight,
    this.onRetry,
  });

  final BookContentBlock block;
  final Uint8List? imageBytes;
  final bool failed;
  final bool constrainToViewport;
  final double? maxImageHeight;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final caption = (block.imageCaption ?? block.imageAlt ?? '').trim();
    final aspectRatio = _aspectRatio(block);
    final heroTag = MediaQuery.of(context).disableAnimations
        ? null
        : 'reader-image-${block.anchor}-${block.resourceId ?? 'inline'}';
    Widget image = imageBytes == null
        ? _ImagePlaceholder(
            failed: failed,
            palette: palette,
            aspectRatio: aspectRatio,
            onRetry: onRetry,
          )
        : GestureDetector(
            onTap: () => _openPreview(context, imageBytes!, caption, heroTag),
            child: _ReaderImageHero(
              heroTag: heroTag,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  imageBytes!,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _ImagePlaceholder(
                    failed: true,
                    palette: palette,
                    aspectRatio: aspectRatio,
                    onRetry: onRetry,
                  ),
                ),
              ),
            ),
          );

    if (constrainToViewport && imageBytes != null) {
      final effectiveMaxImageHeight =
          maxImageHeight ??
          (MediaQuery.sizeOf(context).height - 164).clamp(
            220.0,
            double.infinity,
          );
      final sourceImage = image;
      image = LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final intrinsicHeight =
              aspectRatio != null &&
                  availableWidth.isFinite &&
                  availableWidth > 0
              ? availableWidth / aspectRatio
              : effectiveMaxImageHeight;
          final resolvedHeight = math.min(
            effectiveMaxImageHeight,
            intrinsicHeight,
          );
          return SizedBox(
            width: double.infinity,
            height: resolvedHeight,
            child: sourceImage,
          );
        },
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (aspectRatio == null)
          image
        else if (constrainToViewport && imageBytes != null)
          image
        else
          AspectRatio(aspectRatio: aspectRatio, child: image),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.inkSecondary,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  double? _aspectRatio(BookContentBlock block) {
    final width = block.imageWidth;
    final height = block.imageHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (width / height).clamp(0.35, 3.2);
  }

  void _openPreview(
    BuildContext context,
    Uint8List bytes,
    String caption,
    Object? heroTag,
  ) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierLabel: '关闭图片预览',
        barrierColor: Colors.black.withValues(alpha: 0.72),
        transitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        reverseTransitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 240),
        pageBuilder: (previewContext, _, _) {
          final palette = AppReaderPalette.of(previewContext);
          return Material(
            color: Colors.black.withValues(alpha: 0.92),
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 0.6,
                      maxScale: 4,
                      child: Center(
                        child: _ReaderImageHero(
                          heroTag: heroTag,
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filledTonal(
                      onPressed: () => Navigator.of(previewContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  if (caption.isNotEmpty)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(
                            caption,
                            textAlign: TextAlign.center,
                            style: Theme.of(previewContext).textTheme.bodyMedium
                                ?.copyWith(color: palette.background),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ReaderImageHero extends StatelessWidget {
  const _ReaderImageHero({required this.heroTag, required this.child});

  final Object? heroTag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (heroTag == null) return child;
    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: true,
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({
    required this.failed,
    required this.palette,
    required this.aspectRatio,
    this.onRetry,
  });

  final bool failed;
  final AppReaderPalette palette;
  final double? aspectRatio;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final height = aspectRatio == null ? 180.0 : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.line),
      ),
      child: SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                failed ? '图片无法加载' : '图片加载中',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.inkTertiary),
              ),
              if (failed && onRetry != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectableBlockText extends StatelessWidget {
  const _SelectableBlockText({
    required this.text,
    this.sourceText,
    this.sourceOffset = 0,
    required this.anchor,
    required this.annotations,
    required this.orderedBlockAnchors,
    required this.preferences,
    required this.style,
    required this.onHighlight,
    required this.onAnnotate,
    required this.onOpenAnnotations,
  });

  final String text;
  final String? sourceText;
  final int sourceOffset;
  final String anchor;
  final List<AnnotationView> annotations;
  final List<String> orderedBlockAnchors;
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
  final Future<void> Function(List<AnnotationView> annotations)
  onOpenAnnotations;

  @override
  Widget build(BuildContext context) {
    final completeText = sourceText ?? text;
    final completeResolvedAnnotations = annotations
        .map(
          (annotation) => ResolvedAnnotation.fromAnnotation(
            annotation,
            completeText,
            currentBlockAnchor: anchor,
            orderedBlockAnchors: orderedBlockAnchors,
          ),
        )
        .whereType<ResolvedAnnotation>()
        .toList();
    final fragmentEnd = sourceOffset + text.length;
    final resolvedAnnotations = completeResolvedAnnotations
        .where(
          (annotation) =>
              annotation.range.end > sourceOffset &&
              annotation.range.start < fragmentEnd,
        )
        .map(
          (annotation) => ResolvedAnnotation(
            annotation: annotation.annotation,
            anchor: annotation.anchor,
            range: AnnotationTextRange(
              start:
                  math.max(annotation.range.start, sourceOffset) - sourceOffset,
              end: math.min(annotation.range.end, fragmentEnd) - sourceOffset,
            ),
          ),
        )
        .toList(growable: false);
    final baseStyle = (style ?? const TextStyle()).copyWith(
      fontSize: 17 * preferences.fontScale,
      fontFamily: preferences.fontFamily.fontFamily,
    );
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final defaultTextStyle = DefaultTextStyle.of(context);
    final textHeightBehavior = defaultTextStyle.textHeightBehavior;
    final textWidthBasis = defaultTextStyle.textWidthBasis;
    const strutStyle = StrutStyle();

    return _AnnotationTapRegion(
      text: text,
      style: baseStyle,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      strutStyle: strutStyle,
      textHeightBehavior: textHeightBehavior,
      textWidthBasis: textWidthBasis,
      annotations: resolvedAnnotations,
      onOpenAnnotations: onOpenAnnotations,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AnnotationPainter(
                  text: text,
                  style: baseStyle,
                  textDirection: textDirection,
                  textScaler: textScaler,
                  locale: locale,
                  strutStyle: strutStyle,
                  textHeightBehavior: textHeightBehavior,
                  textWidthBasis: textWidthBasis,
                  annotations: resolvedAnnotations,
                  drawBackgrounds: true,
                  drawUnderlines: false,
                ),
              ),
            ),
          ),
          _SelectableTextWithActions(
            text,
            style: baseStyle,
            textDirection: textDirection,
            textScaler: textScaler,
            strutStyle: strutStyle,
            textHeightBehavior: textHeightBehavior,
            textWidthBasis: textWidthBasis,
            onHighlight: (selection) async {
              final normalizedSelection = _normalizeSelection(selection);
              if (normalizedSelection == null) {
                return;
              }
              final intent = _resolveSelectionIntent(
                normalizedSelection,
                completeResolvedAnnotations,
                completeText,
              );
              await onHighlight(intent.selection, intent.existingAnnotation);
            },
            onAnnotate: (selection) async {
              final normalizedSelection = _normalizeSelection(selection);
              if (normalizedSelection == null) {
                return;
              }
              final intent = _resolveSelectionIntent(
                normalizedSelection,
                completeResolvedAnnotations,
                completeText,
              );
              await onAnnotate(intent.selection, intent.existingAnnotation);
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AnnotationPainter(
                  text: text,
                  style: baseStyle,
                  textDirection: textDirection,
                  textScaler: textScaler,
                  locale: locale,
                  strutStyle: strutStyle,
                  textHeightBehavior: textHeightBehavior,
                  textWidthBasis: textWidthBasis,
                  annotations: resolvedAnnotations,
                  drawBackgrounds: false,
                  drawUnderlines: true,
                ),
              ),
            ),
          ),
        ],
      ),
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
    final completeText = sourceText ?? text;
    return AnnotationSelection(
      blockAnchor: anchor,
      blockText: completeText,
      startOffset: sourceOffset + normalizedStart,
      endOffset: sourceOffset + normalizedEnd,
    );
  }

  _SelectionIntent _resolveSelectionIntent(
    AnnotationSelection selection,
    List<ResolvedAnnotation> resolvedAnnotations,
    String completeText,
  ) {
    final containing =
        resolvedAnnotations
            .where(
              (annotation) =>
                  !annotation.anchor.spansMultipleBlocks &&
                  annotation.anchor.containsRange(
                    start: selection.startOffset,
                    end: selection.endOffset,
                    text: completeText,
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
        resolvedAnnotations
            .where(
              (annotation) =>
                  !annotation.anchor.spansMultipleBlocks &&
                  annotation.anchor.overlapsOrTouches(
                    start: selection.startOffset,
                    end: selection.endOffset,
                    text: completeText,
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
}

class _AnnotationTapRegion extends StatefulWidget {
  const _AnnotationTapRegion({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.strutStyle,
    required this.textHeightBehavior,
    required this.textWidthBasis,
    required this.annotations,
    required this.onOpenAnnotations,
    required this.child,
  });

  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final StrutStyle strutStyle;
  final TextHeightBehavior? textHeightBehavior;
  final TextWidthBasis textWidthBasis;
  final List<ResolvedAnnotation> annotations;
  final Future<void> Function(List<AnnotationView> annotations)
  onOpenAnnotations;
  final Widget child;

  @override
  State<_AnnotationTapRegion> createState() => _AnnotationTapRegionState();
}

class _AnnotationTapRegionState extends State<_AnnotationTapRegion> {
  final Map<int, Offset> _pointerStarts = <int, Offset>{};
  final Set<int> _movedPointers = <int>{};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _pointerStarts[event.pointer] = event.localPosition;
          _movedPointers.remove(event.pointer);
        },
        onPointerMove: (event) {
          final start = _pointerStarts[event.pointer];
          if (start == null) return;
          final tolerance = event.kind == ui.PointerDeviceKind.mouse
              ? 4.0
              : kTouchSlop;
          if ((event.localPosition - start).distance > tolerance) {
            _movedPointers.add(event.pointer);
          }
        },
        onPointerCancel: (event) {
          _pointerStarts.remove(event.pointer);
          _movedPointers.remove(event.pointer);
        },
        onPointerUp: (event) {
          final hadStart = _pointerStarts.remove(event.pointer) != null;
          final moved = _movedPointers.remove(event.pointer);
          if (!hadStart || moved) return;
          _openAnnotationsAt(
            context,
            event.localPosition,
            constraints.maxWidth,
          );
        },
        child: widget.child,
      ),
    );
  }

  void _openAnnotationsAt(
    BuildContext context,
    Offset localPosition,
    double maximumWidth,
  ) {
    if (widget.annotations.isEmpty || !maximumWidth.isFinite) return;
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textAlign: TextAlign.justify,
      textDirection: widget.textDirection,
      textScaler: widget.textScaler,
      locale: widget.locale,
      strutStyle: widget.strutStyle,
      textHeightBehavior: widget.textHeightBehavior,
      textWidthBasis: widget.textWidthBasis,
    )..layout(maxWidth: maximumWidth);
    final matches = <int, AnnotationView>{};
    for (final annotation in widget.annotations) {
      final boxes = textPainter.getBoxesForSelection(
        TextSelection(
          baseOffset: annotation.range.start,
          extentOffset: annotation.range.end,
        ),
      );
      if (boxes.any((box) => box.toRect().inflate(2).contains(localPosition))) {
        matches[annotation.annotation.id] = annotation.annotation;
      }
    }
    if (matches.isNotEmpty) {
      unawaited(
        widget.onOpenAnnotations(matches.values.toList(growable: false)),
      );
    }
  }
}

class _SelectableTextWithActions extends StatefulWidget {
  const _SelectableTextWithActions(
    this.text, {
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.strutStyle,
    required this.textHeightBehavior,
    required this.textWidthBasis,
    required this.onHighlight,
    required this.onAnnotate,
  });

  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final StrutStyle strutStyle;
  final TextHeightBehavior? textHeightBehavior;
  final TextWidthBasis textWidthBasis;
  final Future<void> Function(TextSelection selection) onHighlight;
  final Future<void> Function(TextSelection selection) onAnnotate;

  @override
  State<_SelectableTextWithActions> createState() =>
      _SelectableTextWithActionsState();
}

class _SelectableTextWithActionsState
    extends State<_SelectableTextWithActions> {
  static _SelectableTextWithActionsState? _activeToolbarOwner;

  final LayerLink _toolbarLink = LayerLink();
  OverlayEntry? _toolbarEntry;
  TextSelection? _selection;

  @override
  void dispose() {
    _clearSelectionAndToolbar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _toolbarLink,
      child: SelectableText(
        widget.text,
        textAlign: TextAlign.justify,
        textDirection: widget.textDirection,
        textScaler: widget.textScaler,
        strutStyle: widget.strutStyle,
        textHeightBehavior: widget.textHeightBehavior,
        textWidthBasis: widget.textWidthBasis,
        style: widget.style,
        onSelectionChanged: _handleSelectionChanged,
        // Selection actions are rendered by the linked GlassSurface overlay
        // below so Android, desktop and fallback readers share one toolbar.
        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
      ),
    );
  }

  void _handleSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    if (!selection.isValid || selection.isCollapsed) {
      _clearSelectionAndToolbar();
      return;
    }
    final selectedText = selection.textInside(widget.text).trim();
    if (selectedText.isEmpty) {
      _clearSelectionAndToolbar();
      return;
    }
    final previousOwner = _activeToolbarOwner;
    if (!identical(previousOwner, this)) {
      previousOwner?._clearSelectionAndToolbar();
      _activeToolbarOwner = this;
    }
    _selection = selection;
    if (_toolbarEntry == null) {
      _toolbarEntry = OverlayEntry(builder: _buildFloatingToolbar);
      Overlay.of(context).insert(_toolbarEntry!);
    } else {
      _toolbarEntry!.markNeedsBuild();
    }
  }

  Widget _buildFloatingToolbar(BuildContext context) {
    return UnconstrainedBox(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _toolbarLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 8),
        child: SizedBox(
          width: 252,
          height: 44,
          child: GlassSurface(
            level: GlassSurfaceLevel.floating,
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Expanded(
                  child: _SelectionActionButton(
                    icon: Icons.copy_rounded,
                    label: '复制',
                    onPressed: _copySelection,
                  ),
                ),
                Expanded(
                  child: _SelectionActionButton(
                    icon: Icons.border_color_rounded,
                    label: '高亮',
                    onPressed: () {
                      final selection = _selection;
                      if (selection != null) {
                        _runAction(() => widget.onHighlight(selection));
                      }
                    },
                  ),
                ),
                Expanded(
                  child: _SelectionActionButton(
                    icon: Icons.mode_comment_outlined,
                    label: '批注',
                    onPressed: () {
                      final selection = _selection;
                      if (selection != null) {
                        _runAction(() => widget.onAnnotate(selection));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copySelection() async {
    final selection = _selection;
    if (selection == null) {
      return;
    }
    _clearSelectionAndToolbar();
    await Clipboard.setData(
      ClipboardData(text: selection.textInside(widget.text)),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    _clearSelectionAndToolbar();
    await action();
  }

  void _clearSelectionAndToolbar() {
    _selection = null;
    _removeToolbar();
    if (identical(_activeToolbarOwner, this)) {
      _activeToolbarOwner = null;
    }
  }

  void _removeToolbar() {
    _toolbarEntry?.remove();
    _toolbarEntry = null;
  }
}

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 42),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
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

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
    required this.strutStyle,
    required this.textHeightBehavior,
    required this.textWidthBasis,
    required this.annotations,
    required this.drawBackgrounds,
    required this.drawUnderlines,
  });

  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;
  final StrutStyle strutStyle;
  final TextHeightBehavior? textHeightBehavior;
  final TextWidthBasis textWidthBasis;
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
      textScaler: textScaler,
      locale: locale,
      strutStyle: strutStyle,
      textHeightBehavior: textHeightBehavior,
      textWidthBasis: textWidthBasis,
    )..layout(maxWidth: size.width);
    final lineMetrics = textPainter.computeLineMetrics();

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
      final lineColor =
          annotation.annotation.color == null ||
              annotation.annotation.color!.isEmpty
          ? const Color(0xFFC3924A)
          : Color(
              int.parse('0xFF${annotation.annotation.color!.substring(1)}'),
            );
      final highlightColor =
          annotation.annotation.color == null ||
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
          final lineBottom = _lineBottomForRect(rect, lineMetrics, size.height);
          switch (annotation.anchor.underlineStyle) {
            case AnnotationUnderlineStyle.none:
              break;
            case AnnotationUnderlineStyle.solid:
              const strokeWidth = 1.8;
              final underlineY = _underlineCenterY(
                rect: rect,
                lineBottom: lineBottom,
                canvasHeight: size.height,
                decorationExtent: strokeWidth / 2,
              );
              final paint = Paint()
                ..color = lineColor
                ..strokeWidth = strokeWidth
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round;
              canvas.drawLine(
                Offset(rect.left, underlineY),
                Offset(rect.right, underlineY),
                paint,
              );
              break;
            case AnnotationUnderlineStyle.dotted:
              const radius = 1.3;
              final underlineY = _underlineCenterY(
                rect: rect,
                lineBottom: lineBottom,
                canvasHeight: size.height,
                decorationExtent: radius,
              );
              final paint = Paint()
                ..color = lineColor
                ..style = PaintingStyle.fill;
              const gap = 5.0;
              for (double x = rect.left; x <= rect.right; x += gap) {
                canvas.drawCircle(Offset(x, underlineY), radius, paint);
              }
              break;
            case AnnotationUnderlineStyle.wavy:
              const strokeWidth = 1.6;
              const amplitude = 2.0;
              final underlineY = _underlineCenterY(
                rect: rect,
                lineBottom: lineBottom,
                canvasHeight: size.height,
                decorationExtent: amplitude + strokeWidth / 2,
              );
              final paint = Paint()
                ..color = lineColor
                ..strokeWidth = strokeWidth
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round;
              final path = Path()..moveTo(rect.left, underlineY);
              const waveLength = 8.0;
              double x = rect.left;
              while (x < rect.right) {
                final nextX = math.min(x + waveLength / 2, rect.right);
                final controlX = x + waveLength / 4;
                path.quadraticBezierTo(
                  controlX,
                  underlineY - amplitude,
                  nextX,
                  underlineY,
                );
                if (nextX >= rect.right) {
                  break;
                }
                final endX = math.min(nextX + waveLength / 2, rect.right);
                final nextControlX = nextX + waveLength / 4;
                path.quadraticBezierTo(
                  nextControlX,
                  underlineY + amplitude,
                  endX,
                  underlineY,
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

  double _lineBottomForRect(
    Rect rect,
    List<ui.LineMetrics> lineMetrics,
    double canvasHeight,
  ) {
    if (lineMetrics.isEmpty) {
      return canvasHeight;
    }
    final centerY = rect.center.dy;
    ui.LineMetrics nearest = lineMetrics.first;
    var nearestDistance = double.infinity;
    for (final line in lineMetrics) {
      final top = line.baseline - line.ascent;
      final bottom = line.baseline + line.descent;
      if (centerY >= top - 0.5 && centerY <= bottom + 0.5) {
        return math.min(canvasHeight, bottom);
      }
      final distance = (centerY - line.baseline).abs();
      if (distance < nearestDistance) {
        nearest = line;
        nearestDistance = distance;
      }
    }
    return math.min(canvasHeight, nearest.baseline + nearest.descent);
  }

  double _underlineCenterY({
    required Rect rect,
    required double lineBottom,
    required double canvasHeight,
    required double decorationExtent,
  }) {
    final safeBottom = math.min(canvasHeight, lineBottom);
    return math.min(rect.bottom + 1.8, safeBottom - decorationExtent);
  }

  List<Rect> _mergeBoxes(List<TextBox> boxes) {
    final rects =
        boxes
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
      final existingLine = groupedByLine.cast<List<Rect>?>().firstWhere((line) {
        if (line == null || line.isEmpty) {
          return false;
        }
        final probe = line.first;
        return (rect.top - probe.top).abs() < 1.5 &&
            (rect.bottom - probe.bottom).abs() < 1.5;
      }, orElse: () => null);
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
      merged.add(Rect.fromLTRB(lineLeft, lineTop, lineRight, lineBottom));
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
      const minimumLineGap = 0.8;
      final previous = index == 0 ? null : lineRects[index - 1];
      final next = index == lineRects.length - 1 ? null : lineRects[index + 1];
      final previousBoundary = previous == null
          ? 0.0
          : (previous.bottom + rect.top) / 2;
      final nextBoundary = next == null
          ? canvasHeight
          : (rect.bottom + next.top) / 2;
      return Rect.fromLTRB(
        rect.left,
        math.max(
          rect.top + minimumLineGap / 2,
          previousBoundary + minimumLineGap / 2,
        ),
        rect.right,
        math.min(
          rect.bottom - minimumLineGap / 2,
          nextBoundary - minimumLineGap / 2,
        ),
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

    for (final rect in lineRects) {
      final expanded = Rect.fromLTRB(
        rect.left - 1.2,
        math.max(0, rect.top),
        rect.right + 1.2,
        math.min(size.height, rect.bottom),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(expanded, const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return text != oldDelegate.text ||
        style != oldDelegate.style ||
        textDirection != oldDelegate.textDirection ||
        textScaler != oldDelegate.textScaler ||
        locale != oldDelegate.locale ||
        strutStyle != oldDelegate.strutStyle ||
        textHeightBehavior != oldDelegate.textHeightBehavior ||
        textWidthBasis != oldDelegate.textWidthBasis ||
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
