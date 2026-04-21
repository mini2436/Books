import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/admin_models.dart';
import '../../data/services/api_client.dart';
import '../auth/auth_controller.dart';

final adminCenterControllerProvider = ChangeNotifierProvider<AdminCenterController>(
  (ref) {
    return AdminCenterController(
      authController: ref.read(authControllerProvider),
      apiClient: ref.watch(apiClientProvider),
    );
  },
);

enum AdminSection {
  users,
  roles,
  books,
  annotations,
  bookmarks,
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

  final AuthController _authController;
  final ApiClient _apiClient;

  AdminSection _selectedSection = AdminSection.books;
  List<AdminUserView> _users = const [];
  List<AdminUserView> _grantableUsers = const [];
  List<AdminBookSummary> _books = const [];
  List<AdminAnnotationView> _annotations = const [];
  List<AdminBookmarkView> _bookmarks = const [];
  Map<int, List<BookViewerView>> _bookViewers = const {};
  Set<int> _loadingViewerBookIds = <int>{};
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  String? _notice;

  AdminSection get selectedSection => _selectedSection;
  List<AdminUserView> get users => _users;
  List<AdminUserView> get grantableUsers => _grantableUsers;
  List<AdminBookSummary> get books => _books;
  List<AdminAnnotationView> get annotations => _annotations;
  List<AdminBookmarkView> get bookmarks => _bookmarks;
  bool get isLoading => _isLoading;
  bool get isWorking => _isWorking;
  String? get error => _error;
  String? get notice => _notice;
  bool get canAccessAdmin => _authController.user?.canAccessAdmin ?? false;
  bool get canManageUsers => _authController.user?.canManageAdminUsers ?? false;
  bool get canAssignBooks => canAccessAdmin;

  List<AdminSection> get availableSections => [
    if (canManageUsers) ...[
      AdminSection.users,
      AdminSection.roles,
    ],
    AdminSection.books,
    AdminSection.annotations,
    AdminSection.bookmarks,
  ];

  int get bookCount => _books.length;
  int get annotationCount => _annotations.length;
  int get bookmarkCount => _bookmarks.length;
  int get activeUserCount => _users.where((user) => user.enabled).length;

  List<AdminRoleSummary> get roleSummaries {
    return adminRoles
        .map(
          (role) => AdminRoleSummary(
            role: role,
            label: adminRoleLabel(role),
            description: adminRoleDescription(role),
            userCount: _users.where((user) => user.role == role).length,
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
        _authController.runAuthorized((token) => _apiClient.listAdminBooks(token)),
        _authController.runAuthorized(
          (token) => _apiClient.listAdminAnnotations(token),
        ),
        _authController.runAuthorized(
          (token) => _apiClient.listAdminBookmarks(token),
        ),
        _authController.runAuthorized(
          (token) => _apiClient.listGrantableUsers(token),
        ),
        if (canManageUsers)
          _authController.runAuthorized((token) => _apiClient.listUsers(token)),
      ]);

      _books = results[0] as List<AdminBookSummary>;
      _annotations = results[1] as List<AdminAnnotationView>;
      _bookmarks = results[2] as List<AdminBookmarkView>;
      _grantableUsers = results[3] as List<AdminUserView>;
      _users = canManageUsers
          ? results[4] as List<AdminUserView>
          : const <AdminUserView>[];
      _bookViewers = const {};
      _loadingViewerBookIds = <int>{};
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
      _users = [..._users, created]..sort((left, right) => left.id.compareTo(right.id));
      _notice = '已创建用户 ${created.username}';
    });
  }

  Future<void> uploadBook(String filePath) async {
    await _runMutation(() async {
      final uploaded = await _authController.runAuthorized(
        (token) => _apiClient.uploadAdminBook(token, filePath: filePath),
      );
      await refresh();
      _notice = '已导入《${uploaded.title}》';
      _selectedSection = AdminSection.books;
    });
  }

  List<BookViewerView> viewersForBook(int bookId) => _bookViewers[bookId] ?? const [];

  bool isLoadingViewers(int bookId) => _loadingViewerBookIds.contains(bookId);

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
      _bookViewers = {
        ..._bookViewers,
        bookId: viewers,
      };
    } catch (error) {
      _error = error.toString();
    } finally {
      _loadingViewerBookIds = {..._loadingViewerBookIds}..remove(bookId);
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
        orElse: () => const AdminUserView(
          id: 0,
          username: '未知用户',
          role: 'READER',
          enabled: true,
        ),
      );
      _notice = '已将书籍分配给 ${user.username}';
    });
  }

  Future<void> updateUserRole(AdminUserView user, String role) async {
    if (!canManageUsers || role == user.role) {
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

  Future<void> updateAnnotationDeleted(
    AdminAnnotationView annotation,
    bool deleted,
  ) async {
    final previousAnnotations = _annotations;
    _annotations = _annotations
        .map(
          (item) => item.id == annotation.id ? item.copyWith(deleted: deleted) : item,
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
        .map((item) => item.id == bookmark.id ? item.copyWith(deleted: deleted) : item)
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
    _bookViewers = const {};
    _loadingViewerBookIds = <int>{};
    _error = null;
    _notice = null;
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
    _users = _users
        .map((item) => item.id == updated.id ? updated : item)
        .toList()
      ..sort((left, right) => left.id.compareTo(right.id));
  }

  void _replaceAnnotation(AdminAnnotationView updated) {
    _annotations = _annotations
        .map((item) => item.id == updated.id ? updated : item)
        .toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  void _replaceBookmark(AdminBookmarkView updated) {
    _bookmarks = _bookmarks
        .map((item) => item.id == updated.id ? updated : item)
        .toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }
}
