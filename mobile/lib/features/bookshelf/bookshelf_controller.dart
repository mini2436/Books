import 'dart:async';
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
    _offlineQueueService.addListener(_handleQueueChanged);
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
  final Map<int, Future<Uint8List?>> _offlineCoverLoads =
      <int, Future<Uint8List?>>{};
  final Set<int> _downloadingBookIds = <int>{};
  int _offlineLibrarySizeBytes = 0;
  List<ReadingProgressView> _readingProgresses = const [];
  List<ReadingHistoryView> _readingHistories = const [];
  String _selectedFilterKey = bookshelfFilterAll;
  String? _activeScopeKey;
  int _pendingCountRequestId = 0;
  List<String> _groupNames = const [];
  Map<String, List<BookSummary>> _groupedBooks = const {};
  List<BookshelfFilterOption> _filterOptions = const [
    BookshelfFilterOption(key: bookshelfFilterAll, label: '全部书籍'),
    BookshelfFilterOption(key: bookshelfFilterRead, label: '已读书籍'),
    BookshelfFilterOption(key: bookshelfFilterUnread, label: '未读书籍'),
  ];
  List<BookSummary> _filteredBooks = const [];
  List<BookSummary> _recentBooks = const [];
  Map<int, ReadingProgressView> _progressByBookId = const {};
  Map<int, String> _searchCorpusByBookId = const {};

  List<BookSummary> get books => _books;
  String get selectedFilterKey => _selectedFilterKey;
  List<String> get groupNames => _groupNames;
  Map<String, List<BookSummary>> get groupedBooks => _groupedBooks;
  List<BookshelfFilterOption> get filterOptions => _filterOptions;
  List<BookSummary> get filteredBooks => _filteredBooks;
  List<BookSummary> get recentBooks => _recentBooks;

  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingCount => _pendingCount;
  int get offlineBookCount => _cachedBookIds.length;
  int get offlineLibrarySizeBytes => _offlineLibrarySizeBytes;
  bool get isOfflineMode => _authController.isOfflineMode;
  bool get isOfflineGuest => _authController.isOfflineGuest;
  bool isBookCached(int bookId) => _cachedBookIds.contains(bookId);
  bool isBookDownloading(int bookId) => _downloadingBookIds.contains(bookId);
  Future<Uint8List?>? offlineCoverForBook(int bookId) {
    if (!_cachedBookIds.contains(bookId)) return null;
    final existingLoad = _offlineCoverLoads[bookId];
    if (existingLoad != null) return existingLoad;
    final cached = _offlineCoverBytes[bookId];
    if (cached != null) {
      return _offlineCoverLoads.putIfAbsent(
        bookId,
        () => Future<Uint8List?>.value(cached),
      );
    }
    final serverKey = _authController.activeServerKey;
    final userId = _authController.activeUserId;
    if (serverKey == null || userId == null) return null;
    return _offlineCoverLoads.putIfAbsent(bookId, () async {
      Uint8List? bytes;
      try {
        bytes = await _offlineBookCacheService.loadCover(
          serverKey,
          userId,
          bookId,
        );
      } catch (_) {
        return null;
      }
      if (_authController.activeServerKey == serverKey &&
          _authController.activeUserId == userId &&
          _cachedBookIds.contains(bookId) &&
          bytes != null) {
        _offlineCoverBytes[bookId] = bytes;
      }
      return bytes;
    });
  }

  String get serviceBaseUrl => _apiClient.baseUrl;
  ReadingProgressView? progressForBook(int bookId) => _progressByBookId[bookId];

  ReadingProgressView? progressFor(int bookId) => progressForBook(bookId);

  Future<List<AnnotationView>> loadAnnotations(int bookId) async {
    List<AnnotationView> annotations;
    try {
      annotations = await _authController.runAuthorized(
        (accessToken) => _apiClient.listAnnotations(accessToken, bookId),
      );
    } catch (_) {
      final userId = _authController.activeUserId;
      final serverKey = _authController.activeServerKey;
      if (userId == null ||
          serverKey == null ||
          !await _offlineBookCacheService.isBookCached(
            serverKey,
            userId,
            bookId,
          )) {
        rethrow;
      }
      annotations = await _offlineBookCacheService.loadAnnotations(
        serverKey,
        userId,
        bookId,
      );
    }
    return annotations.where((item) => !item.deleted).toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  /// Loads only the structured-reader chapter summaries used by the book dialog.
  ///
  /// The content endpoint does not include chapter bodies, so opening the
  /// dialog never starts a potentially expensive chapter download. A missing
  /// or unavailable content index is treated as no chapter navigation.
  Future<List<BookContentChapterSummary>> loadChapterSummaries(
    int bookId,
  ) async {
    BookContent? content;
    try {
      content = await _authController.runAuthorized(
        (accessToken) => _apiClient.getStructuredContent(accessToken, bookId),
      );
    } catch (_) {
      final userId = _authController.activeUserId;
      final serverKey = _authController.activeServerKey;
      if (userId == null ||
          serverKey == null ||
          !await _offlineBookCacheService.isBookCached(
            serverKey,
            userId,
            bookId,
          )) {
        return const [];
      }
      try {
        content = await _offlineBookCacheService.loadContent(
          serverKey,
          userId,
          bookId,
        );
      } catch (_) {
        return const [];
      }
    }

    if (content == null || !content.hasStructuredContent) return const [];
    return content.chapters
        .where((chapter) => chapter.anchor.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> updateBookGroup(int bookId, String? groupName) async {
    final normalized = groupName?.trim();
    final updated = await _authController.runAuthorized(
      (accessToken) => _apiClient.updateMyBookGroup(
        accessToken,
        bookId,
        groupName: normalized == null || normalized.isEmpty ? null : normalized,
      ),
    );
    _books = _books
        .map(
          (book) => book.id == bookId
              ? book.copyWith(
                  groupName: updated.groupName,
                  clearGroup: updated.groupName == null,
                )
              : book,
        )
        .toList();
    _rebuildDerivedState();
    notifyListeners();
  }

  Future<int> renameGroup(String oldName, String newName) async {
    final normalizedOldName = oldName.trim();
    final normalizedNewName = newName.trim();
    if (normalizedOldName == normalizedNewName) {
      return 0;
    }
    final updatedBooks = await _authController.runAuthorized(
      (accessToken) => _apiClient.renameMyBookGroup(
        accessToken,
        oldName: normalizedOldName,
        newName: normalizedNewName,
      ),
    );
    _books = _books
        .map(
          (book) => book.groupName?.trim() == normalizedOldName
              ? book.copyWith(groupName: normalizedNewName)
              : book,
        )
        .toList();
    if (_selectedFilterKey ==
        '$_bookshelfFilterGroupPrefix$normalizedOldName') {
      _selectedFilterKey = '$_bookshelfFilterGroupPrefix$normalizedNewName';
    }
    _rebuildDerivedState();
    notifyListeners();
    return updatedBooks;
  }

  void setFilter(String key) {
    if (_selectedFilterKey == key ||
        !filterOptions.any((option) => option.key == key)) {
      return;
    }
    _selectedFilterKey = key;
    _rebuildFilteredBooks();
    notifyListeners();
  }

  List<BookSummary> searchBooks(String query) {
    final normalizedQuery = _normalizeForSearch(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }
    return _books
        .where(
          (book) =>
              _searchCorpusByBookId[book.id]?.contains(normalizedQuery) ??
              false,
        )
        .toList();
  }

  Future<void> refresh() async {
    final userId = _authController.activeUserId;
    final serverKey = _authController.activeServerKey;
    if (userId == null || serverKey == null) {
      _pendingCountRequestId++;
      _books = const [];
      _readingProgresses = const [];
      _readingHistories = const [];
      _selectedFilterKey = bookshelfFilterAll;
      _pendingCount = 0;
      _error = null;
      _clearOfflineCoverCache();
      _rebuildDerivedState();
      notifyListeners();
      return;
    }

    var localProgresses = <ReadingProgressView>[];
    var cachedBooks = <BookSummary>[];
    var offlineStateLoaded = false;
    try {
      cachedBooks = await _offlineBookCacheService.loadCachedBooks(
        serverKey,
        userId,
      );
      if (_books.isEmpty) _books = cachedBooks;
      _cachedBookIds = {for (final book in cachedBooks) book.id};
      _pruneOfflineCoverCache();
      _offlineLibrarySizeBytes = await _offlineBookCacheService.totalSizeBytes(
        serverKey,
        userId,
      );
      localProgresses = await _offlineBookCacheService.loadProgresses(
        serverKey,
        userId,
      );
      _readingProgresses = _mergeProgresses(
        _readingProgresses,
        localProgresses,
      );
      _rebuildDerivedState();
      await _refreshPendingCount(serverKey, userId);
      offlineStateLoaded = true;
    } catch (error, stackTrace) {
      developer.log(
        'Failed to load offline bookshelf',
        name: 'BookshelfController',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (_authController.isOfflineGuest) {
      _books = cachedBooks;
      _rebuildDerivedState();
      _error = null;
      _isLoading = false;
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
      _authController.markServerReachable();
      var nextProgresses = _readingProgresses;
      var nextHistories = _readingHistories;
      try {
        final sync = await _authController.runAuthorized(
          (accessToken) => _apiClient.pullSync(accessToken, cursor: 0),
        );
        nextProgresses = _mergeProgresses(sync.progresses, localProgresses);
        nextHistories = sync.histories;
      } catch (error, stackTrace) {
        developer.log(
          'Failed to load recent reading progress',
          name: 'BookshelfController',
          error: error,
          stackTrace: stackTrace,
        );
      }
      _books = nextBooks;
      if (!offlineStateLoaded) {
        _cachedBookIds = await _offlineBookCacheService.cachedBookIds(
          serverKey,
          userId,
        );
        _pruneOfflineCoverCache();
        _offlineLibrarySizeBytes = await _offlineBookCacheService
            .totalSizeBytes(serverKey, userId);
      }
      _readingProgresses = nextProgresses;
      _readingHistories = nextHistories;
      _rebuildDerivedState();
      if (!_filterOptions.any((option) => option.key == _selectedFilterKey)) {
        _selectedFilterKey = bookshelfFilterAll;
        _rebuildFilteredBooks();
      }
      if (!offlineStateLoaded) {
        await _refreshPendingCount(serverKey, userId);
      }
    } catch (error, stackTrace) {
      if (error is ApiException && error.isNetworkFailure) {
        _authController.markServerUnavailable();
      }
      _error = _books.isEmpty
          ? '书架加载失败。请检查服务器地址和网络，或先在联网时下载书籍。\n当前服务：${_apiClient.baseUrl}'
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
    final serverKey = _authController.activeServerKey;
    if (user == null ||
        serverKey == null ||
        _downloadingBookIds.contains(summary.id)) {
      return;
    }
    if (await _offlineBookCacheService.isBookCached(
      serverKey,
      user.id,
      summary.id,
    )) {
      // 阅读器首次打开已写入同一份离线缓存，无需重复下载。
      _cachedBookIds.add(summary.id);
      notifyListeners();
      return;
    }
    _downloadingBookIds.add(summary.id);
    _error = null;
    notifyListeners();

    try {
      await _offlineBookCacheService.deleteBook(serverKey, user.id, summary.id);
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
        _downloadCover(summary),
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
            serverKey,
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
            serverKey,
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
        serverKey: serverKey,
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
      if (coverBytes != null) {
        _offlineCoverBytes[summary.id] = coverBytes;
        _offlineCoverLoads[summary.id] = Future<Uint8List?>.value(coverBytes);
      }
      _offlineLibrarySizeBytes = await _offlineBookCacheService.totalSizeBytes(
        serverKey,
        user.id,
      );
    } catch (error, stackTrace) {
      await _offlineBookCacheService.deleteBook(serverKey, user.id, summary.id);
      _cachedBookIds.remove(summary.id);
      _error =
          '“${summary.title}”下载失败：${ApiException.userFacingMessage(error, fallback: '请检查网络后重试。')}';
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
    final serverKey = _authController.activeServerKey;
    if (user == null || serverKey == null) return;
    await _offlineBookCacheService.deleteBook(serverKey, user.id, bookId);
    _cachedBookIds.remove(bookId);
    _offlineCoverBytes.remove(bookId);
    _offlineCoverLoads.remove(bookId);
    _offlineLibrarySizeBytes = await _offlineBookCacheService.totalSizeBytes(
      serverKey,
      user.id,
    );
    notifyListeners();
  }

  Future<Uint8List?> _downloadCover(BookSummary book) async {
    try {
      return await _authController.runAuthorized(
        (token) => _apiClient.downloadBookCover(
          token,
          book.id,
          version: book.coverVersion,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _pruneOfflineCoverCache() {
    _offlineCoverBytes.removeWhere(
      (bookId, _) => !_cachedBookIds.contains(bookId),
    );
    _offlineCoverLoads.removeWhere(
      (bookId, _) => !_cachedBookIds.contains(bookId),
    );
  }

  void _clearOfflineCoverCache() {
    _offlineCoverBytes.clear();
    _offlineCoverLoads.clear();
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
    _offlineQueueService.removeListener(_handleQueueChanged);
    super.dispose();
  }

  void _handleQueueChanged() {
    final serverKey = _authController.activeServerKey;
    final userId = _authController.activeUserId;
    if (serverKey == null || userId == null) return;
    unawaited(_refreshPendingCount(serverKey, userId));
  }

  Future<void> _refreshPendingCount(String serverKey, int userId) async {
    final requestId = ++_pendingCountRequestId;
    try {
      final count = await _offlineQueueService.pendingCount(
        serverKey: serverKey,
        userId: userId,
      );
      if (requestId != _pendingCountRequestId ||
          _authController.activeServerKey != serverKey ||
          _authController.activeUserId != userId) {
        return;
      }
      if (_pendingCount == count) return;
      _pendingCount = count;
      notifyListeners();
    } catch (_) {
      // The next bookshelf refresh will retry the count.
    }
  }

  void _handleAuthChange() {
    final userId = _authController.activeUserId;
    final serverKey = _authController.activeServerKey;
    final scopeKey = userId == null || serverKey == null
        ? null
        : '$serverKey\u0000$userId';
    if (_activeScopeKey == scopeKey) return;
    _activeScopeKey = scopeKey;
    _cachedBookIds = <int>{};
    _clearOfflineCoverCache();
    if (scopeKey != null) {
      refresh();
    } else {
      _pendingCountRequestId++;
      _books = const [];
      _readingProgresses = const [];
      _readingHistories = const [];
      _selectedFilterKey = bookshelfFilterAll;
      _pendingCount = 0;
      _error = null;
      _clearOfflineCoverCache();
      _rebuildDerivedState();
      notifyListeners();
    }
  }

  String _searchCorpus(BookSummary book) {
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
        .join('\u0000');
  }

  bool _hasBeenRead(int bookId) {
    final progress = progressForBook(bookId);
    return progress != null && progress.progressPercent > 0;
  }

  String _normalizeForSearch(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  void _rebuildDerivedState() {
    final grouped = <String, List<BookSummary>>{};
    for (final book in _books) {
      final name = book.groupName?.trim();
      grouped
          .putIfAbsent(
            name == null || name.isEmpty ? '未分组' : name,
            () => <BookSummary>[],
          )
          .add(book);
    }
    final groupNames = grouped.keys.where((name) => name != '未分组').toList()
      ..sort((left, right) => left.compareTo(right));
    _groupNames = List<String>.unmodifiable(groupNames);
    _groupedBooks = Map<String, List<BookSummary>>.unmodifiable({
      for (final entry in grouped.entries)
        entry.key: List<BookSummary>.unmodifiable(entry.value),
    });
    _filterOptions = List<BookshelfFilterOption>.unmodifiable([
      const BookshelfFilterOption(key: bookshelfFilterAll, label: '全部书籍'),
      const BookshelfFilterOption(key: bookshelfFilterRead, label: '已读书籍'),
      const BookshelfFilterOption(key: bookshelfFilterUnread, label: '未读书籍'),
      ...groupNames.map(
        (group) => BookshelfFilterOption(
          key: '$_bookshelfFilterGroupPrefix$group',
          label: '分类 · $group',
        ),
      ),
    ]);
    _progressByBookId = Map<int, ReadingProgressView>.unmodifiable({
      for (final progress in _readingProgresses) progress.bookId: progress,
    });
    _searchCorpusByBookId = Map<int, String>.unmodifiable({
      for (final book in _books) book.id: _searchCorpus(book),
    });

    final booksById = {for (final book in _books) book.id: book};
    final lastReadByBook = <int, String>{
      for (final history in _readingHistories)
        history.bookId: history.lastReadAt,
    };
    for (final progress in _readingProgresses) {
      lastReadByBook.putIfAbsent(progress.bookId, () => progress.updatedAt);
    }
    final recentEntries = lastReadByBook.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    _recentBooks = List<BookSummary>.unmodifiable(
      recentEntries
          .map((entry) => booksById[entry.key])
          .whereType<BookSummary>()
          .take(10),
    );
    _rebuildFilteredBooks();
  }

  void _rebuildFilteredBooks() {
    _filteredBooks = List<BookSummary>.unmodifiable(
      switch (_selectedFilterKey) {
        bookshelfFilterRead => _books.where((book) => _hasBeenRead(book.id)),
        bookshelfFilterUnread => _books.where((book) => !_hasBeenRead(book.id)),
        final key when key.startsWith(_bookshelfFilterGroupPrefix) =>
          _books.where(
            (book) =>
                book.groupName?.trim() ==
                key.substring(_bookshelfFilterGroupPrefix.length),
          ),
        _ => _books,
      },
    );
  }
}
