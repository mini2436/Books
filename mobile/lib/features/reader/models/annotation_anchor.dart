import 'dart:convert';

import '../../../data/models/sync_models.dart';

enum AnnotationUnderlineStyle {
  none,
  solid,
  dotted,
  wavy;

  String get value => switch (this) {
    AnnotationUnderlineStyle.none => 'none',
    AnnotationUnderlineStyle.solid => 'solid',
    AnnotationUnderlineStyle.dotted => 'dotted',
    AnnotationUnderlineStyle.wavy => 'wavy',
  };

  static AnnotationUnderlineStyle fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'solid' => AnnotationUnderlineStyle.solid,
      'dotted' => AnnotationUnderlineStyle.dotted,
      'wavy' => AnnotationUnderlineStyle.wavy,
      _ => AnnotationUnderlineStyle.none,
    };
  }
}

class AnnotationAnchor {
  const AnnotationAnchor({
    required this.blockAnchor,
    required this.startOffset,
    required this.endOffset,
    required this.underlineStyle,
    this.endBlockAnchor,
  });

  final String blockAnchor;
  final int? startOffset;
  final int? endOffset;
  final AnnotationUnderlineStyle underlineStyle;
  final String? endBlockAnchor;

  String get effectiveEndBlockAnchor {
    final candidate = endBlockAnchor;
    if (candidate == null || candidate.isEmpty) {
      return blockAnchor;
    }
    return candidate;
  }

  bool get spansMultipleBlocks => effectiveEndBlockAnchor != blockAnchor;

  bool get hasExplicitRange => startOffset != null && endOffset != null;

  factory AnnotationAnchor.parse(String rawAnchor) {
    if (rawAnchor.isEmpty) {
      return const AnnotationAnchor(
        blockAnchor: '',
        startOffset: null,
        endOffset: null,
        underlineStyle: AnnotationUnderlineStyle.none,
        endBlockAnchor: null,
      );
    }

    try {
      final decoded = jsonDecode(rawAnchor);
      if (decoded is Map<String, dynamic>) {
        return AnnotationAnchor(
          blockAnchor:
              decoded['blockAnchor'] as String? ??
              decoded['anchor'] as String? ??
              rawAnchor,
          startOffset: (decoded['startOffset'] as num?)?.toInt(),
          endOffset: (decoded['endOffset'] as num?)?.toInt(),
          endBlockAnchor:
              decoded['endBlockAnchor'] as String? ??
              decoded['endAnchor'] as String?,
          underlineStyle: AnnotationUnderlineStyle.fromValue(
            decoded['underlineStyle'] as String?,
          ),
        );
      }
    } catch (_) {
      // Fall back to legacy plain anchor strings.
    }

    return AnnotationAnchor(
      blockAnchor: rawAnchor,
      startOffset: null,
      endOffset: null,
      underlineStyle: AnnotationUnderlineStyle.none,
      endBlockAnchor: null,
    );
  }

  AnnotationAnchor copyWith({
    String? blockAnchor,
    int? startOffset,
    int? endOffset,
    String? endBlockAnchor,
    AnnotationUnderlineStyle? underlineStyle,
    bool replaceOffsets = false,
    bool replaceEndBlockAnchor = false,
  }) {
    return AnnotationAnchor(
      blockAnchor: blockAnchor ?? this.blockAnchor,
      startOffset: replaceOffsets
          ? startOffset
          : startOffset ?? this.startOffset,
      endOffset: replaceOffsets ? endOffset : endOffset ?? this.endOffset,
      underlineStyle: underlineStyle ?? this.underlineStyle,
      endBlockAnchor: replaceEndBlockAnchor
          ? endBlockAnchor
          : endBlockAnchor ?? this.endBlockAnchor,
    );
  }

  String serialize() {
    if (!hasExplicitRange &&
        underlineStyle == AnnotationUnderlineStyle.none &&
        !spansMultipleBlocks &&
        blockAnchor.isNotEmpty) {
      return blockAnchor;
    }

    return jsonEncode({
      'blockAnchor': blockAnchor,
      if (startOffset != null) 'startOffset': startOffset,
      if (endOffset != null) 'endOffset': endOffset,
      if (spansMultipleBlocks) 'endBlockAnchor': effectiveEndBlockAnchor,
      if (underlineStyle != AnnotationUnderlineStyle.none)
        'underlineStyle': underlineStyle.value,
    });
  }

  int normalizedStart(String text) {
    final raw = startOffset ?? 0;
    return raw.clamp(0, text.length);
  }

  int normalizedEnd(String text) {
    final raw = endOffset ?? text.length;
    return raw.clamp(0, text.length);
  }

  bool containsRange({
    required int start,
    required int end,
    required String text,
  }) {
    final normalizedRange = normalizedRangeIn(text);
    return start >= normalizedRange.start && end <= normalizedRange.end;
  }

  bool overlapsOrTouches({
    required int start,
    required int end,
    required String text,
  }) {
    final normalizedRange = normalizedRangeIn(text);
    return end >= normalizedRange.start && start <= normalizedRange.end;
  }

  AnnotationTextRange normalizedRangeIn(String text) {
    final start = normalizedStart(text);
    final end = normalizedEnd(text);
    if (end < start) {
      return AnnotationTextRange(start: end, end: start);
    }
    return AnnotationTextRange(start: start, end: end);
  }

  bool affectsBlock({
    required String currentBlockAnchor,
    required List<String> orderedBlockAnchors,
  }) {
    if (!spansMultipleBlocks) {
      return currentBlockAnchor == blockAnchor;
    }

    final currentIndex = orderedBlockAnchors.indexOf(currentBlockAnchor);
    final startIndex = orderedBlockAnchors.indexOf(blockAnchor);
    final endIndex = orderedBlockAnchors.indexOf(effectiveEndBlockAnchor);
    if (currentIndex < 0 || startIndex < 0 || endIndex < 0) {
      return currentBlockAnchor == blockAnchor ||
          currentBlockAnchor == effectiveEndBlockAnchor;
    }

    final lowerBound = startIndex < endIndex ? startIndex : endIndex;
    final upperBound = startIndex < endIndex ? endIndex : startIndex;
    return currentIndex >= lowerBound && currentIndex <= upperBound;
  }

  AnnotationTextRange? rangeForBlock({
    required String currentBlockAnchor,
    required String blockText,
    required List<String> orderedBlockAnchors,
  }) {
    if (!hasExplicitRange) {
      return null;
    }
    if (!spansMultipleBlocks) {
      if (currentBlockAnchor != blockAnchor) {
        return null;
      }
      return normalizedRangeIn(blockText);
    }
    if (!affectsBlock(
      currentBlockAnchor: currentBlockAnchor,
      orderedBlockAnchors: orderedBlockAnchors,
    )) {
      return null;
    }

    final currentIndex = orderedBlockAnchors.indexOf(currentBlockAnchor);
    final startIndex = orderedBlockAnchors.indexOf(blockAnchor);
    final endIndex = orderedBlockAnchors.indexOf(effectiveEndBlockAnchor);
    if (currentIndex < 0 || startIndex < 0 || endIndex < 0) {
      if (currentBlockAnchor == blockAnchor) {
        return AnnotationTextRange(
          start: normalizedStart(blockText),
          end: blockText.length,
        );
      }
      if (currentBlockAnchor == effectiveEndBlockAnchor) {
        return AnnotationTextRange(start: 0, end: normalizedEnd(blockText));
      }
      return null;
    }

    if (currentIndex == startIndex) {
      return AnnotationTextRange(
        start: normalizedStart(blockText),
        end: blockText.length,
      );
    }
    if (currentIndex == endIndex) {
      return AnnotationTextRange(start: 0, end: normalizedEnd(blockText));
    }
    return AnnotationTextRange(start: 0, end: blockText.length);
  }
}

class AnnotationTextRange {
  const AnnotationTextRange({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;

  AnnotationTextRange union(AnnotationTextRange other) {
    return AnnotationTextRange(
      start: start < other.start ? start : other.start,
      end: end > other.end ? end : other.end,
    );
  }
}

class AnnotationSelection {
  const AnnotationSelection({
    required this.blockAnchor,
    required this.blockText,
    required this.startOffset,
    required this.endOffset,
    this.endBlockAnchor,
    this.endBlockText,
    String? selectedText,
  }) : _selectedText = selectedText;

  final String blockAnchor;
  final String blockText;
  final int startOffset;
  final int endOffset;
  final String? endBlockAnchor;
  final String? endBlockText;
  final String? _selectedText;

  String get effectiveEndBlockAnchor {
    final candidate = endBlockAnchor;
    if (candidate == null || candidate.isEmpty) {
      return blockAnchor;
    }
    return candidate;
  }

  String get effectiveEndBlockText => endBlockText ?? blockText;

  bool get spansMultipleBlocks => effectiveEndBlockAnchor != blockAnchor;

  String get selectedText =>
      _selectedText ??
      (spansMultipleBlocks
          ? blockText.substring(startOffset)
          : blockText.substring(startOffset, endOffset));

  AnnotationTextRange get range =>
      AnnotationTextRange(start: startOffset, end: endOffset);

  String toAnchorString({required AnnotationUnderlineStyle underlineStyle}) {
    return AnnotationAnchor(
      blockAnchor: blockAnchor,
      startOffset: startOffset,
      endOffset: endOffset,
      underlineStyle: underlineStyle,
      endBlockAnchor: spansMultipleBlocks ? effectiveEndBlockAnchor : null,
    ).serialize();
  }
}

class ResolvedAnnotation {
  const ResolvedAnnotation({
    required this.annotation,
    required this.anchor,
    required this.range,
  });

  final AnnotationView annotation;
  final AnnotationAnchor anchor;
  final AnnotationTextRange range;

  static ResolvedAnnotation? fromAnnotation(
    AnnotationView annotation,
    String blockText, {
    required String currentBlockAnchor,
    required List<String> orderedBlockAnchors,
  }) {
    final parsed = AnnotationAnchor.parse(annotation.anchor);
    if (parsed.blockAnchor.isEmpty) {
      return null;
    }
    final range = parsed.rangeForBlock(
      currentBlockAnchor: currentBlockAnchor,
      blockText: blockText,
      orderedBlockAnchors: orderedBlockAnchors,
    );
    if (range == null || range.length <= 0) {
      return null;
    }
    return ResolvedAnnotation(
      annotation: annotation,
      anchor: parsed,
      range: range,
    );
  }
}
