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
  });

  final String blockAnchor;
  final int? startOffset;
  final int? endOffset;
  final AnnotationUnderlineStyle underlineStyle;

  bool get hasExplicitRange => startOffset != null && endOffset != null;

  factory AnnotationAnchor.parse(String rawAnchor) {
    if (rawAnchor.isEmpty) {
      return const AnnotationAnchor(
        blockAnchor: '',
        startOffset: null,
        endOffset: null,
        underlineStyle: AnnotationUnderlineStyle.none,
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
    );
  }

  AnnotationAnchor copyWith({
    String? blockAnchor,
    int? startOffset,
    int? endOffset,
    AnnotationUnderlineStyle? underlineStyle,
    bool replaceOffsets = false,
  }) {
    return AnnotationAnchor(
      blockAnchor: blockAnchor ?? this.blockAnchor,
      startOffset: replaceOffsets ? startOffset : startOffset ?? this.startOffset,
      endOffset: replaceOffsets ? endOffset : endOffset ?? this.endOffset,
      underlineStyle: underlineStyle ?? this.underlineStyle,
    );
  }

  String serialize() {
    if (!hasExplicitRange &&
        underlineStyle == AnnotationUnderlineStyle.none &&
        blockAnchor.isNotEmpty) {
      return blockAnchor;
    }

    return jsonEncode({
      'blockAnchor': blockAnchor,
      if (startOffset != null) 'startOffset': startOffset,
      if (endOffset != null) 'endOffset': endOffset,
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
}

class AnnotationTextRange {
  const AnnotationTextRange({
    required this.start,
    required this.end,
  });

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
  });

  final String blockAnchor;
  final String blockText;
  final int startOffset;
  final int endOffset;

  String get selectedText => blockText.substring(startOffset, endOffset);

  AnnotationTextRange get range =>
      AnnotationTextRange(start: startOffset, end: endOffset);

  String toAnchorString({
    required AnnotationUnderlineStyle underlineStyle,
  }) {
    return AnnotationAnchor(
      blockAnchor: blockAnchor,
      startOffset: startOffset,
      endOffset: endOffset,
      underlineStyle: underlineStyle,
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
    String blockText,
  ) {
    final parsed = AnnotationAnchor.parse(annotation.anchor);
    if (parsed.blockAnchor.isEmpty) {
      return null;
    }
    return ResolvedAnnotation(
      annotation: annotation,
      anchor: parsed,
      range: parsed.normalizedRangeIn(blockText),
    );
  }
}
