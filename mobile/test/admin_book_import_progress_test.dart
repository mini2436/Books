import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/admin_models.dart';
import 'package:private_reader_mobile/data/models/auth_models.dart';
import 'package:private_reader_mobile/data/models/book_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/session_storage.dart';
import 'package:private_reader_mobile/features/admin/admin_center_controller.dart';
import 'package:private_reader_mobile/features/auth/auth_controller.dart';

void main() {
  test(
    'book import reports upload, processing, refresh, and completion',
    () async {
      final apiClient = _ImportApiClient();
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

      final upload = controller.uploadBook(
        fileBytes: Uint8List(100),
        fileName: '测试.epub',
        fileSize: 100,
      );
      await _waitUntil(() => apiClient.uploadProgress != null);

      apiClient.uploadProgress!(50, 100);
      expect(
        controller.bookImportProgress?.phase,
        AdminBookImportPhase.uploading,
      );
      expect(controller.bookImportProgress?.uploadPercentage, 50);

      apiClient.uploadProgress!(100, 100);
      expect(
        controller.bookImportProgress?.phase,
        AdminBookImportPhase.processing,
      );

      apiClient.refreshGate = Completer<void>();
      apiClient.uploadResult.complete(_bookDetail);
      await _waitUntil(
        () =>
            controller.bookImportProgress?.phase ==
            AdminBookImportPhase.refreshing,
      );

      apiClient.refreshGate!.complete();
      await upload;
      expect(
        controller.bookImportProgress?.phase,
        AdminBookImportPhase.completed,
      );
      expect(controller.bookImportProgress?.importedTitle, '测试图书');
      expect(controller.notice, '已导入《测试图书》');

      controller.dismissBookImportProgress();
      expect(controller.bookImportProgress, isNull);
    },
  );
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

const _bookDetail = BookDetail(
  id: 11,
  title: '测试图书',
  author: null,
  groupName: null,
  description: null,
  pluginId: 'epub',
  format: 'epub',
  sourceMissing: false,
  updatedAt: '2026-07-28T00:00:00Z',
  sourceType: 'MANAGED_UPLOAD',
  manifest: null,
  capabilities: ['STRUCTURED_CONTENT'],
  hasStructuredContent: true,
  contentModel: 'CHAPTERS',
  latestContentVersionId: 1,
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _ImportApiClient extends ApiClient {
  _ImportApiClient() : super(baseUrl: 'http://server-1:8080');

  final Completer<BookDetail> uploadResult = Completer<BookDetail>();
  ProgressCallback? uploadProgress;
  Completer<void>? refreshGate;

  @override
  Future<Session> refresh(String refreshToken) async => _session;

  @override
  Future<List<AdminBookSummary>> listAdminBooks(String accessToken) async {
    await refreshGate?.future;
    return const [];
  }

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

  @override
  Future<BookDetail> uploadAdminBook(
    String accessToken, {
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    ProgressCallback? onSendProgress,
  }) {
    uploadProgress = onSendProgress;
    return uploadResult.future;
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
