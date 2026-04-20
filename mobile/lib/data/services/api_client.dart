import 'package:dio/dio.dart';

import '../../shared/config/app_config.dart';
import '../models/auth_models.dart';
import '../models/book_models.dart';
import '../models/sync_models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

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
    final responseData = error.response?.data;
    if (responseData is Map<String, dynamic>) {
      return (responseData['error'] ?? responseData['message'] ?? '请求失败')
          .toString();
    }
    if (responseData is String && responseData.trim().isNotEmpty) {
      return responseData.trim();
    }
    return error.message ?? '网络请求失败';
  }
}
