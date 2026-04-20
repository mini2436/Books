import 'dart:convert';

enum PendingEntityType { annotation, bookmark, progress }

class AnnotationView {
  const AnnotationView({
    required this.id,
    required this.bookId,
    required this.quoteText,
    required this.noteText,
    required this.color,
    required this.anchor,
    required this.version,
    required this.deleted,
    required this.updatedAt,
  });

  final int id;
  final int bookId;
  final String? quoteText;
  final String? noteText;
  final String? color;
  final String anchor;
  final int version;
  final bool deleted;
  final String updatedAt;

  factory AnnotationView.fromJson(Map<String, dynamic> json) {
    return AnnotationView(
      id: (json['id'] as num).toInt(),
      bookId: (json['bookId'] as num).toInt(),
      quoteText: json['quoteText'] as String?,
      noteText: json['noteText'] as String?,
      color: json['color'] as String?,
      anchor: json['anchor'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
      deleted: json['deleted'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class BookmarkView {
  const BookmarkView({
    required this.id,
    required this.bookId,
    required this.location,
    required this.label,
    required this.deleted,
    required this.updatedAt,
  });

  final int id;
  final int bookId;
  final String location;
  final String? label;
  final bool deleted;
  final String updatedAt;

  factory BookmarkView.fromJson(Map<String, dynamic> json) {
    return BookmarkView(
      id: (json['id'] as num).toInt(),
      bookId: (json['bookId'] as num).toInt(),
      location: json['location'] as String? ?? '',
      label: json['label'] as String?,
      deleted: json['deleted'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class ReadingProgressView {
  const ReadingProgressView({
    required this.bookId,
    required this.location,
    required this.progressPercent,
    required this.updatedAt,
  });

  final int bookId;
  final String location;
  final double progressPercent;
  final String updatedAt;

  factory ReadingProgressView.fromJson(Map<String, dynamic> json) {
    return ReadingProgressView(
      bookId: (json['bookId'] as num).toInt(),
      location: json['location'] as String? ?? '',
      progressPercent: (json['progressPercent'] as num?)?.toDouble() ?? 0,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class AnnotationMutation {
  const AnnotationMutation({
    this.clientTempId,
    this.annotationId,
    required this.bookId,
    required this.action,
    this.quoteText,
    this.noteText,
    this.color,
    required this.anchor,
    this.baseVersion,
    required this.updatedAt,
  });

  final String? clientTempId;
  final int? annotationId;
  final int bookId;
  final String action;
  final String? quoteText;
  final String? noteText;
  final String? color;
  final String anchor;
  final int? baseVersion;
  final String updatedAt;

  Map<String, dynamic> toJson() => {
    'clientTempId': clientTempId,
    'annotationId': annotationId,
    'bookId': bookId,
    'action': action,
    'quoteText': quoteText,
    'noteText': noteText,
    'color': color,
    'anchor': anchor,
    'baseVersion': baseVersion,
    'updatedAt': updatedAt,
  };

  factory AnnotationMutation.fromJson(Map<String, dynamic> json) {
    return AnnotationMutation(
      clientTempId: json['clientTempId'] as String?,
      annotationId: (json['annotationId'] as num?)?.toInt(),
      bookId: (json['bookId'] as num).toInt(),
      action: json['action'] as String? ?? 'CREATE',
      quoteText: json['quoteText'] as String?,
      noteText: json['noteText'] as String?,
      color: json['color'] as String?,
      anchor: json['anchor'] as String? ?? '',
      baseVersion: (json['baseVersion'] as num?)?.toInt(),
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class BookmarkMutation {
  const BookmarkMutation({
    this.bookmarkId,
    required this.bookId,
    required this.action,
    required this.location,
    this.label,
    required this.updatedAt,
  });

  final int? bookmarkId;
  final int bookId;
  final String action;
  final String location;
  final String? label;
  final String updatedAt;

  Map<String, dynamic> toJson() => {
    'bookmarkId': bookmarkId,
    'bookId': bookId,
    'action': action,
    'location': location,
    'label': label,
    'updatedAt': updatedAt,
  };

  factory BookmarkMutation.fromJson(Map<String, dynamic> json) {
    return BookmarkMutation(
      bookmarkId: (json['bookmarkId'] as num?)?.toInt(),
      bookId: (json['bookId'] as num).toInt(),
      action: json['action'] as String? ?? 'CREATE',
      location: json['location'] as String? ?? '',
      label: json['label'] as String?,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class ReadingProgressMutation {
  const ReadingProgressMutation({
    required this.bookId,
    required this.location,
    required this.progressPercent,
    required this.updatedAt,
  });

  final int bookId;
  final String location;
  final double progressPercent;
  final String updatedAt;

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'location': location,
    'progressPercent': progressPercent,
    'updatedAt': updatedAt,
  };

  factory ReadingProgressMutation.fromJson(Map<String, dynamic> json) {
    return ReadingProgressMutation(
      bookId: (json['bookId'] as num).toInt(),
      location: json['location'] as String? ?? '',
      progressPercent: (json['progressPercent'] as num?)?.toDouble() ?? 0,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class SyncPushRequest {
  const SyncPushRequest({
    this.annotations = const [],
    this.bookmarks = const [],
    this.progresses = const [],
  });

  final List<AnnotationMutation> annotations;
  final List<BookmarkMutation> bookmarks;
  final List<ReadingProgressMutation> progresses;

  Map<String, dynamic> toJson() => {
    'annotations': annotations.map((item) => item.toJson()).toList(),
    'bookmarks': bookmarks.map((item) => item.toJson()).toList(),
    'progresses': progresses.map((item) => item.toJson()).toList(),
  };
}

class SyncConflict {
  const SyncConflict({
    required this.entityType,
    required this.entityId,
    required this.message,
  });

  final String entityType;
  final int entityId;
  final String message;

  factory SyncConflict.fromJson(Map<String, dynamic> json) {
    return SyncConflict(
      entityType: json['entityType'] as String? ?? '',
      entityId: (json['entityId'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
    );
  }
}

class SyncPushResponse {
  const SyncPushResponse({
    required this.annotationMappings,
    required this.conflicts,
  });

  final Map<String, int> annotationMappings;
  final List<SyncConflict> conflicts;

  factory SyncPushResponse.fromJson(Map<String, dynamic> json) {
    final rawMappings =
        (json['annotationMappings'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    return SyncPushResponse(
      annotationMappings: rawMappings.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      ),
      conflicts: ((json['conflicts'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => SyncConflict.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SyncPullResponse {
  const SyncPullResponse({
    required this.cursor,
    required this.annotations,
    required this.bookmarks,
    required this.progresses,
  });

  final int cursor;
  final List<AnnotationView> annotations;
  final List<BookmarkView> bookmarks;
  final List<ReadingProgressView> progresses;

  factory SyncPullResponse.fromJson(Map<String, dynamic> json) {
    return SyncPullResponse(
      cursor: (json['cursor'] as num?)?.toInt() ?? 0,
      annotations: ((json['annotations'] as List<dynamic>?) ?? const [])
          .map((item) => AnnotationView.fromJson(item as Map<String, dynamic>))
          .toList(),
      bookmarks: ((json['bookmarks'] as List<dynamic>?) ?? const [])
          .map((item) => BookmarkView.fromJson(item as Map<String, dynamic>))
          .toList(),
      progresses: ((json['progresses'] as List<dynamic>?) ?? const [])
          .map(
            (item) =>
                ReadingProgressView.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.entityType,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final PendingEntityType entityType;
  final Map<String, dynamic> payload;
  final String createdAt;

  Map<String, dynamic> toDatabaseRow() => {
    'id': id,
    'entity_type': entityType.name,
    'payload': jsonEncode(payload),
    'created_at': createdAt,
  };

  factory PendingOperation.fromDatabaseRow(Map<String, Object?> row) {
    return PendingOperation(
      id: row['id'] as String,
      entityType: PendingEntityType.values.byName(row['entity_type'] as String),
      payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      createdAt: row['created_at'] as String,
    );
  }
}
