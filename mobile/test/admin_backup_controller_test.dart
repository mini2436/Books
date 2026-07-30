import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/data/models/admin_models.dart';
import 'package:private_reader_mobile/data/models/auth_models.dart';
import 'package:private_reader_mobile/data/services/api_client.dart';
import 'package:private_reader_mobile/data/services/offline_book_cache_service.dart';
import 'package:private_reader_mobile/data/services/session_storage.dart';
import 'package:private_reader_mobile/features/admin/admin_center_controller.dart';
import 'package:private_reader_mobile/features/auth/auth_controller.dart';

void main() {
  test('backup entry follows resources and full restore signs out', () async {
    final apiClient = _BackupApiClient();
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

    expect(controller.availableSections.last, AdminSection.backups);
    expect(controller.backupSchedule?.frequency, 'WEEKLY');
    expect(controller.backupRecords, [_backupRecord]);
    expect(
      controller.availableSections.indexOf(AdminSection.backups),
      controller.availableSections.indexOf(AdminSection.librarySources) + 1,
    );
    expect(
      await controller.exportFullSystemBackup(),
      Uint8List.fromList([1, 2, 3]),
    );
    await controller.exportBackup(
      scope: 'FULL',
      userIds: const [99],
      bookIds: const [88],
      dataTypes: const ['ANNOTATIONS'],
    );
    expect(apiClient.exportUserIds, isEmpty);
    expect(apiClient.exportBookIds, isEmpty);
    expect(apiClient.exportDataTypes, isEmpty);

    expect(
      await controller.createBackupDownloadUrl(scope: 'FULL'),
      'http://server-1:8080/api/admin/backups/download/ticket',
    );
    controller.markBackupDownloadStarted();
    expect(controller.notice, '备份下载已启动，请在浏览器或系统下载列表中查看进度');
    expect(
      await controller.exportBackupToFile(
        destinationPath: 'C:/backup.zip',
        scope: 'FULL',
      ),
      isTrue,
    );
    expect(apiClient.downloadDestinationPath, 'C:/backup.zip');

    expect(
      await controller.updateBackupSchedule(
        enabled: true,
        frequency: 'MONTHLY',
      ),
      isTrue,
    );
    expect(controller.backupSchedule?.enabled, isTrue);
    expect(controller.backupSchedule?.frequency, 'MONTHLY');
    expect(await controller.deleteBackupRecord(_backupRecord.id), isTrue);
    expect(controller.backupRecords, isEmpty);

    final preview = await controller.previewSystemBackup(
      fileName: 'backup.zip',
      fileBytes: Uint8List.fromList([1]),
    );
    expect(preview?.isFull, isTrue);
    expect(preview?.books, 12);

    final restoreFuture = controller.restoreFullSystemBackup(
      fileName: 'backup.zip',
      fileBytes: Uint8List.fromList([1]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.backupOperation, AdminBackupOperation.restoring);
    expect(controller.backupOperation, isNot(AdminBackupOperation.exporting));
    apiClient.restoreResult.complete(_restoreResult);
    final restored = await restoreFuture;
    expect(restored, isTrue);
    expect(auth.isAuthenticated, isFalse);
    expect(apiClient.restoreCalled, isTrue);
  });

  test(
    'user data backup forwards selection and restore keeps session',
    () async {
      final apiClient = _BackupApiClient()..previewValue = _userDataPreview;
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

      await controller.exportBackup(
        scope: 'USER_DATA',
        userIds: const [11],
        bookIds: const [22],
        dataTypes: const ['ANNOTATIONS', 'READING_PROGRESS'],
      );
      expect(apiClient.exportScope, 'USER_DATA');
      expect(apiClient.exportUserIds, [11]);
      expect(apiClient.exportBookIds, [22]);

      final preview = await controller.previewBackup(
        fileName: 'user-data.zip',
        fileBytes: Uint8List.fromList([1]),
      );
      expect(preview?.isUserData, isTrue);
      final restoreFuture = controller.restoreBackup(
        fileName: 'user-data.zip',
        fileBytes: Uint8List.fromList([1]),
        restoreScope: 'USER_DATA',
        userMappings: const {11: 1},
        dataTypes: const ['ANNOTATIONS'],
        mode: 'REPLACE',
      );
      await Future<void>.delayed(Duration.zero);
      apiClient.restoreResult.complete(_userDataRestoreResult);
      expect(await restoreFuture, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(apiClient.restoreMappings, {11: 1});
      expect(apiClient.restoreScope, 'USER_DATA');
      expect(apiClient.restoreDataTypes, ['ANNOTATIONS']);
      expect(apiClient.restoreMode, 'REPLACE');
    },
  );
}

const _session = Session(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  user: AuthUser(
    id: 1,
    username: 'admin',
    displayName: null,
    role: 'SUPER_ADMIN',
    hasAvatar: false,
    avatarVersion: null,
  ),
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _BackupApiClient extends ApiClient {
  _BackupApiClient() : super(baseUrl: 'http://server-1:8080');

  bool restoreCalled = false;
  String? exportScope;
  String? downloadDestinationPath;
  List<int> exportUserIds = const [];
  List<int> exportBookIds = const [];
  List<String> exportDataTypes = const [];
  Map<int, int>? restoreMappings;
  String? restoreScope;
  List<String> restoreDataTypes = const [];
  String? restoreMode;
  bool scheduleEnabled = false;
  String scheduleFrequency = 'WEEKLY';
  AdminBackupPreview previewValue = _fullPreview;
  final Completer<AdminBackupRestoreResult> restoreResult =
      Completer<AdminBackupRestoreResult>();

  @override
  Future<Session> refresh(String refreshToken) async => _session;

  @override
  Future<void> logout(String accessToken) async {}

  @override
  Future<List<AdminBookSummary>> listAdminBooks(String accessToken) async =>
      const [];

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
  Future<List<AdminUserView>> listUsers(String accessToken) async => const [];

  @override
  Future<List<AdminBackupRecord>> listBackupRecords(String accessToken) async =>
      const [_backupRecord];

  @override
  Future<AdminBackupSchedule> getBackupSchedule(String accessToken) async =>
      _schedule(scheduleEnabled, scheduleFrequency);

  @override
  Future<AdminBackupSchedule> updateBackupSchedule(
    String accessToken, {
    required bool enabled,
    required String frequency,
  }) async {
    scheduleEnabled = enabled;
    scheduleFrequency = frequency;
    return _schedule(enabled, frequency);
  }

  @override
  Future<void> deleteBackupRecord(String accessToken, String recordId) async {}

  @override
  Future<Uint8List> exportBackup(
    String accessToken, {
    required String scope,
    List<int> userIds = const [],
    List<int> bookIds = const [],
    List<String> dataTypes = const [],
  }) async {
    exportScope = scope;
    exportUserIds = userIds;
    exportBookIds = bookIds;
    exportDataTypes = dataTypes;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<String> createBackupDownloadTicket(
    String accessToken, {
    required String scope,
    List<int> userIds = const [],
    List<int> bookIds = const [],
    List<String> dataTypes = const [],
  }) async => 'http://server-1:8080/api/admin/backups/download/ticket';

  @override
  Future<void> downloadBackupToFile(
    String accessToken, {
    required String destinationPath,
    required String scope,
    List<int> userIds = const [],
    List<int> bookIds = const [],
    List<String> dataTypes = const [],
    ProgressCallback? onReceiveProgress,
  }) async {
    downloadDestinationPath = destinationPath;
    onReceiveProgress?.call(3, 3);
  }

  @override
  Future<AdminBackupPreview> previewSystemBackup(
    String accessToken, {
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async => previewValue;

  @override
  Future<AdminBackupRestoreResult> restoreBackup(
    String accessToken, {
    required String operationId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
    required String restoreScope,
    Map<int, int>? userMappings,
    List<String> dataTypes = const [],
    String mode = 'MERGE',
    ProgressCallback? onSendProgress,
  }) async {
    restoreCalled = true;
    this.restoreScope = restoreScope;
    restoreMappings = userMappings;
    restoreDataTypes = dataTypes;
    restoreMode = mode;
    onSendProgress?.call(1, 1);
    return restoreResult.future;
  }
}

const _fullPreview = AdminBackupPreview(
  formatVersion: 1,
  scope: 'FULL',
  createdAt: '2026-07-29T00:00:00Z',
  sourceUsers: [],
  books: 12,
  annotations: 4,
  bookmarks: 3,
  histories: 2,
  progresses: 2,
);

const _userDataPreview = AdminBackupPreview(
  formatVersion: 2,
  scope: 'USER_DATA',
  createdAt: '2026-07-29T00:00:00Z',
  sourceUsers: [
    AdminBackupUserView(id: 11, username: 'source', displayName: 'Source'),
  ],
  books: 1,
  annotations: 4,
  bookmarks: 0,
  histories: 1,
  progresses: 1,
  dataTypes: ['ANNOTATIONS', 'READING_HISTORY', 'READING_PROGRESS'],
);

const _backupRecord = AdminBackupRecord(
  id: '7c505eec-5af2-4e16-aa34-a681a52afabc',
  scope: 'FULL',
  origin: 'MANUAL',
  filename: 'private-reader-full-20260730-120000.zip',
  sizeBytes: 1024,
  createdAt: '2026-07-30T12:00:00Z',
);

AdminBackupSchedule _schedule(bool enabled, String frequency) =>
    AdminBackupSchedule(
      enabled: enabled,
      frequency: frequency,
      lastRunAt: null,
      nextRunAt: enabled ? '2026-08-30T12:00:00Z' : null,
      updatedAt: '2026-07-30T12:00:00Z',
    );

const _restoreResult = AdminBackupRestoreResult(
  scope: 'FULL',
  restoredUsers: 1,
  restoredBooks: 12,
  annotations: 4,
  bookmarks: 3,
  histories: 2,
  progresses: 2,
  skippedBooks: 0,
);

const _userDataRestoreResult = AdminBackupRestoreResult(
  scope: 'USER_DATA',
  restoredUsers: 1,
  restoredBooks: 1,
  annotations: 4,
  bookmarks: 0,
  histories: 1,
  progresses: 1,
  skippedBooks: 0,
);

class _MemorySessionStorage extends SessionStorage {
  @override
  Future<Session?> readSession() async => _session;

  @override
  Future<void> saveSession(Session session) async {}

  @override
  Future<void> clear() async {}
}
