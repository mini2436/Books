import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

import '../models/admin_models.dart';
import '../../shared/config/app_config.dart';
import '../models/auth_models.dart';
import '../models/book_models.dart';
import '../models/sync_models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isAuthenticationFailure => statusCode == 401 || statusCode == 403;
  bool get isNetworkFailure => statusCode == null || statusCode! >= 500;

  /// Converts unexpected local errors into a safe message for the UI.
  /// Network responses are normalized before becoming an [ApiException], so
  /// callers must never surface `error.toString()` directly.
  static String userFacingMessage(
    Object error, {
    String fallback = '操作未完成，请稍后重试。',
  }) => error is ApiException ? error.message : fallback;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl ?? AppConfig.defaultApiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;

  void updateBaseUrl(String value) {
    _dio.options.baseUrl = AppConfig.normalizeBaseUrl(value);
  }

  String buildUrl(String path) => _dio.options.baseUrl + path;

  String buildBookCoverUrl(int bookId, {String? version}) {
    final uri = Uri.parse(buildUrl('/api/me/books/$bookId/cover'));
    final normalizedVersion = version?.trim();
    if (normalizedVersion == null || normalizedVersion.isEmpty) {
      return uri.toString();
    }
    return uri
        .replace(
          queryParameters: {...uri.queryParameters, 'v': normalizedVersion},
        )
        .toString();
  }

  Future<Session> login({
    required String username,
    required String password,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {'username': username, 'password': password},
      ),
    );
    return Session.fromJson(data);
  }

  Future<Session> refresh(String refreshToken) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: {'refreshToken': refreshToken},
      ),
    );
    return Session.fromJson(data);
  }

  Future<void> logout(String accessToken) async {
    await _request<dynamic>(
      () => _dio.post<dynamic>(
        '/api/auth/logout',
        options: Options(headers: _headers(accessToken)),
      ),
    );
  }

  Future<AuthUser> updateMyProfile(
    String accessToken, {
    required String? displayName,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/me/profile',
        data: {'displayName': displayName},
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return AuthUser.fromJson(data);
  }

  Future<void> changeMyPassword(
    String accessToken, {
    required String currentPassword,
    required String newPassword,
  }) async {
    await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/me/profile/password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
        options: Options(headers: _headers(accessToken)),
      ),
    );
  }

  Future<AuthUser> uploadMyAvatar(
    String accessToken, {
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    final resolvedFileName =
        fileName ?? (filePath == null ? 'avatar.jpg' : path.basename(filePath));
    final formData = FormData.fromMap({
      'file': await _multipartFile(
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: resolvedFileName,
        contentType: DioMediaType.parse(_avatarContentType(resolvedFileName)),
      ),
    });
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/me/profile/avatar',
        data: formData,
        options: Options(
          headers: _headers(accessToken),
          contentType: 'multipart/form-data',
        ),
      ),
    );
    return AuthUser.fromJson(data);
  }

  Future<List<BookSummary>> listMyBooks(String accessToken) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/me/books',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map((item) => BookSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<BookDetail> updateMyBookGroup(
    String accessToken,
    int bookId, {
    String? groupName,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/me/books/$bookId/group',
        data: {'groupName': groupName},
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return BookDetail.fromJson(data);
  }

  Future<int> renameMyBookGroup(
    String accessToken, {
    required String oldName,
    required String newName,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/me/books/groups',
        data: {'oldName': oldName, 'newName': newName},
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return (data['updatedBooks'] as num?)?.toInt() ?? 0;
  }

  Future<List<AdminBookSummary>> listAdminBooks(String accessToken) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/books',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map((item) => AdminBookSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AdminBookDetail> getAdminBook(String accessToken, int bookId) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/api/admin/books/$bookId',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminBookDetail.fromJson(data);
  }

  Future<AdminBookDetail> updateAdminBook(
    String accessToken,
    int bookId, {
    String? groupName,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/admin/books/$bookId',
        data: {'groupName': groupName},
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminBookDetail.fromJson(data);
  }

  Future<AdminBookDetail> updateAdminBookMetadata(
    String accessToken,
    int bookId, {
    required String title,
    String? author,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/admin/books/$bookId/metadata',
        data: {'title': title, 'author': author},
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminBookDetail.fromJson(data);
  }

  Future<AdminBookDetail> rebuildAdminBookContent(
    String accessToken,
    int bookId,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/books/$bookId/content/rebuild',
        options: Options(
          headers: _headers(accessToken),
          receiveTimeout: const Duration(minutes: 5),
        ),
      ),
    );

    return AdminBookDetail.fromJson(data);
  }

  Future<int> bulkDeleteAdminBooks(
    String accessToken,
    List<int> bookIds,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/books/bulk-delete',
        data: {'bookIds': bookIds},
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return (data['deletedCount'] as num?)?.toInt() ?? 0;
  }

  Future<int> bulkGrantAdminBooks(
    String accessToken,
    List<int> bookIds, {
    required int userId,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/books/bulk-grant',
        data: {'bookIds': bookIds, 'userId': userId},
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return (data['grantedCount'] as num?)?.toInt() ?? 0;
  }

  Future<int> bulkUpdateAdminBookGroups(
    String accessToken,
    List<int> bookIds, {
    String? groupName,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/books/bulk-group',
        data: {'bookIds': bookIds, 'groupName': groupName},
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return (data['updatedCount'] as num?)?.toInt() ?? 0;
  }

  Future<BookDetail> uploadAdminBook(
    String accessToken, {
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
    ProgressCallback? onSendProgress,
  }) async {
    final resolvedFileName =
        fileName ?? (filePath == null ? 'book.epub' : path.basename(filePath));
    final formData = FormData.fromMap({
      'file': await _multipartFile(
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: resolvedFileName,
      ),
    });

    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/books/upload',
        data: formData,
        options: Options(
          headers: _headers(accessToken),
          contentType: 'multipart/form-data',
          connectTimeout: Duration.zero,
          sendTimeout: const Duration(minutes: 30),
          receiveTimeout: Duration.zero,
        ),
        onSendProgress: onSendProgress,
      ),
    );

    return BookDetail.fromJson(data);
  }

  Future<Uint8List> exportFullSystemBackup(String accessToken) async {
    return exportBackup(accessToken, scope: 'FULL');
  }

  Future<Uint8List> exportBackup(
    String accessToken, {
    required String scope,
    List<int> userIds = const [],
    List<int> bookIds = const [],
    List<String> dataTypes = const [],
  }) async {
    final data = await _request<List<int>>(
      () => _dio.get<List<int>>(
        '/api/admin/backups/export',
        queryParameters: {
          'scope': scope,
          if (userIds.isNotEmpty) 'userIds': userIds,
          if (bookIds.isNotEmpty) 'bookIds': bookIds,
          if (dataTypes.isNotEmpty) 'dataTypes': dataTypes,
        },
        options: Options(
          headers: _headers(accessToken),
          responseType: ResponseType.bytes,
          receiveTimeout: Duration.zero,
        ),
      ),
    );
    return Uint8List.fromList(data);
  }

  Future<String> createBackupDownloadTicket(
    String accessToken, {
    required String scope,
    List<int> userIds = const [],
    List<int> bookIds = const [],
    List<String> dataTypes = const [],
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/backups/export-ticket',
        data: {
          'scope': scope,
          'userIds': userIds,
          'bookIds': bookIds,
          'dataTypes': dataTypes,
        },
        options: Options(
          headers: _headers(accessToken),
          receiveTimeout: Duration.zero,
        ),
      ),
    );
    final downloadPath = data['downloadPath']?.toString().trim();
    if (downloadPath == null || downloadPath.isEmpty) {
      throw const ApiException('服务器未返回有效的备份下载地址');
    }
    return Uri.parse(baseUrl).resolve(downloadPath).toString();
  }

  Future<void> downloadBackupToFile(
    String accessToken, {
    required String destinationPath,
    required String scope,
    List<int> userIds = const [],
    List<int> bookIds = const [],
    List<String> dataTypes = const [],
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final downloadUrl = await createBackupDownloadTicket(
        accessToken,
        scope: scope,
        userIds: userIds,
        bookIds: bookIds,
        dataTypes: dataTypes,
      );
      await _dio.download(
        downloadUrl,
        destinationPath,
        options: Options(receiveTimeout: Duration.zero),
        onReceiveProgress: onReceiveProgress,
        deleteOnError: true,
      );
    } on DioException catch (error) {
      throw ApiException(
        _extractMessage(error),
        statusCode: error.response?.statusCode,
      );
    }
  }

  Future<List<AdminBackupRecord>> listBackupRecords(String accessToken) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/backups/records',
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return data
        .map((item) => AdminBackupRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AdminBackupSchedule> getBackupSchedule(String accessToken) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/api/admin/backups/schedule',
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return AdminBackupSchedule.fromJson(data);
  }

  Future<AdminBackupSchedule> updateBackupSchedule(
    String accessToken, {
    required bool enabled,
    required String frequency,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.put<Map<String, dynamic>>(
        '/api/admin/backups/schedule',
        data: {'enabled': enabled, 'frequency': frequency},
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return AdminBackupSchedule.fromJson(data);
  }

  Future<String> createBackupRecordDownloadTicket(
    String accessToken,
    String recordId,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/backups/records/$recordId/download-ticket',
        options: Options(headers: _headers(accessToken)),
      ),
    );
    final downloadPath = data['downloadPath']?.toString().trim();
    if (downloadPath == null || downloadPath.isEmpty) {
      throw const ApiException('服务器未返回有效的备份下载地址');
    }
    return Uri.parse(baseUrl).resolve(downloadPath).toString();
  }

  Future<void> downloadBackupRecordToFile(
    String accessToken, {
    required String recordId,
    required String destinationPath,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final downloadUrl = await createBackupRecordDownloadTicket(
        accessToken,
        recordId,
      );
      await _dio.download(
        downloadUrl,
        destinationPath,
        options: Options(receiveTimeout: Duration.zero),
        onReceiveProgress: onReceiveProgress,
        deleteOnError: true,
      );
    } on DioException catch (error) {
      throw ApiException(
        _extractMessage(error),
        statusCode: error.response?.statusCode,
      );
    }
  }

  Future<void> deleteBackupRecord(String accessToken, String recordId) async {
    await _request<Map<String, dynamic>>(
      () => _dio.delete<Map<String, dynamic>>(
        '/api/admin/backups/records/$recordId',
        queryParameters: const {'confirm': true},
        options: Options(headers: _headers(accessToken)),
      ),
    );
  }

  Future<AdminBackupPreview> previewSystemBackup(
    String accessToken, {
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async {
    final formData = FormData.fromMap({
      'file': await _multipartFile(
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: fileName,
      ),
    });
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/backups/preview',
        data: formData,
        options: Options(
          headers: _headers(accessToken),
          contentType: 'multipart/form-data',
          connectTimeout: Duration.zero,
          sendTimeout: Duration.zero,
          receiveTimeout: Duration.zero,
        ),
      ),
    );
    return AdminBackupPreview.fromJson(data);
  }

  Future<AdminBackupRestoreResult> restoreFullSystemBackup(
    String accessToken, {
    required String operationId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
    ProgressCallback? onSendProgress,
  }) async {
    return restoreBackup(
      accessToken,
      operationId: operationId,
      fileName: fileName,
      filePath: filePath,
      fileBytes: fileBytes,
      restoreScope: 'FULL',
      onSendProgress: onSendProgress,
    );
  }

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
    final formData = FormData.fromMap({
      'file': await _multipartFile(
        filePath: filePath,
        fileBytes: fileBytes,
        fileName: fileName,
      ),
      'request': MultipartFile.fromString(
        jsonEncode({
          'scope': restoreScope,
          'dataTypes': dataTypes,
          if (userMappings != null)
            'userMappings': userMappings.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          'mode': mode,
        }),
        contentType: DioMediaType.parse('application/json'),
      ),
    });
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/backups/restore',
        queryParameters: {'operationId': operationId},
        data: formData,
        options: Options(
          headers: _headers(accessToken),
          contentType: 'multipart/form-data',
          connectTimeout: Duration.zero,
          sendTimeout: Duration.zero,
          receiveTimeout: Duration.zero,
        ),
        onSendProgress: onSendProgress,
      ),
    );
    return AdminBackupRestoreResult.fromJson(data);
  }

  Future<AdminBackupRestoreStatus> getFullSystemRestoreStatus(
    String accessToken,
    String operationId,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/api/admin/backups/restore-status/$operationId',
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return AdminBackupRestoreStatus.fromJson(data);
  }

  Future<List<AdminUserView>> listGrantableUsers(String accessToken) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/books/grantable-users',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map((item) => AdminUserView.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> grantBook(
    String accessToken,
    int bookId, {
    required int userId,
  }) async {
    return _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/books/$bookId/grants',
        data: {'userId': userId},
        options: Options(headers: _headers(accessToken)),
      ),
    );
  }

  Future<void> revokeBookGrant(
    String accessToken,
    int bookId,
    int userId,
  ) async {
    await _request<Map<String, dynamic>>(
      () => _dio.delete<Map<String, dynamic>>(
        '/api/admin/books/$bookId/grants/$userId',
        options: Options(headers: _headers(accessToken)),
      ),
    );
  }

  Future<List<BookViewerView>> listBookViewers(
    String accessToken,
    int bookId,
  ) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/books/$bookId/viewers',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map((item) => BookViewerView.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminUserView>> listUsers(String accessToken) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/users',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map((item) => AdminUserView.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AdminUserView> createUser(
    String accessToken, {
    required String username,
    required String password,
    required String role,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/users',
        data: {'username': username, 'password': password, 'role': role},
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminUserView.fromJson(data);
  }

  Future<AdminUserView> updateUser(
    String accessToken,
    int userId, {
    bool? enabled,
    String? role,
  }) async {
    final payload = <String, dynamic>{'enabled': enabled, 'role': role}
      ..removeWhere((_, value) => value == null);

    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/admin/users/$userId',
        data: payload,
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminUserView.fromJson(data);
  }

  Future<AdminUserView> resetUserPassword(
    String accessToken,
    int userId, {
    required String newPassword,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/admin/users/$userId/password',
        data: {'newPassword': newPassword},
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminUserView.fromJson(data);
  }

  Future<List<AdminAnnotationView>> listAdminAnnotations(
    String accessToken,
  ) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/annotations',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map(
          (item) => AdminAnnotationView.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<AdminAnnotationView> updateAdminAnnotationDeleted(
    String accessToken,
    int annotationId, {
    required bool deleted,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/admin/annotations/$annotationId',
        data: {'deleted': deleted},
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminAnnotationView.fromJson(data);
  }

  Future<List<AdminLibrarySourceView>> listLibrarySources(
    String accessToken,
  ) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/library-sources',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map(
          (item) =>
              AdminLibrarySourceView.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<AdminLibrarySourceView> createLibrarySource(
    String accessToken, {
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
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/library-sources',
        data: {
          'name': name,
          'sourceType': sourceType,
          'rootPath': rootPath,
          'baseUrl': baseUrl,
          'remotePath': remotePath,
          'username': username,
          'password': password,
          'enabled': enabled,
          'scanIntervalMinutes': scanIntervalMinutes,
        },
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminLibrarySourceView.fromJson(data);
  }

  Future<AdminLibrarySourceView> updateLibrarySource(
    String accessToken,
    int sourceId, {
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
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/admin/library-sources/$sourceId',
        data: {
          'name': name,
          'sourceType': sourceType,
          'rootPath': rootPath,
          'baseUrl': baseUrl,
          'remotePath': remotePath,
          'username': username,
          'password': password,
          'enabled': enabled,
          'scanIntervalMinutes': scanIntervalMinutes,
        },
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminLibrarySourceView.fromJson(data);
  }

  Future<Map<String, dynamic>> rescanLibrarySource(
    String accessToken,
    int sourceId,
  ) async {
    return _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/library-sources/$sourceId/rescan',
        options: Options(
          headers: _headers(accessToken),
          connectTimeout: Duration.zero,
          receiveTimeout: Duration.zero,
        ),
      ),
    );
  }

  Future<AdminClientScanPlan> planClientLibraryScan(
    String accessToken,
    int sourceId,
    List<Map<String, dynamic>> files,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/library-sources/$sourceId/client-scan/plan',
        data: {'files': files},
        options: Options(headers: _headers(accessToken)),
      ),
    );
    return AdminClientScanPlan.fromJson(data);
  }

  Future<Map<String, dynamic>> uploadClientLibraryFileChunk(
    String accessToken,
    int sourceId, {
    required String relativePath,
    required String fileName,
    required int sizeBytes,
    required int lastModifiedMillis,
    required int offsetBytes,
    required Uint8List bytes,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final formData = FormData.fromMap({
      'relativePath': relativePath,
      'sizeBytes': sizeBytes,
      'lastModifiedMillis': lastModifiedMillis,
      'offsetBytes': offsetBytes,
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    return _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/admin/library-sources/$sourceId/client-file-chunks',
        data: formData,
        options: Options(
          headers: _headers(accessToken),
          contentType: 'multipart/form-data',
          connectTimeout: Duration.zero,
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: Duration.zero,
        ),
        onSendProgress: onSendProgress,
      ),
    );
  }

  Future<void> deleteLibrarySource(String accessToken, int sourceId) async {
    await _request<Map<String, dynamic>>(
      () => _dio.delete<Map<String, dynamic>>(
        '/api/admin/library-sources/$sourceId',
        options: Options(headers: _headers(accessToken)),
      ),
    );
  }

  Future<List<AdminImportJobView>> listImportJobs(String accessToken) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/books/import-jobs',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map(
          (item) => AdminImportJobView.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<AdminBookmarkView>> listAdminBookmarks(String accessToken) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/admin/bookmarks',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map((item) => AdminBookmarkView.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AdminBookmarkView> updateAdminBookmarkDeleted(
    String accessToken,
    int bookmarkId, {
    required bool deleted,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.patch<Map<String, dynamic>>(
        '/api/admin/bookmarks/$bookmarkId',
        data: {'deleted': deleted},
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return AdminBookmarkView.fromJson(data);
  }

  Future<BookDetail> getMyBook(String accessToken, int bookId) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/api/me/books/$bookId',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return BookDetail.fromJson(data);
  }

  Future<BookContent> getStructuredContent(
    String accessToken,
    int bookId,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/api/me/books/$bookId/content',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return BookContent.fromJson(data);
  }

  Future<BookContentChapter> getStructuredChapter(
    String accessToken,
    int bookId,
    int chapterIndex,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/api/me/books/$bookId/content/chapters/$chapterIndex',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return BookContentChapter.fromJson(data);
  }

  Future<Uint8List> downloadBookFile(
    String accessToken,
    int bookId, {
    ProgressCallback? onReceiveProgress,
  }) async {
    final data = await _request<List<int>>(
      () => _dio.get<List<int>>(
        '/api/me/books/$bookId/file',
        options: Options(
          headers: _headers(accessToken),
          responseType: ResponseType.bytes,
        ),
        onReceiveProgress: onReceiveProgress,
      ),
    );

    return Uint8List.fromList(data);
  }

  Future<Uint8List> downloadBookResource(
    String accessToken,
    int bookId,
    String resourceId,
  ) async {
    final data = await _request<List<int>>(
      () => _dio.get<List<int>>(
        '/api/me/books/$bookId/content/resources/$resourceId',
        options: Options(
          headers: _headers(accessToken),
          responseType: ResponseType.bytes,
        ),
      ),
    );

    return Uint8List.fromList(data);
  }

  Future<Uint8List> downloadBookCover(
    String accessToken,
    int bookId, {
    String? version,
  }) async {
    final data = await _request<List<int>>(
      () => _dio.get<List<int>>(
        buildBookCoverUrl(bookId, version: version),
        options: Options(
          headers: _headers(accessToken),
          responseType: ResponseType.bytes,
        ),
      ),
    );
    return Uint8List.fromList(data);
  }

  Future<List<AnnotationView>> listAnnotations(
    String accessToken,
    int bookId,
  ) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/me/books/$bookId/annotations',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map((item) => AnnotationView.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<BookmarkView>> listBookmarks(
    String accessToken,
    int bookId,
  ) async {
    final data = await _request<List<dynamic>>(
      () => _dio.get<List<dynamic>>(
        '/api/me/books/$bookId/bookmarks',
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return data
        .map((item) => BookmarkView.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ReadingProgressView> putProgress(
    String accessToken,
    int bookId,
    ReadingProgressMutation mutation,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.put<Map<String, dynamic>>(
        '/api/me/books/$bookId/progress',
        data: mutation.toJson(),
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return ReadingProgressView.fromJson(data);
  }

  Future<SyncPullResponse> pullSync(String accessToken, {int? cursor}) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.get<Map<String, dynamic>>(
        '/api/me/sync/pull',
        queryParameters: cursor == null ? null : {'cursor': cursor},
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return SyncPullResponse.fromJson(data);
  }

  Future<SyncPushResponse> pushSync(
    String accessToken,
    SyncPushRequest request,
  ) async {
    final data = await _request<Map<String, dynamic>>(
      () => _dio.post<Map<String, dynamic>>(
        '/api/me/sync/push',
        data: request.toJson(),
        options: Options(headers: _headers(accessToken)),
      ),
    );

    return SyncPushResponse.fromJson(data);
  }

  Map<String, String> coverHeaders(String accessToken) => _headers(accessToken);

  Map<String, String> _headers(String accessToken) => {
    'Authorization': 'Bearer $accessToken',
  };

  Future<MultipartFile> _multipartFile({
    required String? filePath,
    required Uint8List? fileBytes,
    required String fileName,
    DioMediaType? contentType,
  }) async {
    if (fileBytes != null) {
      return MultipartFile.fromBytes(
        fileBytes,
        filename: fileName,
        contentType: contentType,
      );
    }
    if (filePath != null && filePath.trim().isNotEmpty) {
      return MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: contentType,
      );
    }
    throw const ApiException('未能读取所选文件');
  }

  Future<T> _request<T>(Future<Response<T>> Function() action) async {
    try {
      final response = await action();
      final data = response.data;
      if (data == null) {
        throw const ApiException('服务器未返回有效数据');
      }
      return data;
    } on DioException catch (error) {
      throw ApiException(
        _extractMessage(error),
        statusCode: error.response?.statusCode,
      );
    }
  }

  String _extractMessage(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 413) {
      return '文件超过服务器上传限制，请联系管理员调整上传配置';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError) {
      return '无法连接到服务器，请检查服务地址和网络。';
    }
    if (error.type == DioExceptionType.sendTimeout) {
      return '文件上传超时，请确认服务器仍在运行后重试';
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return '服务器解析图书超时，请稍后检查导入结果';
    }
    if (error.type == DioExceptionType.cancel) {
      return '请求已取消，请重试。';
    }
    if (error.type == DioExceptionType.badCertificate) {
      return '无法验证服务器证书，请检查服务地址。';
    }

    final serverMessage = _serverMessage(error.response?.data);
    final mappedMessage = _mapServerMessage(serverMessage);
    if (mappedMessage != null) return mappedMessage;
    if (statusCode != null && statusCode >= 500) {
      return '服务器暂时无法处理请求，请稍后重试。';
    }

    return switch (statusCode) {
      400 => '提交的信息有误，请检查后重试。',
      401 => '登录状态已失效，请重新登录。',
      403 => '你没有权限执行此操作。',
      404 => '请求的内容不存在或已被删除。',
      408 => '请求超时，请检查网络后重试。',
      409 => '数据已发生变化，请刷新后重试。',
      429 => '操作过于频繁，请稍后再试。',
      _ => '网络请求失败，请检查网络后重试。',
    };
  }

  String? _serverMessage(Object? responseData) {
    if (responseData is Map<String, dynamic>) {
      return (responseData['error'] ?? responseData['message'])
          ?.toString()
          .trim();
    }
    if (responseData is String) return responseData.trim();
    return null;
  }

  String? _mapServerMessage(String? message) {
    if (message == null || message.isEmpty) return null;
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid username or password')) {
      return '用户名或密码不正确，请重试。';
    }
    if (normalized.contains('user is disabled')) {
      return '该账号已被停用，请联系管理员。';
    }
    if (normalized.contains('current password is incorrect')) {
      return '当前密码不正确，请重试。';
    }
    if (normalized.contains('uploaded file is too large')) {
      return '文件超过服务器上传限制，请联系管理员调整上传配置';
    }
    if (normalized.contains('avatar file must not exceed')) {
      return '头像文件不能超过 5 MB。';
    }
    if (normalized.contains('only jpeg, png, webp or gif avatars')) {
      return '头像仅支持 JPEG、PNG、WebP 或 GIF 格式。';
    }
    if (normalized.contains('book access denied')) {
      return '你没有访问这本书的权限。';
    }
    if (normalized.contains('not found')) {
      return '请求的内容不存在或已被删除。';
    }
    if (normalized.contains('no plugin available')) {
      return '暂不支持导入该文件格式。';
    }
    if (normalized.contains('webdav')) {
      return '无法访问 WebDAV 服务，请检查地址、账号和网络。';
    }
    return null;
  }

  String _avatarContentType(String filePath) {
    return switch (path.extension(filePath).toLowerCase()) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'application/octet-stream',
    };
  }
}
