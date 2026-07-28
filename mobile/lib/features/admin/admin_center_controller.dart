import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/admin_models.dart';
import '../../data/models/user_role.dart';
import '../../data/services/api_client.dart';
import '../../data/services/local_library_folder_models.dart';
import '../auth/auth_controller.dart';

final adminCenterControllerProvider =
    ChangeNotifierProvider<AdminCenterController>((ref) {
      return AdminCenterController(
        authController: ref.read(authControllerProvider),
        apiClient: ref.watch(apiClientProvider),
      );
    });

enum AdminSection { users, roles, books, annotations, librarySources }

enum AdminBookImportPhase {
  uploading,
  processing,
  refreshing,
  completed,
  failed,
}

class AdminBookImportProgress {
  const AdminBookImportProgress({
    required this.fileName,
    required this.phase,
    required this.bytesSent,
    required this.totalBytes,
    this.importedTitle,
    this.errorMessage,
  });

  final String fileName;
  final AdminBookImportPhase phase;
  final int bytesSent;
  final int totalBytes;
  final String? importedTitle;
  final String? errorMessage;

  bool get isTerminal =>
      phase == AdminBookImportPhase.completed ||
      phase == AdminBookImportPhase.failed;

  double? get uploadFraction {
    if (totalBytes <= 0) return null;
    return (bytesSent / totalBytes).clamp(0.0, 1.0);
  }

  int? get uploadPercentage {
    final fraction = uploadFraction;
    return fraction == null ? null : (fraction * 100).round();
  }
}

class AdminCenterController extends ChangeNotifier {
  AdminCenterController({
    required AuthController authController,
    required ApiClient apiClient,
  }) : _authController = authController,
       _apiClient = apiClient {
    _authController.addListener(_handleAuthChanged);
    _handleAuthChanged();
  }

  static const String allBookGroupsLabel = '全部分组';

  final AuthController _authController;
  final ApiClient _apiClient;

  AdminSection _selectedSection = AdminSection.books;
  List<AdminUserView> _users = const [];
  List<AdminUserView> _grantableUsers = const [];
  List<AdminBookSummary> _books = const [];
  List<AdminAnnotationView> _annotations = const [];
  List<AdminBookmarkView> _bookmarks = const [];
  List<AdminLibrarySourceView> _librarySources = const [];
  List<AdminImportJobView> _importJobs = const [];
  Map<int, List<BookViewerView>> _bookViewers = const {};
  Map<int, AdminBookDetail> _bookDetails = const {};
  Set<int> _loadingViewerBookIds = <int>{};
  Set<int> _loadingBookDetailIds = <int>{};
  Set<int> _rebuildingBookIds = <int>{};
  Set<int> _selectedBookIds = <int>{};
  String _bookSearchQuery = '';
  String _selectedBookGroup = allBookGroupsLabel;
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  String? _notice;
  String? _workingMessage;
  AdminBookImportProgress? _bookImportProgress;

  AdminSection get selectedSection => _selectedSection;
  List<AdminUserView> get users => _users;
  List<AdminUserView> get grantableUsers => _grantableUsers;
  List<AdminBookSummary> get books => _books;
  List<AdminAnnotationView> get annotations => _annotations;
  List<AdminBookmarkView> get bookmarks => _bookmarks;
  List<AdminLibrarySourceView> get librarySources => _librarySources;
  List<AdminImportJobView> get importJobs => _importJobs;
  bool get isLoading => _isLoading;
  bool get isWorking => _isWorking;
  bool isRebuildingBook(int bookId) => _rebuildingBookIds.contains(bookId);
  String? get error => _error;
  String? get notice => _notice;
  String? get workingMessage => _workingMessage;
  AdminBookImportProgress? get bookImportProgress => _bookImportProgress;
  String get bookSearchQuery => _bookSearchQuery;
  String get selectedBookGroup => _selectedBookGroup;
  Set<int> get selectedBookIds => _selectedBookIds;
  bool get canAccessAdmin => _authController.user?.canAccessAdmin ?? false;
  bool get canManageUsers => _authController.user?.canManageAdminUsers ?? false;
  bool get canAssignBooks => canAccessAdmin;
  bool isCurrentUser(AdminUserView user) => _authController.user?.id == user.id;

  List<AdminSection> get availableSections => [
    if (canManageUsers) ...[AdminSection.users, AdminSection.roles],
    AdminSection.books,
    AdminSection.annotations,
    AdminSection.librarySources,
  ];

  int get bookCount => _books.length;
  int get annotationCount => _annotations.length;
  int get librarySourceCount => _librarySources.length;
  int get importJobCount => _importJobs.length;
  int get activeUserCount => _users.where((user) => user.enabled).length;
  int get enabledSuperAdminCount => _users
      .where(
        (user) =>
            user.enabled &&
            UserRole.fromValue(user.role) == UserRole.superAdmin,
      )
      .length;
  int get selectedBookCount => _selectedBookIds.length;
  bool get hasBookSelection => _selectedBookIds.isNotEmpty;

  List<String> get availableBookGroups {
    final groups =
        _books
            .map((book) => book.groupName?.trim())
            .whereType<String>()
            .where((group) => group.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [allBookGroupsLabel, ...groups];
  }

  List<AdminBookSummary> get filteredBooks {
    final normalizedQuery = _bookSearchQuery.trim().toLowerCase();
    return _books.where((book) {
      final groupMatches =
          _selectedBookGroup == allBookGroupsLabel ||
          (book.groupName?.trim() ?? '') == _selectedBookGroup;
      if (!groupMatches) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final haystacks = [
        book.title,
        book.author ?? '',
        book.groupName ?? '',
      ].map((value) => value.toLowerCase());
      return haystacks.any((value) => value.contains(normalizedQuery));
    }).toList();
  }

  bool get areAllVisibleBooksSelected {
    final visibleIds = filteredBooks.map((book) => book.id).toSet();
    if (visibleIds.isEmpty) {
      return false;
    }
    return visibleIds.every(_selectedBookIds.contains);
  }

  List<AdminRoleSummary> get roleSummaries {
    return adminRoles
        .map(
          (role) => AdminRoleSummary(
            role: role.value,
            label: role.label,
            description: role.description,
            userCount: _users.where((user) => user.role == role.value).length,
          ),
        )
        .toList();
  }

  Future<void> refresh() async {
    if (!canAccessAdmin) {
      _clear();
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait<dynamic>([
        _authController.runAuthorized(
          (token) => _apiClient.listAdminBooks(token),
        ),
        _authController.runAuthorized(
          (token) => _apiClient.listAdminAnnotations(token),
        ),
        _authController.runAuthorized(
          (token) => _apiClient.listGrantableUsers(token),
        ),
        _authController.runAuthorized(
          (token) => _apiClient.listLibrarySources(token),
        ),
        _authController.runAuthorized(
          (token) => _apiClient.listImportJobs(token),
        ),
        if (canManageUsers)
          _authController.runAuthorized((token) => _apiClient.listUsers(token)),
      ]);

      _books = results[0] as List<AdminBookSummary>;
      _annotations = results[1] as List<AdminAnnotationView>;
      _grantableUsers = results[2] as List<AdminUserView>;
      _librarySources = results[3] as List<AdminLibrarySourceView>;
      _importJobs = results[4] as List<AdminImportJobView>;
      _users = canManageUsers
          ? results[5] as List<AdminUserView>
          : const <AdminUserView>[];
      _bookmarks = const [];
      _bookViewers = const {};
      _bookDetails = const {};
      _loadingViewerBookIds = <int>{};
      _loadingBookDetailIds = <int>{};
      _selectedBookIds = _selectedBookIds
          .where((bookId) => _books.any((book) => book.id == bookId))
          .toSet();
      if (!availableBookGroups.contains(_selectedBookGroup)) {
        _selectedBookGroup = allBookGroupsLabel;
      }
      _ensureValidSection();
    } catch (error) {
      _error = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSection(AdminSection section) {
    if (!availableSections.contains(section)) {
      return;
    }
    _selectedSection = section;
    notifyListeners();
  }

  void setBookSearchQuery(String value) {
    if (_bookSearchQuery == value) {
      return;
    }
    _bookSearchQuery = value;
    notifyListeners();
  }

  void setBookGroupFilter(String value) {
    if (_selectedBookGroup == value) {
      return;
    }
    _selectedBookGroup = value;
    notifyListeners();
  }

  void toggleBookSelection(int bookId) {
    final next = {..._selectedBookIds};
    if (!next.add(bookId)) {
      next.remove(bookId);
    }
    _selectedBookIds = next;
    notifyListeners();
  }

  void toggleSelectAllVisibleBooks() {
    final visibleIds = filteredBooks.map((book) => book.id).toSet();
    if (visibleIds.isEmpty) {
      return;
    }
    final next = {..._selectedBookIds};
    if (visibleIds.every(next.contains)) {
      next.removeAll(visibleIds);
    } else {
      next.addAll(visibleIds);
    }
    _selectedBookIds = next;
    notifyListeners();
  }

  void clearSelectedBooks() {
    if (_selectedBookIds.isEmpty) {
      return;
    }
    _selectedBookIds = <int>{};
    notifyListeners();
  }

  Future<void> createUser({
    required String username,
    required String password,
    required String role,
  }) async {
    if (!canManageUsers) {
      return;
    }

    await _runMutation(() async {
      final created = await _authController.runAuthorized(
        (token) => _apiClient.createUser(
          token,
          username: username,
          password: password,
          role: role,
        ),
      );
      _users = [..._users, created]
        ..sort((left, right) => left.id.compareTo(right.id));
      _notice = '已创建用户 ${created.username}';
    });
  }

  Future<void> uploadBook({
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    int? fileSize,
  }) async {
    final sizeLabel = fileSize == null ? null : _formatFileSize(fileSize);
    final resolvedFileName = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : '所选图书';
    _bookImportProgress = AdminBookImportProgress(
      fileName: resolvedFileName,
      phase: AdminBookImportPhase.uploading,
      bytesSent: 0,
      totalBytes: fileSize ?? 0,
    );
    _workingMessage = sizeLabel == null
        ? '正在上传并解析图书，请勿关闭窗口'
        : '正在上传 $sizeLabel，上传后还需要解析，请勿关闭窗口';
    _isWorking = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final uploaded = await _authController.runAuthorized(
        (token) => _apiClient.uploadAdminBook(
          token,
          filePath: filePath,
          fileBytes: fileBytes,
          fileName: fileName,
          onSendProgress: _handleBookUploadProgress,
        ),
      );
      _bookImportProgress = AdminBookImportProgress(
        fileName: resolvedFileName,
        phase: AdminBookImportPhase.refreshing,
        bytesSent: _bookImportProgress?.bytesSent ?? fileSize ?? 0,
        totalBytes: _bookImportProgress?.totalBytes ?? fileSize ?? 0,
        importedTitle: uploaded.title,
      );
      _workingMessage = '图书已导入，正在更新书库';
      notifyListeners();
      await refresh();
      _notice = '已导入《${uploaded.title}》';
      _selectedSection = AdminSection.books;
      _bookImportProgress = AdminBookImportProgress(
        fileName: resolvedFileName,
        phase: AdminBookImportPhase.completed,
        bytesSent: _bookImportProgress?.bytesSent ?? fileSize ?? 0,
        totalBytes: _bookImportProgress?.totalBytes ?? fileSize ?? 0,
        importedTitle: uploaded.title,
      );
    } catch (error) {
      _error = error.toString();
      _bookImportProgress = AdminBookImportProgress(
        fileName: resolvedFileName,
        phase: AdminBookImportPhase.failed,
        bytesSent: _bookImportProgress?.bytesSent ?? 0,
        totalBytes: _bookImportProgress?.totalBytes ?? fileSize ?? 0,
        errorMessage: error.toString(),
      );
    } finally {
      _isWorking = false;
      _workingMessage = null;
      notifyListeners();
    }
  }

  void dismissBookImportProgress() {
    if (!(_bookImportProgress?.isTerminal ?? false)) return;
    _bookImportProgress = null;
    notifyListeners();
  }

  void _handleBookUploadProgress(int sent, int total) {
    final current = _bookImportProgress;
    if (current == null || current.isTerminal) return;
    final resolvedTotal = total > 0 ? total : current.totalBytes;
    final nextPhase = resolvedTotal > 0 && sent >= resolvedTotal
        ? AdminBookImportPhase.processing
        : AdminBookImportPhase.uploading;
    final next = AdminBookImportProgress(
      fileName: current.fileName,
      phase: nextPhase,
      bytesSent: sent,
      totalBytes: resolvedTotal,
    );
    if (current.phase == next.phase &&
        current.uploadPercentage == next.uploadPercentage) {
      return;
    }
    _bookImportProgress = next;
    _workingMessage = nextPhase == AdminBookImportPhase.processing
        ? '上传完成，服务器正在解析图书'
        : '正在上传图书 ${next.uploadPercentage ?? 0}%';
    notifyListeners();
  }

  String _formatFileSize(int bytes) {
    const megabyte = 1024 * 1024;
    if (bytes >= megabyte) {
      return '${(bytes / megabyte).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Future<void> createLibrarySource({
    required String name,
    required String sourceType,
    String? rootPath,
    String? baseUrl,
    String? remotePath,
    String? username,
    String? password,
    required bool enabled,
    required int scanIntervalMinutes,
  }) async {
    await _runMutation(() async {
      final created = await _authController.runAuthorized(
        (token) => _apiClient.createLibrarySource(
          token,
          name: name,
          sourceType: sourceType,
          rootPath: rootPath,
          baseUrl: baseUrl,
          remotePath: remotePath,
          username: username,
          password: password,
          enabled: enabled,
          scanIntervalMinutes: scanIntervalMinutes,
        ),
      );
      _librarySources = [..._librarySources, created]
        ..sort((left, right) => left.id.compareTo(right.id));
      _selectedSection = AdminSection.librarySources;
      _notice = '已新增扫描源 ${created.name}';
    });
  }

  Future<void> updateLibrarySource({
    required int sourceId,
    required String name,
    required String sourceType,
    String? rootPath,
    String? baseUrl,
    String? remotePath,
    String? username,
    String? password,
    required bool enabled,
    required int scanIntervalMinutes,
  }) async {
    await _runMutation(() async {
      final updated = await _authController.runAuthorized(
        (token) => _apiClient.updateLibrarySource(
          token,
          sourceId,
          name: name,
          sourceType: sourceType,
          rootPath: rootPath,
          baseUrl: baseUrl,
          remotePath: remotePath,
          username: username,
          password: password,
          enabled: enabled,
          scanIntervalMinutes: scanIntervalMinutes,
        ),
      );
      _librarySources =
          _librarySources
              .map((item) => item.id == updated.id ? updated : item)
              .toList()
            ..sort((left, right) => left.id.compareTo(right.id));
      _notice = '已更新扫描源 ${updated.name}';
    });
  }

  Future<void> toggleLibrarySourceEnabled(
    AdminLibrarySourceView source,
    bool enabled,
  ) async {
    await updateLibrarySource(
      sourceId: source.id,
      name: source.name,
      sourceType: source.sourceType,
      rootPath: source.rootPath,
      baseUrl: source.baseUrl,
      remotePath: source.remotePath,
      username: source.username,
      password: source.password,
      enabled: enabled,
      scanIntervalMinutes: source.scanIntervalMinutes,
    );
  }

  Future<void> rescanLibrarySource(AdminLibrarySourceView source) async {
    await _runMutation(() async {
      final result = await _authController.runAuthorized(
        (token) => _apiClient.rescanLibrarySource(token, source.id),
      );
      await refresh();
      final imported = (result['imported'] as num?)?.toInt() ?? 0;
      final missingMarked = (result['missingMarked'] as num?)?.toInt() ?? 0;
      _selectedSection = AdminSection.librarySources;
      _notice = '${source.name} 扫描完成，导入 $imported 本，标记缺失 $missingMarked 本';
    });
  }

  Future<void> scanClientLibrarySource(
    AdminLibrarySourceView source,
    PickedLocalLibraryFolder folder,
    LocalLibraryFileReader fileReader,
  ) async {
    await _runMutation(() async {
      try {
        _workingMessage = '正在比较 ${folder.files.length} 个本地文件摘要';
        notifyListeners();
        final plan = await _authController.runAuthorized(
          (token) => _apiClient.planClientLibraryScan(
            token,
            source.id,
            folder.files.map((file) => file.toJson()).toList(),
          ),
        );
        final filesByPath = {
          for (final file in folder.files) file.relativePath: file,
        };
        var uploaded = 0;
        for (final relativePath in plan.uploadPaths) {
          final file = filesByPath[relativePath];
          if (file == null) {
            throw StateError('扫描计划包含本地目录中不存在的文件：$relativePath');
          }
          _workingMessage =
              '正在上传 ${uploaded + 1}/${plan.uploadPaths.length} · ${file.fileName}';
          notifyListeners();
          if (file.sizeBytes <= 0) {
            throw StateError('无法上传空文件：${file.relativePath}');
          }
          var offsetBytes = 0;
          while (offsetBytes < file.sizeBytes) {
            final remainingBytes = file.sizeBytes - offsetBytes;
            final chunkLength =
                remainingBytes < localLibraryUploadChunkSizeBytes
                ? remainingBytes
                : localLibraryUploadChunkSizeBytes;
            final chunkEndBytes = offsetBytes + chunkLength;
            final chunk = await fileReader.readFileChunk(
              file,
              offsetBytes: offsetBytes,
              lengthBytes: chunkLength,
            );
            if (chunk.length != chunkLength) {
              throw StateError('读取文件分块失败：${file.relativePath}');
            }
            final chunkOffsetBytes = offsetBytes;
            await _authController.runAuthorized(
              (token) => _apiClient.uploadClientLibraryFileChunk(
                token,
                source.id,
                relativePath: file.relativePath,
                fileName: file.fileName,
                sizeBytes: file.sizeBytes,
                lastModifiedMillis: file.lastModifiedMillis,
                offsetBytes: chunkOffsetBytes,
                bytes: chunk,
                onSendProgress: (sent, total) {
                  final sentForFile = chunkOffsetBytes + sent;
                  final percentage = (sentForFile * 100 ~/ file.sizeBytes)
                      .clamp(0, 100);
                  _workingMessage =
                      sent >= total && chunkEndBytes == file.sizeBytes
                      ? '正在解析 ${uploaded + 1}/${plan.uploadPaths.length} · ${file.fileName}'
                      : '正在上传 ${uploaded + 1}/${plan.uploadPaths.length} · '
                            '${file.fileName} · $percentage%';
                  notifyListeners();
                },
              ),
            );
            offsetBytes = chunkEndBytes;
          }
          uploaded += 1;
        }
        await refresh();
        _selectedSection = AdminSection.librarySources;
        _notice =
            '${source.name} 扫描完成，上传 $uploaded 本，'
            '跳过 ${plan.unchanged} 本，标记缺失 ${plan.missingMarked} 本';
      } finally {
        _workingMessage = null;
      }
    });
  }

  Future<void> deleteLibrarySource(AdminLibrarySourceView source) async {
    await _runMutation(() async {
      await _authController.runAuthorized(
        (token) => _apiClient.deleteLibrarySource(token, source.id),
      );
      _librarySources = _librarySources
          .where((item) => item.id != source.id)
          .toList();
      _importJobs = _importJobs
          .map(
            (job) => job.sourceId == source.id
                ? AdminImportJobView(
                    id: job.id,
                    bookId: job.bookId,
                    bookTitle: job.bookTitle,
                    sourceId: null,
                    sourceName: null,
                    fileId: job.fileId,
                    status: job.status,
                    message: job.message,
                    createdAt: job.createdAt,
                    updatedAt: job.updatedAt,
                  )
                : job,
          )
          .toList();
      _selectedSection = AdminSection.librarySources;
      _notice = '已删除同步任务 ${source.name}，已导入图书仍保留在书库中';
    });
  }

  List<BookViewerView> viewersForBook(int bookId) =>
      _bookViewers[bookId] ?? const [];

  AdminBookDetail? bookDetailFor(int bookId) => _bookDetails[bookId];

  bool isLoadingViewers(int bookId) => _loadingViewerBookIds.contains(bookId);

  bool isLoadingBookDetail(int bookId) =>
      _loadingBookDetailIds.contains(bookId);

  Future<void> loadBookViewers(int bookId, {bool force = false}) async {
    if (!canAccessAdmin) {
      return;
    }
    if (!force && _bookViewers.containsKey(bookId)) {
      return;
    }
    if (_loadingViewerBookIds.contains(bookId)) {
      return;
    }

    _loadingViewerBookIds = {..._loadingViewerBookIds, bookId};
    notifyListeners();
    try {
      final viewers = await _authController.runAuthorized(
        (token) => _apiClient.listBookViewers(token, bookId),
      );
      _bookViewers = {..._bookViewers, bookId: viewers};
    } catch (error) {
      _error = error.toString();
    } finally {
      _loadingViewerBookIds = {..._loadingViewerBookIds}..remove(bookId);
      notifyListeners();
    }
  }

  Future<void> loadBookDetail(int bookId, {bool force = false}) async {
    if (!canAccessAdmin) {
      return;
    }
    if (!force && _bookDetails.containsKey(bookId)) {
      return;
    }
    if (_loadingBookDetailIds.contains(bookId)) {
      return;
    }

    _loadingBookDetailIds = {..._loadingBookDetailIds, bookId};
    notifyListeners();
    try {
      final detail = await _authController.runAuthorized(
        (token) => _apiClient.getAdminBook(token, bookId),
      );
      _bookDetails = {..._bookDetails, bookId: detail};
    } catch (error) {
      _error = error.toString();
    } finally {
      _loadingBookDetailIds = {..._loadingBookDetailIds}..remove(bookId);
      notifyListeners();
    }
  }

  Future<void> grantBookToUser(int bookId, int userId) async {
    if (!canAssignBooks) {
      return;
    }

    await _runMutation(() async {
      await _authController.runAuthorized(
        (token) => _apiClient.grantBook(token, bookId, userId: userId),
      );
      await loadBookViewers(bookId, force: true);
      final user = _grantableUsers.firstWhere(
        (item) => item.id == userId,
        orElse: () => AdminUserView(
          id: 0,
          username: '未知用户',
          role: UserRole.reader.value,
          enabled: true,
        ),
      );
      _notice = '已将书籍分配给 ${user.username}';
    });
  }

  Future<void> revokeBookFromUser(int bookId, BookViewerView viewer) async {
    if (!viewer.isExplicitGrant) {
      return;
    }

    await _runMutation(() async {
      await _authController.runAuthorized(
        (token) => _apiClient.revokeBookGrant(token, bookId, viewer.userId),
      );
      await loadBookViewers(bookId, force: true);
      _notice = '已移除 ${viewer.username} 的图书访问权限';
    });
  }

  Future<void> updateBookGroup(int bookId, String? groupName) async {
    await _runMutation(() async {
      final updated = await _authController.runAuthorized(
        (token) => _apiClient.updateAdminBook(
          token,
          bookId,
          groupName: groupName?.trim().isEmpty == true
              ? null
              : groupName?.trim(),
        ),
      );
      _bookDetails = {..._bookDetails, bookId: updated};
      _books = _books
          .map(
            (book) => book.id == bookId
                ? book.copyWith(
                    groupName: updated.groupName,
                    clearGroupName: updated.groupName == null,
                    updatedAt: updated.updatedAt,
                  )
                : book,
          )
          .toList();
      _notice = updated.groupName == null || updated.groupName!.isEmpty
          ? '已清空图书分组'
          : '已将图书分组更新为 ${updated.groupName}';
    });
  }

  Future<void> updateBookMetadata(
    int bookId,
    String title,
    String? author,
  ) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      _error = '书名不能为空';
      notifyListeners();
      return;
    }

    await _runMutation(() async {
      final normalizedAuthor = author?.trim();
      final updated = await _authController.runAuthorized(
        (token) => _apiClient.updateAdminBookMetadata(
          token,
          bookId,
          title: normalizedTitle,
          author: normalizedAuthor?.isEmpty == true ? null : normalizedAuthor,
        ),
      );
      _bookDetails = {..._bookDetails, bookId: updated};
      _books = _books
          .map(
            (book) => book.id == bookId
                ? book.copyWith(
                    title: updated.title,
                    author: updated.author,
                    clearAuthor: updated.author == null,
                    updatedAt: updated.updatedAt,
                  )
                : book,
          )
          .toList();
      _notice = '已更新《${updated.title}》的书籍信息';
    });
  }

  Future<void> rebuildStructuredContent(int bookId) async {
    if (_rebuildingBookIds.contains(bookId)) {
      return;
    }

    _rebuildingBookIds = {..._rebuildingBookIds, bookId};
    notifyListeners();
    try {
      await _runMutation(() async {
        final updated = await _authController.runAuthorized(
          (token) => _apiClient.rebuildAdminBookContent(token, bookId),
        );
        _bookDetails = {..._bookDetails, bookId: updated};
        _books = _books
            .map(
              (book) => book.id == bookId
                  ? book.copyWith(updatedAt: updated.updatedAt)
                  : book,
            )
            .toList();
        _notice = '已重新生成《${updated.title}》的结构化正文';
      });
    } finally {
      _rebuildingBookIds = Set<int>.from(_rebuildingBookIds)..remove(bookId);
      notifyListeners();
    }
  }

  Future<void> deleteSelectedBooks() async {
    final targetIds = _selectedBookIds.toList()..sort();
    if (targetIds.isEmpty) {
      return;
    }

    await _runMutation(() async {
      final deletedCount = await _authController.runAuthorized(
        (token) => _apiClient.bulkDeleteAdminBooks(token, targetIds),
      );
      final idSet = targetIds.toSet();
      _books = _books.where((book) => !idSet.contains(book.id)).toList();
      _bookDetails = Map<int, AdminBookDetail>.from(_bookDetails)
        ..removeWhere((bookId, _) => idSet.contains(bookId));
      _bookViewers = Map<int, List<BookViewerView>>.from(_bookViewers)
        ..removeWhere((bookId, _) => idSet.contains(bookId));
      _selectedBookIds = <int>{};
      _notice = '已删除 $deletedCount 本图书';
    });
  }

  Future<void> updateUserRole(AdminUserView user, String role) async {
    if (!canManageUsers || isCurrentUser(user) || role == user.role) {
      return;
    }

    final previousUsers = _users;
    _users = _users
        .map((item) => item.id == user.id ? item.copyWith(role: role) : item)
        .toList();
    notifyListeners();

    try {
      final updated = await _authController.runAuthorized(
        (token) => _apiClient.updateUser(token, user.id, role: role),
      );
      _replaceUser(updated);
      _notice = '已更新 ${updated.username} 的角色';
    } catch (error) {
      _users = previousUsers;
      _error = error.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> updateUserEnabled(AdminUserView user, bool enabled) async {
    if (!canManageUsers || enabled == user.enabled) {
      return;
    }

    if (!enabled && UserRole.fromValue(user.role) == UserRole.superAdmin) {
      if (!isCurrentUser(user)) {
        _error = '管理员只能停用自己的账号';
        notifyListeners();
        return;
      }
      if (enabledSuperAdminCount <= 1) {
        _error = '系统中至少需要保留一个启用的管理员账号';
        notifyListeners();
        return;
      }
    }

    final previousUsers = _users;
    _users = _users
        .map(
          (item) => item.id == user.id ? item.copyWith(enabled: enabled) : item,
        )
        .toList();
    notifyListeners();

    try {
      final updated = await _authController.runAuthorized(
        (token) => _apiClient.updateUser(token, user.id, enabled: enabled),
      );
      _replaceUser(updated);
      _notice = enabled ? '已启用 ${updated.username}' : '已停用 ${updated.username}';
    } catch (error) {
      _users = previousUsers;
      _error = error.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> resetUserPassword(AdminUserView user, String newPassword) async {
    if (!canManageUsers ||
        UserRole.fromValue(user.role) == UserRole.superAdmin) {
      return;
    }

    await _runMutation(() async {
      await _authController.runAuthorized(
        (token) => _apiClient.resetUserPassword(
          token,
          user.id,
          newPassword: newPassword,
        ),
      );
      _notice = '已修改 ${user.username} 的密码';
    });
  }

  Future<void> updateAnnotationDeleted(
    AdminAnnotationView annotation,
    bool deleted,
  ) async {
    final previousAnnotations = _annotations;
    _annotations = _annotations
        .map(
          (item) =>
              item.id == annotation.id ? item.copyWith(deleted: deleted) : item,
        )
        .toList();
    notifyListeners();

    try {
      final updated = await _authController.runAuthorized(
        (token) => _apiClient.updateAdminAnnotationDeleted(
          token,
          annotation.id,
          deleted: deleted,
        ),
      );
      _replaceAnnotation(updated);
      _notice = deleted ? '已隐藏一条批注' : '已恢复一条批注';
    } catch (error) {
      _annotations = previousAnnotations;
      _error = error.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> updateBookmarkDeleted(
    AdminBookmarkView bookmark,
    bool deleted,
  ) async {
    final previousBookmarks = _bookmarks;
    _bookmarks = _bookmarks
        .map(
          (item) =>
              item.id == bookmark.id ? item.copyWith(deleted: deleted) : item,
        )
        .toList();
    notifyListeners();

    try {
      final updated = await _authController.runAuthorized(
        (token) => _apiClient.updateAdminBookmarkDeleted(
          token,
          bookmark.id,
          deleted: deleted,
        ),
      );
      _replaceBookmark(updated);
      _notice = deleted ? '已隐藏一条书签' : '已恢复一条书签';
    } catch (error) {
      _bookmarks = previousBookmarks;
      _error = error.toString();
    } finally {
      notifyListeners();
    }
  }

  void clearBanner() {
    _error = null;
    _notice = null;
    _workingMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (canAccessAdmin) {
      _ensureValidSection();
      unawaited(refresh());
      return;
    }

    _clear();
    notifyListeners();
  }

  void _ensureValidSection() {
    if (!availableSections.contains(_selectedSection)) {
      _selectedSection = availableSections.first;
    }
  }

  void _clear() {
    _users = const [];
    _grantableUsers = const [];
    _books = const [];
    _annotations = const [];
    _bookmarks = const [];
    _librarySources = const [];
    _importJobs = const [];
    _bookViewers = const {};
    _bookDetails = const {};
    _loadingViewerBookIds = <int>{};
    _loadingBookDetailIds = <int>{};
    _rebuildingBookIds = <int>{};
    _selectedBookIds = <int>{};
    _bookSearchQuery = '';
    _selectedBookGroup = allBookGroupsLabel;
    _error = null;
    _notice = null;
    _bookImportProgress = null;
    _isLoading = false;
    _isWorking = false;
    _selectedSection = AdminSection.books;
  }

  Future<void> _runMutation(Future<void> Function() action) async {
    _isWorking = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = error.toString();
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  void _replaceUser(AdminUserView updated) {
    _users =
        _users.map((item) => item.id == updated.id ? updated : item).toList()
          ..sort((left, right) => left.id.compareTo(right.id));
  }

  void _replaceAnnotation(AdminAnnotationView updated) {
    _annotations =
        _annotations
            .map((item) => item.id == updated.id ? updated : item)
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  void _replaceBookmark(AdminBookmarkView updated) {
    _bookmarks =
        _bookmarks
            .map((item) => item.id == updated.id ? updated : item)
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }
}
