import 'annotation_center_controller.dart';

String buildAnnotationMarkdown({
  required List<AnnotationBookGroup> groups,
  required String userDisplayName,
  required String username,
  required DateTime exportedAt,
}) {
  final annotationCount = groups.fold<int>(
    0,
    (total, group) => total + group.annotationCount,
  );
  final userLabel = userDisplayName.trim() == username.trim()
      ? username.trim()
      : '${userDisplayName.trim()}（${username.trim()}）';
  final buffer = StringBuffer()
    ..writeln('# 轻阅批注导出')
    ..writeln()
    ..writeln('- 导出用户：${_inline(userLabel)}')
    ..writeln('- 导出时间：${_formatDateTime(exportedAt)}')
    ..writeln('- 书籍数量：${groups.length}')
    ..writeln('- 批注数量：$annotationCount');

  for (var bookIndex = 0; bookIndex < groups.length; bookIndex++) {
    final group = groups[bookIndex];
    buffer
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('## ${bookIndex + 1}. ${_heading(group.book.title)}')
      ..writeln()
      ..writeln('- 作者：${_inline(_nonEmpty(group.book.author, '未知作者'))}')
      ..writeln('- 格式：${_inline(group.book.format.toUpperCase())}')
      ..writeln('- 批注数量：${group.annotationCount}');

    for (var entryIndex = 0; entryIndex < group.entries.length; entryIndex++) {
      final annotation = group.entries[entryIndex].annotation;
      final quote = annotation.quoteText?.trim();
      final note = annotation.noteText?.trim();
      buffer
        ..writeln()
        ..writeln('### 批注 ${entryIndex + 1}')
        ..writeln()
        ..writeln(
          '> ${_blockquote(quote?.isNotEmpty == true ? quote! : '未记录高亮原文')}',
        );
      if (note?.isNotEmpty == true) {
        buffer
          ..writeln()
          ..writeln('**笔记**')
          ..writeln()
          ..writeln(note);
      }
      buffer
        ..writeln()
        ..writeln('- 更新时间：${_formatSourceDateTime(annotation.updatedAt)}');
    }
  }

  return buffer.toString();
}

String buildAnnotationExportFileName({
  required String username,
  required DateTime exportedAt,
}) {
  final safeUsername = username
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
      .replaceAll(RegExp(r'\s+'), '-');
  final userPart = safeUsername.isEmpty ? 'current-user' : safeUsername;
  final stamp =
      '${exportedAt.year.toString().padLeft(4, '0')}'
      '${exportedAt.month.toString().padLeft(2, '0')}'
      '${exportedAt.day.toString().padLeft(2, '0')}-'
      '${exportedAt.hour.toString().padLeft(2, '0')}'
      '${exportedAt.minute.toString().padLeft(2, '0')}';
  return '轻阅批注-$userPart-$stamp.md';
}

String _nonEmpty(String? value, String fallback) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? fallback : normalized;
}

String _heading(String value) => value
    .replaceAll('\\', r'\\')
    .replaceAll('#', r'\#')
    .replaceAll(RegExp(r'[\r\n]+'), ' ')
    .trim();

String _inline(String value) =>
    value.replaceAll('\\', r'\\').replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

String _blockquote(String value) => value
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n')
    .map((line) => line.trimRight())
    .join('\n> ');

String _formatSourceDateTime(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? value : _formatDateTime(parsed.toLocal());
}

String _formatDateTime(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
