class BookSummary {
  const BookSummary({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.pluginId,
    required this.format,
    required this.sourceMissing,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String? author;
  final String? description;
  final String pluginId;
  final String format;
  final bool sourceMissing;
  final String updatedAt;

  factory BookSummary.fromJson(Map<String, dynamic> json) {
    return BookSummary(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '未命名书籍',
      author: json['author'] as String?,
      description: json['description'] as String?,
      pluginId: json['pluginId'] as String? ?? '',
      format: (json['format'] as String? ?? '').toLowerCase(),
      sourceMissing: json['sourceMissing'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class BookDetail extends BookSummary {
  const BookDetail({
    required super.id,
    required super.title,
    required super.author,
    required super.description,
    required super.pluginId,
    required super.format,
    required super.sourceMissing,
    required super.updatedAt,
    required this.sourceType,
    required this.manifest,
    required this.capabilities,
    required this.hasStructuredContent,
    required this.contentModel,
    required this.latestContentVersionId,
  });

  final String sourceType;
  final Map<String, dynamic>? manifest;
  final List<String> capabilities;
  final bool hasStructuredContent;
  final String? contentModel;
  final int? latestContentVersionId;

  bool get supportsStructuredReader =>
      hasStructuredContent && (format == 'txt' || format == 'epub');

  factory BookDetail.fromJson(Map<String, dynamic> json) {
    return BookDetail(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '未命名书籍',
      author: json['author'] as String?,
      description: json['description'] as String?,
      pluginId: json['pluginId'] as String? ?? '',
      format: (json['format'] as String? ?? '').toLowerCase(),
      sourceMissing: json['sourceMissing'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? '',
      manifest: json['manifest'] as Map<String, dynamic>?,
      capabilities:
          ((json['capabilities'] as List<dynamic>?) ?? const <dynamic>[])
              .map((item) => item.toString())
              .toList(),
      hasStructuredContent: json['hasStructuredContent'] as bool? ?? false,
      contentModel: json['contentModel'] as String?,
      latestContentVersionId: (json['latestContentVersionId'] as num?)?.toInt(),
    );
  }
}

class BookContent {
  const BookContent({
    required this.bookId,
    required this.contentModel,
    required this.contentVersionId,
    required this.hasStructuredContent,
    required this.chapters,
  });

  final int bookId;
  final String? contentModel;
  final int? contentVersionId;
  final bool hasStructuredContent;
  final List<BookContentChapterSummary> chapters;

  factory BookContent.fromJson(Map<String, dynamic> json) {
    return BookContent(
      bookId: (json['bookId'] as num).toInt(),
      contentModel: json['contentModel'] as String?,
      contentVersionId: (json['contentVersionId'] as num?)?.toInt(),
      hasStructuredContent: json['hasStructuredContent'] as bool? ?? false,
      chapters: ((json['chapters'] as List<dynamic>?) ?? const <dynamic>[])
          .map(
            (item) => BookContentChapterSummary.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class BookContentChapterSummary {
  const BookContentChapterSummary({
    required this.chapterIndex,
    required this.title,
    required this.anchor,
  });

  final int chapterIndex;
  final String title;
  final String anchor;

  factory BookContentChapterSummary.fromJson(Map<String, dynamic> json) {
    return BookContentChapterSummary(
      chapterIndex: (json['chapterIndex'] as num).toInt(),
      title: json['title'] as String? ?? '未命名章节',
      anchor: json['anchor'] as String? ?? '',
    );
  }
}

class BookContentChapter {
  const BookContentChapter({
    required this.bookId,
    required this.contentModel,
    required this.contentVersionId,
    required this.hasStructuredContent,
    required this.chapterIndex,
    required this.title,
    required this.anchor,
    required this.blocks,
  });

  final int bookId;
  final String contentModel;
  final int contentVersionId;
  final bool hasStructuredContent;
  final int chapterIndex;
  final String title;
  final String anchor;
  final List<BookContentBlock> blocks;

  factory BookContentChapter.fromJson(Map<String, dynamic> json) {
    return BookContentChapter(
      bookId: (json['bookId'] as num).toInt(),
      contentModel: json['contentModel'] as String? ?? '',
      contentVersionId: (json['contentVersionId'] as num).toInt(),
      hasStructuredContent: json['hasStructuredContent'] as bool? ?? false,
      chapterIndex: (json['chapterIndex'] as num).toInt(),
      title: json['title'] as String? ?? '未命名章节',
      anchor: json['anchor'] as String? ?? '',
      blocks: ((json['blocks'] as List<dynamic>?) ?? const <dynamic>[])
          .map(
            (item) => BookContentBlock.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class BookContentBlock {
  const BookContentBlock({
    required this.blockIndex,
    required this.type,
    required this.anchor,
    required this.text,
    required this.plainText,
    required this.meta,
  });

  final int blockIndex;
  final String type;
  final String anchor;
  final String text;
  final String plainText;
  final Map<String, dynamic> meta;

  String get renderedText => text.isNotEmpty ? text : plainText;

  factory BookContentBlock.fromJson(Map<String, dynamic> json) {
    return BookContentBlock(
      blockIndex: (json['blockIndex'] as num).toInt(),
      type: json['type'] as String? ?? 'paragraph',
      anchor: json['anchor'] as String? ?? '',
      text: json['text'] as String? ?? '',
      plainText: json['plainText'] as String? ?? '',
      meta: (json['meta'] as Map<String, dynamic>?) ?? const {},
    );
  }
}
