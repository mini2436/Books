class AdminBookSummary {
  const AdminBookSummary({
    required this.id,
    required this.title,
    required this.author,
    required this.groupName,
    required this.description,
    required this.pluginId,
    required this.format,
    required this.sourceType,
    required this.sourceMissing,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String? author;
  final String? groupName;
  final String? description;
  final String pluginId;
  final String format;
  final String sourceType;
  final bool sourceMissing;
  final String updatedAt;

  factory AdminBookSummary.fromJson(Map<String, dynamic> json) {
    return AdminBookSummary(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '未命名书籍',
      author: json['author'] as String?,
      groupName: json['groupName'] as String?,
      description: json['description'] as String?,
      pluginId: json['pluginId'] as String? ?? '',
      format: (json['format'] as String? ?? '').toUpperCase(),
      sourceType: json['sourceType'] as String? ?? '',
      sourceMissing: json['sourceMissing'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  AdminBookSummary copyWith({
    String? title,
    String? author,
    String? groupName,
    String? description,
    String? pluginId,
    String? format,
    String? sourceType,
    bool? sourceMissing,
    String? updatedAt,
  }) {
    return AdminBookSummary(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      groupName: groupName ?? this.groupName,
      description: description ?? this.description,
      pluginId: pluginId ?? this.pluginId,
      format: format ?? this.format,
      sourceType: sourceType ?? this.sourceType,
      sourceMissing: sourceMissing ?? this.sourceMissing,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AdminBookDetail {
  const AdminBookDetail({
    required this.id,
    required this.title,
    required this.author,
    required this.groupName,
    required this.description,
    required this.pluginId,
    required this.format,
    required this.sourceType,
    required this.sourceMissing,
    required this.hasStructuredContent,
    required this.contentModel,
    required this.latestContentVersionId,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String? author;
  final String? groupName;
  final String? description;
  final String pluginId;
  final String format;
  final String sourceType;
  final bool sourceMissing;
  final bool hasStructuredContent;
  final String? contentModel;
  final int? latestContentVersionId;
  final String updatedAt;

  factory AdminBookDetail.fromJson(Map<String, dynamic> json) {
    return AdminBookDetail(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '未命名书籍',
      author: json['author'] as String?,
      groupName: json['groupName'] as String?,
      description: json['description'] as String?,
      pluginId: json['pluginId'] as String? ?? '',
      format: (json['format'] as String? ?? '').toUpperCase(),
      sourceType: json['sourceType'] as String? ?? '',
      sourceMissing: json['sourceMissing'] as bool? ?? false,
      hasStructuredContent: json['hasStructuredContent'] as bool? ?? false,
      contentModel: json['contentModel'] as String?,
      latestContentVersionId: (json['latestContentVersionId'] as num?)?.toInt(),
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

class AdminUserView {
  const AdminUserView({
    required this.id,
    required this.username,
    required this.role,
    required this.enabled,
  });

  final int id;
  final String username;
  final String role;
  final bool enabled;

  factory AdminUserView.fromJson(Map<String, dynamic> json) {
    return AdminUserView(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String? ?? '',
      role: json['role'] as String? ?? 'READER',
      enabled: json['enabled'] as bool? ?? false,
    );
  }

  AdminUserView copyWith({String? role, bool? enabled}) {
    return AdminUserView(
      id: id,
      username: username,
      role: role ?? this.role,
      enabled: enabled ?? this.enabled,
    );
  }
}

class AdminAnnotationView {
  const AdminAnnotationView({
    required this.id,
    required this.userId,
    required this.username,
    required this.bookId,
    required this.bookTitle,
    required this.quoteText,
    required this.noteText,
    required this.color,
    required this.anchor,
    required this.version,
    required this.deleted,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final String username;
  final int bookId;
  final String bookTitle;
  final String? quoteText;
  final String? noteText;
  final String? color;
  final String anchor;
  final int version;
  final bool deleted;
  final String updatedAt;

  factory AdminAnnotationView.fromJson(Map<String, dynamic> json) {
    return AdminAnnotationView(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      username: json['username'] as String? ?? '',
      bookId: (json['bookId'] as num).toInt(),
      bookTitle: json['bookTitle'] as String? ?? '未命名书籍',
      quoteText: json['quoteText'] as String?,
      noteText: json['noteText'] as String?,
      color: json['color'] as String?,
      anchor: json['anchor'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
      deleted: json['deleted'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  AdminAnnotationView copyWith({bool? deleted}) {
    return AdminAnnotationView(
      id: id,
      userId: userId,
      username: username,
      bookId: bookId,
      bookTitle: bookTitle,
      quoteText: quoteText,
      noteText: noteText,
      color: color,
      anchor: anchor,
      version: version,
      deleted: deleted ?? this.deleted,
      updatedAt: updatedAt,
    );
  }
}

class AdminBookmarkView {
  const AdminBookmarkView({
    required this.id,
    required this.userId,
    required this.username,
    required this.bookId,
    required this.bookTitle,
    required this.location,
    required this.label,
    required this.deleted,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final String username;
  final int bookId;
  final String bookTitle;
  final String location;
  final String? label;
  final bool deleted;
  final String updatedAt;

  factory AdminBookmarkView.fromJson(Map<String, dynamic> json) {
    return AdminBookmarkView(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      username: json['username'] as String? ?? '',
      bookId: (json['bookId'] as num).toInt(),
      bookTitle: json['bookTitle'] as String? ?? '未命名书籍',
      location: json['location'] as String? ?? '',
      label: json['label'] as String?,
      deleted: json['deleted'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  AdminBookmarkView copyWith({bool? deleted}) {
    return AdminBookmarkView(
      id: id,
      userId: userId,
      username: username,
      bookId: bookId,
      bookTitle: bookTitle,
      location: location,
      label: label,
      deleted: deleted ?? this.deleted,
      updatedAt: updatedAt,
    );
  }
}

class AdminRoleSummary {
  const AdminRoleSummary({
    required this.role,
    required this.label,
    required this.description,
    required this.userCount,
  });

  final String role;
  final String label;
  final String description;
  final int userCount;
}

class BookViewerView {
  const BookViewerView({
    required this.userId,
    required this.username,
    required this.role,
    required this.enabled,
    required this.accessSource,
    required this.grantedAt,
  });

  final int userId;
  final String username;
  final String role;
  final bool enabled;
  final String accessSource;
  final String? grantedAt;

  bool get isGlobalAccess => accessSource == 'GLOBAL_ROLE';
  bool get isExplicitGrant => !isGlobalAccess;

  factory BookViewerView.fromJson(Map<String, dynamic> json) {
    return BookViewerView(
      userId: (json['userId'] as num).toInt(),
      username: json['username'] as String? ?? '',
      role: json['role'] as String? ?? 'READER',
      enabled: json['enabled'] as bool? ?? false,
      accessSource: json['accessSource'] as String? ?? 'EXPLICIT_GRANT',
      grantedAt: json['grantedAt'] as String?,
    );
  }
}

const adminRoles = ['SUPER_ADMIN', 'LIBRARIAN', 'READER'];

String adminRoleLabel(String role) {
  switch (role) {
    case 'SUPER_ADMIN':
      return '超级管理员';
    case 'LIBRARIAN':
      return '馆员';
    default:
      return '读者';
  }
}

String adminRoleDescription(String role) {
  switch (role) {
    case 'SUPER_ADMIN':
      return '可管理用户、角色与全部后台能力';
    case 'LIBRARIAN':
      return '可管理图书、批注与书签';
    default:
      return '仅使用阅读与同步功能';
  }
}
