import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/book_models.dart';
import '../../data/models/sync_models.dart';
import '../../data/services/api_client.dart';
import '../../data/services/offline_queue_service.dart';
import '../../data/services/offline_book_cache_service.dart';
import '../auth/auth_controller.dart';

const String bookshelfFilterAll = 'all';
const String bookshelfFilterRead = 'read';
const String bookshelfFilterUnread = 'unread';
const String _bookshelfFilterGroupPrefix = 'group:';

class BookshelfFilterOption {
  const BookshelfFilterOption({required this.key, required this.label});

  final String key;
  final String label;
}

final bookshelfControllerProvider = ChangeNotifierProvider<BookshelfController>(
  (ref) {
    return BookshelfController(
      authController: ref.read(authControllerProvider),
      apiClient: ref.watch(apiClientProvider),
      offlineQueueService: ref.watch(offlineQueueServiceProvider),
      offlineBookCacheService: ref.watch(offlineBookCacheServiceProvider),
    );
  },
);

class BookshelfController extends ChangeNotifier {
  BookshelfController({
    required AuthController authController,
    required ApiClient apiClient,
    required OfflineQueueService offlineQueueService,
    required OfflineBookCacheService offlineBookCacheService,
  }) : _authController = authController,
       _apiClient = apiClient,
       _offlineQueueService = offlineQueueService,
       _offlineBookCacheService = offlineBookCacheService {
    _authController.addListener(_handleAuthChange);
    _handleAuthChange();
  }

  final AuthController _authController;
  final ApiClient _apiClient;
  final OfflineQueueService _offlineQueueService;
  final OfflineBookCacheService _offlineBookCacheService;

  List<BookSummary> _books = const [];
  bool _isLoading = false;
  String? _error;
  int _pendingCount = 0;
  Set<int> _cachedBookIds = <int>{};
  final Map<int, Uint8List> _offlineCoverBytes = <int, Uint8List>{};
  final Set<int> _downloadingBookIds = <int>{};
  int _offlineLibrarySizeBytes = 0;
  List<ReadingProgressView> _readingProgresses = const [];
  String _selectedFilterKey = bookshelfFilterAll;
  int? _activeUserId;

  List<BookSummary> get books => _books;
  String get selectedFilterKey => _selectedFilterKey;
  List<String> get groupNames {
    final groups = _books
        .map((book) => book.groupName?.trim())
        .whereType<String>()
        .where((group) => group.isNotEmpty)
        .toSet()
        .toList();
    groups.sort((left, right) => left.compareTo(right));
    return groups;
  }

  List<BookshelfFilterOption> get filterOptions => [
    const BookshelfFilterOption(key: bookshelfFilterAll, label: '全部书籍'),
    const BookshelfFilterOption(key: bookshelfFilterRead, label: '已读书籍'),
    const BookshelfFilterOption(key: bookshelfFilterUnread, label: '未读书籍'),
    ...groupNames.map(
      (group) => BookshelfFilterOption(
        key: '$_bookshelfFilterGroupPrefix$group',
        label: '分类 · $group',
      ),
    ),
  ];

  List<BookSummary> get filteredBooks => switch (_selectedFilterKey) {
    bookshelfFilterRead =>
      _books.where((book) => _hasBeenRead(book.id)).toList(),
    bookshelfFilterUnread =>
      _books.where((book) => !_hasBeenRead(book.id)).toList(),
    final key when key.startsWith(_bookshelfFilterGroupPrefix) =>
      _books
          .where(
            (book) =>
                book.groupName?.trim() ==
                key.substring(_bookshelfFilterGroupPrefix.length),
          )
          .toList(),
    _ => _books,
  };
  List<BookSummary> get recentBooks {
    final booksById = {for (final book in _books) book.id: book};
    final progresses = [..._readingProgresses]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return progresses
        .map((progress) => booksById[progress.bookId])
        .whereType<BookSummary>()
        .take(10)
        .toList();
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingCount => _pendingCount;
  int get offlineBookCount => _cachedBookIds.length;
  int get offlineLibrarySizeBytes => _offlineLibrarySizeBytes;
  bool get isOfflineMode => _authController.isOfflineMode;
  bool isBookCached(int bookId) => _cachedBookIds.contains(bookId);
  bool isBookDownloading(int bookId) => _downloadingBookIds.contains(bookId);
  Uint8List? offlineCoverForBook(int bookId) => _offlineCoverBytes[bookId];
  String get serviceBaseUrl => _apiClient.baseUrl;
  ReadingProgressView? progressForBook(int bookId) {
    for (final progress in _readingProgresses) {
      if (progress.bookId == bookId) {
        return progress;
      }
    }
    return null;
  }

  void setFilter(String key) {
    if (_selectedFilterKey == key ||
        !filterOptions.any((option) => option.key == key)) {
      return;
    }
    _selectedFilterKey = key;
    notifyListeners();
  }

  List<BookSummary> searchBooks(String query) {
    final normalizedQuery = _normalizeForSearch(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }
    return _books
        .where((book) => _matchesSearch(book, normalizedQuery))
        .toList();
  }

  Future<void> refresh() async {
    if (!_authController.isAuthenticated) {
      _books = const [];
      _readingProgresses = const [];
      _selectedFilterKey = bookshelfFilterAll;
      _pendingCount = 0;
      _error = null;
      notifyListeners();
      return;
    }

    final userId = _authController.user!.id;
    var localProgresses = <ReadingProgressView>[];
    try {
      final cachedBooks = await _offlineBookCacheService.loadCachedBooks(
        userId,
      );
      if (_books.isEmpty) _books = cachedBooks;
      _cachedBookIds = await _offlineBookCacheService.cachedBookIds(userId);
      await _loadOfflineCovers(userId);
      _offlineLibrarySizeBytes = await _offlineBookCacheService.totalSizeBytes(
        userId,
      );
      localProgresses = (await Future.wait(
        cachedBooks.map(
          (book) => _offlineBookCacheService.loadProgress(userId, book.id),
        ),
      )).whereType<ReadingProgressView>().toList();
      _readingProgresses = _mergeProgresses(
        _readingProgresses,
        localProgresses,
      );
      _pendingCount = await _offlineQueueService.pendingCount();
    } catch (error, stackTrace) {
      developer.log(
        'Failed to load offline bookshelf',
        name: 'BookshelfController',
        error: error,
        stackTrace: stackTrace,
      );
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final nextBooks = await _authController.runAuthorized(
        (accessToken) => _apiClient.listMyBooks(accessToken),
      );
      _authController.markServerReachable();
      var nextProgresses = _readingProgresses;
      try {
        final sync = await _authController.runAuthorized(
          (accessToken) => _apiClient.pullSync(accessToken, cursor: 0),
        );
        nextProgresses = _mergeProgresses(sync.progresses, localProgresses);
      } catch (error, stackTrace) {
        developer.log(
          'Failed to load recent reading progress',
          name: 'BookshelfController',
          error: error,
          stackTrace: stackTrace,
        );
      }
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
      _cachedBookIds = await _offlineBookCacheService.cachedBookIds(userId);
      await _loadOfflineCovers(userId);
      _offlineLibrarySizeBytes = await _offlineBookCacheService.totalSizeBytes(
        userId,
      );
      _readingProgresses = nextProgresses;
      if (!filterOptions.any((option) => option.key == _selectedFilterKey)) {
        _selectedFilterKey = bookshelfFilterAll;
      }
      _pendingCount = count;
    } catch (error, stackTrace) {
      if (error is ApiException && error.isNetworkFailure) {
        _authController.markServerUnavailable();
      }
      _error = _books.isEmpty
          ? '书架加载失败。请连接服务器，或先在联网时下载书籍。\n当前服务：${_apiClient.baseUrl}\n$error'
          : null;
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

  Future<void> downloadForOffline(BookSummary summary) async {
    final user = _authController.user;
    if (user == null || _downloadingBookIds.contains(summary.id)) return;
    _downloadingBookIds.add(summary.id);
    _error = null;
    notifyListeners();

    try {
      await _offlineBookCacheService.deleteBook(user.id, summary.id);
      final detail = await _authController.runAuthorized(
        (token) => _apiClient.getMyBook(token, summary.id),
      );
      final readerState = await Future.wait<Object?>([
        _authController.runAuthorized(
          (token) => _apiClient.pullSync(token, cursor: 0),
        ),
        _authController.runAuthorized(
          (token) => _apiClient.listAnnotations(token, summary.id),
        ),
        _authController.runAuthorized(
          (token) => _apiClient.listBookmarks(token, summary.id),
        ),
        _downloadCover(summary.id),
      ]);

      BookContent? content;
      Uint8List? fileBytes;
      var sizeBytes = 0;
      if (detail.isPdf) {
        final downloadedFile = await _authController.runAuthorized(
          (token) => _apiClient.downloadBookFile(token, summary.id),
        );
        fileBytes = downloadedFile;
        sizeBytes += downloadedFile.length;
      } else if (detail.supportsStructuredReader) {
        final downloadedContent = await _authController.runAuthorized(
          (token) => _apiClient.getStructuredContent(token, summary.id),
        );
        content = downloadedContent;
        sizeBytes += utf8.encode(jsonEncode(downloadedContent.toJson())).length;
        final resourceIds = <String>{};
        for (final chapterSummary in downloadedContent.chapters) {
          final chapter = await _authController.runAuthorized(
            (token) => _apiClient.getStructuredChapter(
              token,
              summary.id,
              chapterSummary.chapterIndex,
            ),
          );
          await _offlineBookCacheService.saveChapter(
            user.id,
            summary.id,
            chapter,
          );
          sizeBytes += utf8.encode(jsonEncode(chapter.toJson())).length;
          resourceIds.addAll(
            chapter.blocks
                .where((block) => block.isImage)
                .map((block) => block.resourceId)
                .whereType<String>()
                .where((id) => id.isNotEmpty),
          );
        }
        for (final resourceId in resourceIds) {
          final bytes = await _authController.runAuthorized(
            (token) =>
                _apiClient.downloadBookResource(token, summary.id, resourceId),
          );
          await _offlineBookCacheService.saveResource(
            user.id,
            summary.id,
            resourceId,
            bytes,
          );
          sizeBytes += bytes.length;
        }
      } else {
        throw const ApiException('当前书籍格式暂不支持离线阅读');
      }

      final sync = readerState[0]! as SyncPullResponse;
      final annotations = readerState[1]! as List<AnnotationView>;
      final bookmarks = readerState[2]! as List<BookmarkView>;
      final coverBytes = readerState[3] as Uint8List?;
      if (coverBytes != null) sizeBytes += coverBytes.length;
      ReadingProgressView? progress;
      for (final item in sync.progresses) {
        if (item.bookId == summary.id) {
          progress = item;
          break;
        }
      }
      await _offlineBookCacheService.saveDownloadedBook(
        userId: user.id,
        summary: summary,
        detail: detail,
        content: content,
        annotations: annotations.where((item) => !item.deleted).toList(),
        bookmarks: bookmarks.where((item) => !item.deleted).toList(),
        progress: progress,
        fileBytes: fileBytes,
        coverBytes: coverBytes,
        sizeBytes: sizeBytes,
      );
      _cachedBookIds.add(summary.id);
      if (coverBytes != null) _offlineCoverBytes[summary.id] = coverBytes;
      _offlineLibrarySizeBytes = await _offlineBookCacheService.totalSizeBytes(
        user.id,
      );
    } catch (error, stackTrace) {
      await _offlineBookCacheService.deleteBook(user.id, summary.id);
      _cachedBookIds.remove(summary.id);
      _error = '“${summary.title}”下载失败：$error';
      developer.log(
        'Offline book download failed',
        name: 'BookshelfController',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      _downloadingBookIds.remove(summary.id);
      notifyListeners();
    }
  }

  Future<void> removeOfflineDownload(int bookId) async {
    final user = _authController.user;
    if (user == null) return;
    await _offlineBookCacheService.deleteBook(user.id, bookId);
    _cachedBookIds.remove(bookId);
    _offlineCoverBytes.remove(bookId);
    _offlineLibrarySizeBytes = await _offlineBookCacheService.totalSizeBytes(
      user.id,
    );
    notifyListeners();
  }

  Future<Uint8List?> _downloadCover(int bookId) async {
    try {
      return await _authController.runAuthorized(
        (token) => _apiClient.downloadBookCover(token, bookId),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadOfflineCovers(int userId) async {
    for (final bookId in _cachedBookIds) {
      final bytes = await _offlineBookCacheService.loadCover(userId, bookId);
      if (bytes != null) _offlineCoverBytes[bookId] = bytes;
    }
    _offlineCoverBytes.removeWhere(
      (bookId, _) => !_cachedBookIds.contains(bookId),
    );
  }

  List<ReadingProgressView> _mergeProgresses(
    List<ReadingProgressView> primary,
    List<ReadingProgressView> secondary,
  ) {
    final byBook = <int, ReadingProgressView>{};
    for (final progress in [...primary, ...secondary]) {
      final existing = byBook[progress.bookId];
      if (existing == null ||
          progress.updatedAt.compareTo(existing.updatedAt) > 0) {
        byBook[progress.bookId] = progress;
      }
    }
    return byBook.values.toList();
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChange);
    super.dispose();
  }

  void _handleAuthChange() {
    final userId = _authController.user?.id;
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    if (userId != null) {
      refresh();
    } else {
      _books = const [];
      _readingProgresses = const [];
      _selectedFilterKey = bookshelfFilterAll;
      _pendingCount = 0;
      _error = null;
      notifyListeners();
    }
  }

  bool _matchesSearch(BookSummary book, String normalizedQuery) {
    final candidates = [
      book.title,
      book.author,
      book.description,
      book.groupName,
      book.format,
      book.pluginId,
    ];
    return candidates
        .whereType<String>()
        .map(_normalizeForSearch)
        .any((candidate) => candidate.contains(normalizedQuery));
  }

  bool _hasBeenRead(int bookId) {
    final progress = progressForBook(bookId);
    return progress != null && progress.progressPercent > 0;
  }

  String _normalizeForSearch(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
