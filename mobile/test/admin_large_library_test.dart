import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/admin_models.dart';
import 'package:private_reader_mobile/data/models/auth_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/session_storage.dart';
import 'package:private_reader_mobile/features/admin/admin_center_controller.dart';
import 'package:private_reader_mobile/features/auth/auth_controller.dart';

void main() {
  test('千本管理书籍复用派生缓存并延迟执行搜索', () async {
    final apiClient = _LargeAdminLibraryApiClient();
    final auth = AuthController(
      apiClient: apiClient,
      sessionStorage: _MemorySessionStorage(),
      offlineBookCacheService: OfflineBookCacheService(),
    );
    await _waitUntil(() => !auth.isBootstrapping && auth.isAuthenticated);
    final controller = AdminCenterController(
      authController: auth,
      apiClient: apiClient,
    );
    addTearDown(() {
      controller.dispose();
      auth.dispose();
    });

    await _waitUntil(() => !controller.isLoading);
    expect(controller.books, hasLength(1000));
    expect(controller.availableBookGroups, hasLength(11));
    expect(controller.filteredBooks, hasLength(1000));
    expect(
      identical(controller.availableBookGroups, controller.availableBookGroups),
      isTrue,
    );
    expect(
      identical(controller.filteredBooks, controller.filteredBooks),
      isTrue,
    );

    controller.setBookSearchQuery('作者 999');
    expect(controller.filteredBooks, hasLength(1000));
    await _waitUntil(() => controller.filteredBooks.length == 1);
    expect(controller.filteredBooks.single.id, 999);

    controller.setBookSearchQuery('');
    await _waitUntil(() => controller.filteredBooks.length == 1000);
    controller.setBookGroupFilter('分组 3');
    expect(controller.filteredBooks, hasLength(100));

    controller.toggleSelectAllVisibleBooks();
    expect(controller.selectedBookCount, 100);
    expect(controller.areAllVisibleBooksSelected, isTrue);
    controller.toggleSelectAllVisibleBooks();
    expect(controller.selectedBookCount, 0);
  });

  test('管理页可批量授权并批量编组已选书籍', () async {
    final apiClient = _BulkAdminBookApiClient();
    final auth = AuthController(
      apiClient: apiClient,
      sessionStorage: _MemorySessionStorage(),
      offlineBookCacheService: OfflineBookCacheService(),
    );
    await _waitUntil(() => !auth.isBootstrapping && auth.isAuthenticated);
    final controller = AdminCenterController(
      authController: auth,
      apiClient: apiClient,
    );
    addTearDown(() {
      controller.dispose();
      auth.dispose();
    });
    await _waitUntil(() => !controller.isLoading);

    controller.toggleBookSelection(1);
    controller.toggleBookSelection(2);
    await controller.grantSelectedBooks(12);
    expect(apiClient.grantedBookIds, [1, 2]);
    expect(apiClient.grantedUserId, 12);
    expect(controller.selectedBookCount, 0);

    controller.toggleBookSelection(1);
    controller.toggleBookSelection(2);
    await controller.groupSelectedBooks('科幻');
    expect(apiClient.groupedBookIds, [1, 2]);
    expect(apiClient.groupName, '科幻');
    expect(controller.books.every((book) => book.groupName == '科幻'), isTrue);
    expect(controller.selectedBookCount, 0);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

const _session = Session(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  user: AuthUser(
    id: 7,
    username: 'librarian',
    displayName: null,
    role: 'LIBRARIAN',
    hasAvatar: false,
    avatarVersion: null,
  ),
);

class _LargeAdminLibraryApiClient extends ApiClient {
  _LargeAdminLibraryApiClient() : super(baseUrl: 'http://server-1:8080');

  @override
  Future<Session> refresh(String refreshToken) async => _session;

  @override
  Future<List<AdminBookSummary>> listAdminBooks(String accessToken) async =>
      List.generate(1000, (index) {
        final id = index + 1;
        return AdminBookSummary(
          id: id,
          title: '图书 $id',
          author: '作者 $id',
          groupName: '分组 ${id % 10}',
          description: null,
          pluginId: 'epub',
          format: 'EPUB',
          sourceType: 'UPLOAD',
          sourceMissing: false,
          updatedAt: '2026-08-01T00:00:00Z',
        );
      }, growable: false);

  @override
  Future<List<AdminAnnotationView>> listAdminAnnotations(
    String accessToken,
  ) async => const [];

  @override
  Future<List<AdminUserView>> listGrantableUsers(String accessToken) async =>
      const [];

  @override
  Future<List<AdminLibrarySourceView>> listLibrarySources(
    String accessToken,
  ) async => const [];

  @override
  Future<List<AdminImportJobView>> listImportJobs(String accessToken) async =>
      const [];
}

class _BulkAdminBookApiClient extends _LargeAdminLibraryApiClient {
  List<int> grantedBookIds = const [];
  int? grantedUserId;
  List<int> groupedBookIds = const [];
  String? groupName;

  @override
  Future<List<AdminBookSummary>> listAdminBooks(String accessToken) async =>
      List.generate(
        2,
        (index) => AdminBookSummary(
          id: index + 1,
          title: '图书 ${index + 1}',
          author: null,
          groupName: null,
          description: null,
          pluginId: 'epub',
          format: 'EPUB',
          sourceType: 'UPLOAD',
          sourceMissing: false,
          updatedAt: '2026-08-01T00:00:00Z',
        ),
      );

  @override
  Future<List<AdminUserView>> listGrantableUsers(String accessToken) async => [
    const AdminUserView(
      id: 12,
      username: 'reader',
      role: 'READER',
      enabled: true,
    ),
  ];

  @override
  Future<int> bulkGrantAdminBooks(
    String accessToken,
    List<int> bookIds, {
    required int userId,
  }) async {
    grantedBookIds = List.of(bookIds);
    grantedUserId = userId;
    return bookIds.length;
  }

  @override
  Future<int> bulkUpdateAdminBookGroups(
    String accessToken,
    List<int> bookIds, {
    String? groupName,
  }) async {
    groupedBookIds = List.of(bookIds);
    this.groupName = groupName;
    return bookIds.length;
  }
}

class _MemorySessionStorage extends SessionStorage {
  @override
  Future<Session?> readSession() async => _session;

  @override
  Future<void> saveSession(Session session) async {}

  @override
  Future<void> clear() async {}
}
