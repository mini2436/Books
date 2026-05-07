import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/book_models.dart';
import '../../data/services/api_client.dart';
import '../../data/services/offline_queue_service.dart';
import '../auth/auth_controller.dart';

final bookshelfControllerProvider = ChangeNotifierProvider<BookshelfController>(
  (ref) {
    return BookshelfController(
      authController: ref.read(authControllerProvider),
      apiClient: ref.watch(apiClientProvider),
      offlineQueueService: ref.watch(offlineQueueServiceProvider),
    );
  },
);

class BookshelfController extends ChangeNotifier {
  BookshelfController({
    required AuthController authController,
    required ApiClient apiClient,
    required OfflineQueueService offlineQueueService,
  }) : _authController = authController,
       _apiClient = apiClient,
       _offlineQueueService = offlineQueueService {
    _authController.addListener(_handleAuthChange);
    _handleAuthChange();
  }

  final AuthController _authController;
  final ApiClient _apiClient;
  final OfflineQueueService _offlineQueueService;

  List<BookSummary> _books = const [];
  bool _isLoading = false;
  String? _error;
  int _pendingCount = 0;
  String _searchQuery = '';

  List<BookSummary> get books => _books;
  List<BookSummary> get visibleBooks {
    final normalizedQuery = _normalizedSearchQuery;
    if (normalizedQuery.isEmpty) {
      return _books;
    }
    return _books
        .where((book) => _matchesSearch(book, normalizedQuery))
        .toList();
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingCount => _pendingCount;
  String get serviceBaseUrl => _apiClient.baseUrl;
  String get searchQuery => _searchQuery;
  bool get hasSearchQuery => _normalizedSearchQuery.isNotEmpty;
  int get visibleBookCount => visibleBooks.length;

  Future<void> refresh() async {
    if (!_authController.isAuthenticated) {
      _books = const [];
      _pendingCount = 0;
      _error = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final nextBooks = await _authController.runAuthorized(
        (accessToken) => _apiClient.listMyBooks(accessToken),
      );
      var count = _pendingCount;
      try {
        count = await _offlineQueueService.pendingCount();
      } catch (error, stackTrace) {
        developer.log(
          'Failed to read offline queue count',
          name: 'BookshelfController',
          error: error,
          stackTrace: stackTrace,
        );
      }
      _books = nextBooks;
      _pendingCount = count;
    } catch (error, stackTrace) {
      _error = '书架加载失败，请检查服务地址、登录状态或网络后重试。\n当前服务：${_apiClient.baseUrl}\n$error';
      developer.log(
        'Bookshelf refresh failed',
        name: 'BookshelfController',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChange);
    super.dispose();
  }

  void _handleAuthChange() {
    if (_authController.isAuthenticated) {
      refresh();
    } else {
      _books = const [];
      _pendingCount = 0;
      _error = null;
      notifyListeners();
    }
  }

  void updateSearchQuery(String value) {
    if (value == _searchQuery) {
      return;
    }
    _searchQuery = value;
    notifyListeners();
  }

  void clearSearchQuery() {
    if (_searchQuery.isEmpty) {
      return;
    }
    _searchQuery = '';
    notifyListeners();
  }

  String get _normalizedSearchQuery => _normalizeForSearch(_searchQuery);

  bool _matchesSearch(BookSummary book, String normalizedQuery) {
    final candidates = [
      book.title,
      book.author,
      book.description,
      book.format,
      book.pluginId,
    ];
    return candidates
        .whereType<String>()
        .map(_normalizeForSearch)
        .any((candidate) => candidate.contains(normalizedQuery));
  }

  String _normalizeForSearch(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
