import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/book_models.dart';
import '../../data/models/sync_models.dart';
import '../../data/services/api_client.dart';
import '../../data/services/offline_queue_service.dart';
import '../../data/services/offline_book_cache_service.dart';
import '../annotations/annotation_change_notifier.dart';
import '../auth/auth_controller.dart';
import 'models/annotation_anchor.dart';

enum ReaderInspectorTab { notes, settings }

final readerControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ReaderController, ReaderRouteArgs>(
      (ref, args) => ReaderController(
        bookId: args.bookId,
        initialAnchor: args.initialAnchor,
        authController: ref.read(authControllerProvider),
        apiClient: ref.watch(apiClientProvider),
        offlineQueueService: ref.watch(offlineQueueServiceProvider),
        offlineBookCacheService: ref.watch(offlineBookCacheServiceProvider),
        annotationChangeNotifier: ref.read(annotationChangeNotifierProvider),
      ),
    );

class ReaderRouteArgs {
  const ReaderRouteArgs({required this.bookId, this.initialAnchor});

  final int bookId;
  final String? initialAnchor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderRouteArgs &&
          runtimeType == other.runtimeType &&
          bookId == other.bookId &&
          initialAnchor == other.initialAnchor;

  @override
  int get hashCode => Object.hash(bookId, initialAnchor);
}

enum ReaderChapterOpenPosition { preserve, start, end }

const readerChapterStartMarker = '__reader_chapter_start__';
const readerChapterEndMarker = '__reader_chapter_end__';

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.bookId,
    this.initialAnchor,
    required AuthController authController,
    required ApiClient apiClient,
    required OfflineQueueService offlineQueueService,
    required OfflineBookCacheService offlineBookCacheService,
    required AnnotationChangeNotifier annotationChangeNotifier,
  }) : _authController = authController,
       _apiClient = apiClient,
       _offlineQueueService = offlineQueueService,
       _offlineBookCacheService = offlineBookCacheService,
       _annotationChangeNotifier = annotationChangeNotifier {
    unawaited(load());
  }

  final int bookId;
  final String? initialAnchor;
  final AuthController _authController;
  final ApiClient _apiClient;
  final OfflineQueueService _offlineQueueService;
  final OfflineBookCacheService _offlineBookCacheService;
  final AnnotationChangeNotifier _annotationChangeNotifier;

  BookDetail? detail;
  BookContent? content;
  Uint8List? pdfBytes;
  final Map<int, BookContentChapter> _chapterCache = {};
  final Set<int> _loadingChapters = {};
  final Map<String, Uint8List> imageResourceBytes = {};
  final Set<String> loadingImageResourceIds = {};
  final Set<String> failedImageResourceIds = {};
  List<AnnotationView> annotations = const [];
  List<BookmarkView> bookmarks = const [];
  bool isLoading = true;
  String? initializationStatus;
  double? initializationProgress;
  String? error;
  bool uiVisible = true;
  bool tocVisible = true;
  bool inspectorVisible = true;
  ReaderInspectorTab inspectorTab = ReaderInspectorTab.notes;
  int currentChapterIndex = 0;
  int pdfPageNumber = 1;
  int pdfPageCount = 0;
  String? focusedAnchor;
  int anchorJumpVersion = 0;
  String? _currentVisibleAnchor;
  Timer? _progressTimer;

  bool get isPdf => detail?.isPdf == true;

  bool get isSupported => detail?.supportsStructuredReader == true || isPdf;
  bool get isReadOnlyOffline => _authController.isOfflineGuest;

  BookContentChapter? get currentChapter => _chapterCache[currentChapterIndex];
  bool get hasCurrentLocationBookmark {
    final location = currentReadingLocation;
    if (location.isEmpty) {
      return false;
    }
    return bookmarks.any(
      (bookmark) => !bookmark.deleted && bookmark.location == location,
    );
  }

  String get currentReadingLocation {
    if (isPdf) {
      return _pdfLocation(pdfPageNumber);
    }
    final visibleAnchor = AnnotationAnchor.parse(
      _currentVisibleAnchor ?? '',
    ).blockAnchor;
    if (visibleAnchor.isNotEmpty) {
      return visibleAnchor;
    }
    return currentChapter?.anchor ?? '';
  }

  String get currentReadingLabel => _labelForLocation(currentReadingLocation);

  double get progressPercent {
    if (isPdf) {
      if (pdfPageCount <= 0) {
        return 0;
      }
      return (pdfPageNumber / pdfPageCount) * 100;
    }
    final chapterCount = content?.chapters.length ?? 0;
    if (chapterCount <= 0) {
      return 0;
    }
    final chapter = currentChapter;
    if (chapter == null || chapter.blocks.isEmpty) {
      return (currentChapterIndex / chapterCount) * 100;
    }
    final currentAnchor = AnnotationAnchor.parse(
      currentReadingLocation,
    ).blockAnchor;
    final blockIndex = chapter.blocks.indexWhere(
      (block) => block.anchor == currentAnchor,
    );
    final blockProgress = blockIndex < 0
        ? 0.0
        : (blockIndex + 1) / chapter.blocks.length;
    return ((currentChapterIndex + blockProgress) / chapterCount) * 100;
  }

  bool get isCurrentChapterLoading =>
      _loadingChapters.contains(currentChapterIndex);
  bool get hasPendingChapterLoad => _loadingChapters.isNotEmpty;

  Future<void> load() async {
    isLoading = true;
    error = null;
    initializationStatus = null;
    initializationProgress = null;
    notifyListeners();

    try {
      final userId = _authController.activeUserId;
      final serverKey = _authController.activeServerKey;
      if (_authController.isOfflineMode &&
          userId != null &&
          serverKey != null &&
          await _offlineBookCacheService.isBookCached(
            serverKey,
            userId,
            bookId,
          )) {
        await _loadOffline();
        return;
      }
      if (userId != null &&
          serverKey != null &&
          await _offlineBookCacheService.isBookCached(
            serverKey,
            userId,
            bookId,
          )) {
        await _loadOffline();
        return;
      }
      final loadedDetail = await _authController.runAuthorized(
        (accessToken) => _apiClient.getMyBook(accessToken, bookId),
      );
      detail = loadedDetail;

      final loadedAnnotationsFuture = _authController.runAuthorized(
        (accessToken) => _apiClient.listAnnotations(accessToken, bookId),
      );
      final loadedBookmarksFuture = _authController.runAuthorized(
        (accessToken) => _apiClient.listBookmarks(accessToken, bookId),
      );

      if (loadedDetail.isPdf) {
        _setInitialization('正在初始化阅读…', 0);
        final results = await Future.wait([
          loadedAnnotationsFuture,
          loadedBookmarksFuture,
          _authController.runAuthorized(
            (accessToken) => _apiClient.pullSync(accessToken),
          ),
          _authController.runAuthorized(
            (accessToken) => _apiClient.downloadBookFile(
              accessToken,
              bookId,
              onReceiveProgress: _updatePdfDownloadProgress,
            ),
          ),
        ]);

        annotations =
            (results[0] as List<AnnotationView>)
                .where((item) => !item.deleted)
                .toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        bookmarks =
            (results[1] as List<BookmarkView>)
                .where((item) => !item.deleted)
                .toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final pull = results[2] as SyncPullResponse;
        final progress = pull.progresses
            .cast<ReadingProgressView?>()
            .firstWhere((entry) => entry?.bookId == bookId, orElse: () => null);
        final initialLocation =
            initialAnchor ??
            progress?.location ??
            loadedDetail.manifest?['primaryLocation'] as String?;
        pdfPageCount = loadedDetail.pdfPageCount ?? 0;
        pdfPageNumber = _parsePdfPage(initialLocation) ?? 1;
        pdfBytes = results[3] as Uint8List;
        await _saveInitialCache(
          detail: loadedDetail,
          annotations: annotations,
          bookmarks: bookmarks,
          progress: progress,
          fileBytes: pdfBytes,
        );
        await _persistReaderState(progress: progress);
        _authController.markServerReachable();
        return;
      }

      if (!loadedDetail.supportsStructuredReader) {
        annotations = await loadedAnnotationsFuture;
        bookmarks = await loadedBookmarksFuture;
        return;
      }

      _setInitialization('正在初始化阅读…', 0);
      final results = await Future.wait([
        _authController.runAuthorized(
          (accessToken) => _apiClient.getStructuredContent(accessToken, bookId),
        ),
        loadedAnnotationsFuture,
        loadedBookmarksFuture,
        _authController.runAuthorized(
          (accessToken) => _apiClient.pullSync(accessToken),
        ),
      ]);

      content = results[0] as BookContent;
      annotations =
          (results[1] as List<AnnotationView>)
              .where((item) => !item.deleted)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      bookmarks =
          (results[2] as List<BookmarkView>)
              .where((item) => !item.deleted)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      final pull = results[3] as SyncPullResponse;
      final progress = pull.progresses.cast<ReadingProgressView?>().firstWhere(
        (entry) => entry?.bookId == bookId,
        orElse: () => null,
      );

      final initialLocation = initialAnchor ?? progress?.location;
      await _cacheStructuredBook(
        detail: loadedDetail,
        content: content!,
        annotations: annotations,
        bookmarks: bookmarks,
        progress: progress,
      );
      currentChapterIndex = await _resolveChapterIndex(initialLocation) ?? 0;
      if (initialLocation != null && initialLocation.isNotEmpty) {
        focusedAnchor = initialLocation;
        _currentVisibleAnchor = AnnotationAnchor.parse(
          initialLocation,
        ).blockAnchor;
        anchorJumpVersion += 1;
      }
      await openChapter(currentChapterIndex, persistProgress: false);
      await _persistReaderState(progress: progress);
      _authController.markServerReachable();
    } catch (caught) {
      if (caught is ApiException && caught.isNetworkFailure) {
        _authController.markServerUnavailable();
      }
      try {
        await _loadOffline();
      } catch (_) {
        error = '无法打开这本书。连接服务器后，请先在书架中下载到本地再重试。';
      }
    } finally {
      isLoading = false;
      initializationStatus = null;
      initializationProgress = null;
      notifyListeners();
    }
  }

  void _setInitialization(String status, double? progress) {
    initializationStatus = status;
    initializationProgress = progress;
    notifyListeners();
  }

  void _updatePdfDownloadProgress(int received, int total) {
    if (total <= 0) {
      _setInitialization('正在初始化阅读…', null);
      return;
    }
    _setInitialization('正在初始化阅读…', (received / total).clamp(0, 1).toDouble());
  }

  Future<Uint8List?> _downloadCover(int id) async {
    try {
      return await _authController.runAuthorized(
        (token) => _apiClient.downloadBookCover(token, id),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveInitialCache({
    required BookDetail detail,
    required List<AnnotationView> annotations,
    required List<BookmarkView> bookmarks,
    required ReadingProgressView? progress,
    Uint8List? fileBytes,
    BookContent? content,
    int additionalSizeBytes = 0,
  }) async {
    final userId = _authController.activeUserId;
    final serverKey = _authController.activeServerKey;
    if (userId == null || serverKey == null) return;
    final coverBytes = await _downloadCover(bookId);
    await _offlineBookCacheService.saveDownloadedBook(
      serverKey: serverKey,
      userId: userId,
      summary: detail,
      detail: detail,
      content: content,
      annotations: annotations,
      bookmarks: bookmarks,
      progress: progress,
      fileBytes: fileBytes,
      coverBytes: coverBytes,
      sizeBytes:
          (fileBytes?.length ?? 0) +
          (coverBytes?.length ?? 0) +
          additionalSizeBytes,
    );
  }

  Future<void> _cacheStructuredBook({
    required BookDetail detail,
    required BookContent content,
    required List<AnnotationView> annotations,
    required List<BookmarkView> bookmarks,
    required ReadingProgressView? progress,
  }) async {
    final userId = _authController.activeUserId;
    final serverKey = _authController.activeServerKey;
    if (userId == null || serverKey == null) return;

    var sizeBytes = utf8.encode(jsonEncode(content.toJson())).length;
    final resourceIds = <String>{};
    try {
      for (var index = 0; index < content.chapters.length; index++) {
        _setInitialization(
          '正在初始化阅读（${index + 1}/${content.chapters.length}）',
          content.chapters.isEmpty ? 1 : index / content.chapters.length,
        );
        final summary = content.chapters[index];
        final chapter = await _authController.runAuthorized(
          (token) => _apiClient.getStructuredChapter(
            token,
            bookId,
            summary.chapterIndex,
          ),
        );
        _chapterCache[summary.chapterIndex] = chapter;
        await _offlineBookCacheService.saveChapter(
          serverKey,
          userId,
          bookId,
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
      final resources = resourceIds.toList();
      for (var index = 0; index < resources.length; index++) {
        _setInitialization(
          '正在缓存插图（${index + 1}/${resources.length}）',
          resources.isEmpty ? 1 : index / resources.length,
        );
        final resourceId = resources[index];
        final bytes = await _authController.runAuthorized(
          (token) => _apiClient.downloadBookResource(token, bookId, resourceId),
        );
        await _offlineBookCacheService.saveResource(
          serverKey,
          userId,
          bookId,
          resourceId,
          bytes,
        );
        sizeBytes += bytes.length;
      }
      _setInitialization('正在保存到本地…', 1);
      await _saveInitialCache(
        detail: detail,
        content: content,
        annotations: annotations,
        bookmarks: bookmarks,
        progress: progress,
        additionalSizeBytes: sizeBytes,
      );
    } catch (_) {
      await _offlineBookCacheService.deleteBook(serverKey, userId, bookId);
      rethrow;
    }
  }

  Future<void> _loadOffline() async {
    final userId = _authController.activeUserId;
    final serverKey = _authController.activeServerKey;
    if (userId == null || serverKey == null) {
      throw StateError('没有可用的本地用户');
    }
    final loadedDetail = await _offlineBookCacheService.loadDetail(
      serverKey,
      userId,
      bookId,
    );
    if (loadedDetail == null) throw StateError('书籍未下载');
    detail = loadedDetail;
    annotations = await _offlineBookCacheService.loadAnnotations(
      serverKey,
      userId,
      bookId,
    );
    annotations = [...annotations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    bookmarks = await _offlineBookCacheService.loadBookmarks(
      serverKey,
      userId,
      bookId,
    );
    bookmarks = [...bookmarks]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final progress = await _offlineBookCacheService.loadProgress(
      serverKey,
      userId,
      bookId,
    );

    if (loadedDetail.isPdf) {
      pdfBytes = await _offlineBookCacheService.loadFile(
        serverKey,
        userId,
        bookId,
      );
      if (pdfBytes == null) throw StateError('离线 PDF 文件不完整');
      pdfPageCount = loadedDetail.pdfPageCount ?? 0;
      final initialLocation =
          initialAnchor ??
          progress?.location ??
          loadedDetail.manifest?['primaryLocation'] as String?;
      pdfPageNumber = _parsePdfPage(initialLocation) ?? 1;
      return;
    }

    content = await _offlineBookCacheService.loadContent(
      serverKey,
      userId,
      bookId,
    );
    if (content == null || !loadedDetail.supportsStructuredReader) {
      throw StateError('离线章节数据不完整');
    }
    final initialLocation = initialAnchor ?? progress?.location;
    currentChapterIndex = await _resolveChapterIndex(initialLocation) ?? 0;
    if (initialLocation != null && initialLocation.isNotEmpty) {
      focusedAnchor = initialLocation;
      _currentVisibleAnchor = AnnotationAnchor.parse(
        initialLocation,
      ).blockAnchor;
      anchorJumpVersion += 1;
    }
    await openChapter(currentChapterIndex, persistProgress: false);
  }

  Future<void> openChapter(
    int chapterIndex, {
    bool persistProgress = true,
    ReaderChapterOpenPosition position = ReaderChapterOpenPosition.preserve,
  }) async {
    final summaries = content?.chapters ?? const [];
    if (chapterIndex < 0 || chapterIndex >= summaries.length) {
      return;
    }

    await _fetchChapter(chapterIndex);
    currentChapterIndex = chapterIndex;
    final chapter = currentChapter;
    final targetAnchor = switch (position) {
      ReaderChapterOpenPosition.preserve => null,
      ReaderChapterOpenPosition.start => readerChapterStartMarker,
      ReaderChapterOpenPosition.end => readerChapterEndMarker,
    };
    if (position == ReaderChapterOpenPosition.start) {
      _currentVisibleAnchor = _firstReadableAnchor(chapter);
    } else if (position == ReaderChapterOpenPosition.end) {
      _currentVisibleAnchor = _lastReadableAnchor(chapter);
    } else if (chapter != null &&
        !_chapterContainsAnchor(chapter, currentReadingLocation)) {
      _currentVisibleAnchor = _firstReadableAnchor(chapter);
    }
    if (targetAnchor == null) {
      notifyListeners();
    }
    if (targetAnchor != null) {
      focusedAnchor = targetAnchor;
      anchorJumpVersion += 1;
      notifyListeners();
    }
    _pruneImageCache();
    unawaited(_prefetchNeighbors(chapterIndex));

    if (persistProgress) {
      _scheduleProgressWrite();
    }
  }

  Future<void> nextChapter() => openChapter(currentChapterIndex + 1);

  Future<void> previousChapter() => openChapter(currentChapterIndex - 1);

  void updatePdfPage({required int pageNumber, int? pageCount}) {
    if (!isPdf) {
      return;
    }
    final nextPageCount = pageCount ?? pdfPageCount;
    final boundedPage = _boundPdfPage(pageNumber, nextPageCount);
    final changed =
        boundedPage != pdfPageNumber || nextPageCount != pdfPageCount;
    pdfPageNumber = boundedPage;
    pdfPageCount = nextPageCount;
    if (!changed) {
      return;
    }
    notifyListeners();
    _scheduleProgressWrite();
  }

  void nextPdfPage() {
    if (!isPdf) {
      return;
    }
    updatePdfPage(pageNumber: pdfPageNumber + 1);
  }

  void previousPdfPage() {
    if (!isPdf) {
      return;
    }
    updatePdfPage(pageNumber: pdfPageNumber - 1);
  }

  Future<void> nextChapterFromPageBoundary() => openChapter(
    currentChapterIndex + 1,
    position: ReaderChapterOpenPosition.start,
  );

  Future<void> previousChapterFromPageBoundary() => openChapter(
    currentChapterIndex - 1,
    position: ReaderChapterOpenPosition.end,
  );

  Future<void> jumpToAnchor(String anchor) async {
    if (isPdf) {
      final page = _parsePdfPage(anchor);
      if (page == null) {
        return;
      }
      updatePdfPage(pageNumber: page);
      return;
    }

    final chapterIndex = await _resolveChapterIndex(anchor);
    if (chapterIndex == null) {
      return;
    }
    _currentVisibleAnchor = AnnotationAnchor.parse(anchor).blockAnchor;
    focusedAnchor = anchor;
    anchorJumpVersion += 1;
    notifyListeners();
    await openChapter(chapterIndex);
  }

  Future<void> addBookmark() async {
    if (isReadOnlyOffline) return;
    final location = currentReadingLocation;
    if (location.isEmpty) {
      return;
    }
    if (hasCurrentLocationBookmark) {
      return;
    }

    final mutation = BookmarkMutation(
      bookId: bookId,
      action: 'CREATE',
      location: location,
      label: _labelForLocation(location),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await _authController.runAuthorized(
        (accessToken) => _apiClient.pushSync(
          accessToken,
          SyncPushRequest(bookmarks: [mutation]),
        ),
      );
      bookmarks = [
        BookmarkView(
          id: DateTime.now().millisecondsSinceEpoch,
          bookId: bookId,
          location: location,
          label: mutation.label,
          deleted: false,
          updatedAt: mutation.updatedAt,
        ),
        ...bookmarks,
      ];
    } catch (_) {
      await _offlineQueueService.enqueue(
        _pendingOperation(
          id: _localId('bookmark'),
          entityType: PendingEntityType.bookmark,
          payload: mutation.toJson(),
          createdAt: mutation.updatedAt,
        ),
      );
      bookmarks = [
        BookmarkView(
          id: -DateTime.now().millisecondsSinceEpoch,
          bookId: bookId,
          location: location,
          label: mutation.label,
          deleted: false,
          updatedAt: mutation.updatedAt,
        ),
        ...bookmarks,
      ];
    }

    await _persistReaderState();
    notifyListeners();
  }

  Future<void> deleteBookmark(BookmarkView bookmark) async {
    if (isReadOnlyOffline) return;
    final mutation = BookmarkMutation(
      bookmarkId: bookmark.id > 0 ? bookmark.id : null,
      bookId: bookId,
      action: 'DELETE',
      location: bookmark.location,
      label: bookmark.label,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    bookmarks = bookmarks.where((item) => item.id != bookmark.id).toList();
    await _persistReaderState();
    notifyListeners();

    try {
      await _authController.runAuthorized(
        (accessToken) => _apiClient.pushSync(
          accessToken,
          SyncPushRequest(bookmarks: [mutation]),
        ),
      );
      await _refreshBookmarks();
    } catch (_) {
      await _offlineQueueService.enqueue(
        _pendingOperation(
          id: _localId('bookmark'),
          entityType: PendingEntityType.bookmark,
          payload: mutation.toJson(),
          createdAt: mutation.updatedAt,
        ),
      );
    }
    await _persistReaderState();
  }

  Future<void> addHighlight({
    required AnnotationSelection selection,
    String color = '#C3924A',
    AnnotationUnderlineStyle underlineStyle = AnnotationUnderlineStyle.none,
  }) async {
    await _saveAnnotation(
      quoteText: selection.selectedText,
      noteText: null,
      anchor: selection.toAnchorString(underlineStyle: underlineStyle),
      color: color,
    );
  }

  Future<void> addAnnotation({
    required AnnotationSelection selection,
    required String? noteText,
    required String color,
    required AnnotationUnderlineStyle underlineStyle,
  }) async {
    await _saveAnnotation(
      quoteText: selection.selectedText,
      noteText: noteText,
      anchor: selection.toAnchorString(underlineStyle: underlineStyle),
      color: color,
    );
  }

  Future<void> updateAnnotation({
    required AnnotationView annotation,
    required String? noteText,
    required String color,
    AnnotationSelection? selection,
    AnnotationUnderlineStyle? underlineStyle,
  }) async {
    final currentAnchor = AnnotationAnchor.parse(annotation.anchor);
    final nextUnderlineStyle = underlineStyle ?? currentAnchor.underlineStyle;
    final nextQuoteText = selection?.selectedText ?? annotation.quoteText;
    final nextAnchor =
        selection?.toAnchorString(underlineStyle: nextUnderlineStyle) ??
        currentAnchor.copyWith(underlineStyle: nextUnderlineStyle).serialize();
    final mutation = AnnotationMutation(
      annotationId: annotation.id,
      bookId: bookId,
      action: 'UPDATE',
      quoteText: nextQuoteText,
      noteText: noteText,
      color: color,
      anchor: nextAnchor,
      baseVersion: annotation.version,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    await _pushAnnotationMutation(
      mutation: mutation,
      optimistic: annotation.copyWith(
        quoteText: nextQuoteText,
        noteText: noteText,
        color: color,
        anchor: nextAnchor,
        updatedAt: mutation.updatedAt,
      ),
    );
  }

  Future<void> deleteAnnotation(AnnotationView annotation) async {
    final mutation = AnnotationMutation(
      annotationId: annotation.id,
      bookId: bookId,
      action: 'DELETE',
      quoteText: annotation.quoteText,
      noteText: annotation.noteText,
      color: annotation.color,
      anchor: annotation.anchor,
      baseVersion: annotation.version,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    annotations = annotations
        .where((item) => item.id != annotation.id)
        .toList();
    await _persistReaderState();
    notifyListeners();

    if (_authController.isOfflineGuest) {
      await _enqueueAnnotationMutation(mutation);
      _annotationChangeNotifier.markChanged();
      return;
    }

    try {
      await _authController.runAuthorized(
        (accessToken) => _apiClient.pushSync(
          accessToken,
          SyncPushRequest(annotations: [mutation]),
        ),
      );
      final refreshed = await _authController.runAuthorized(
        (accessToken) => _apiClient.listAnnotations(accessToken, bookId),
      );
      annotations = refreshed.where((item) => !item.deleted).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _annotationChangeNotifier.markChanged();
    } catch (_) {
      await _enqueueAnnotationMutation(mutation);
    }
    await _persistReaderState();
  }

  void toggleUi() {
    uiVisible = !uiVisible;
    notifyListeners();
  }

  void setUiVisible(bool value) {
    if (uiVisible == value) {
      return;
    }
    uiVisible = value;
    notifyListeners();
  }

  void toggleToc() {
    tocVisible = !tocVisible;
    notifyListeners();
  }

  void toggleInspector() {
    inspectorVisible = !inspectorVisible;
    notifyListeners();
  }

  void setInspectorTab(ReaderInspectorTab tab) {
    inspectorTab = tab;
    notifyListeners();
  }

  void updateVisibleAnchor(String anchor) {
    final parsedAnchor = AnnotationAnchor.parse(anchor).blockAnchor;
    final chapter = currentChapter;
    if (parsedAnchor.isEmpty ||
        chapter == null ||
        !_chapterContainsAnchor(chapter, parsedAnchor) ||
        parsedAnchor == _currentVisibleAnchor) {
      return;
    }

    _currentVisibleAnchor = parsedAnchor;
    notifyListeners();
    _scheduleProgressWrite();
  }

  @override
  void dispose() {
    final hasPendingProgress = _progressTimer?.isActive ?? false;
    _progressTimer?.cancel();
    _progressTimer = null;
    if (hasPendingProgress) {
      unawaited(_writeCurrentProgress());
    }
    super.dispose();
  }

  Future<void> _saveAnnotation({
    required String quoteText,
    required String? noteText,
    required String anchor,
    required String color,
  }) async {
    final localAnnotationId = -DateTime.now().microsecondsSinceEpoch;
    final mutation = AnnotationMutation(
      clientTempId: annotationClientTempIdForLocalId(localAnnotationId),
      bookId: bookId,
      action: 'CREATE',
      quoteText: quoteText,
      noteText: noteText,
      color: color,
      anchor: anchor,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    await _pushAnnotationMutation(
      mutation: mutation,
      optimistic: AnnotationView(
        id: localAnnotationId,
        bookId: bookId,
        quoteText: quoteText,
        noteText: noteText,
        color: color,
        anchor: anchor,
        version: 0,
        deleted: false,
        updatedAt: mutation.updatedAt,
      ),
    );
  }

  Future<void> _pushAnnotationMutation({
    required AnnotationMutation mutation,
    required AnnotationView optimistic,
  }) async {
    annotations = [
      optimistic,
      ...annotations.where((item) => item.id != optimistic.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _persistReaderState();
    notifyListeners();

    if (_authController.isOfflineGuest) {
      await _enqueueAnnotationMutation(mutation);
      _annotationChangeNotifier.markChanged();
      await _persistReaderState();
      notifyListeners();
      return;
    }

    try {
      await _authController.runAuthorized(
        (accessToken) => _apiClient.pushSync(
          accessToken,
          SyncPushRequest(annotations: [mutation]),
        ),
      );
      final refreshed = await _authController.runAuthorized(
        (accessToken) => _apiClient.listAnnotations(accessToken, bookId),
      );
      annotations = refreshed.where((item) => !item.deleted).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _annotationChangeNotifier.markChanged();
    } catch (_) {
      await _enqueueAnnotationMutation(mutation);
    }
    await _persistReaderState();
    notifyListeners();
  }

  Future<void> _enqueueAnnotationMutation(AnnotationMutation mutation) async {
    final annotationId = mutation.annotationId;
    if (annotationId != null && annotationId < 0) {
      final clientTempId = annotationClientTempIdForLocalId(annotationId);
      if (mutation.action.toUpperCase() == 'DELETE') {
        await _offlineQueueService.deleteByIds([clientTempId]);
        return;
      }
      final createMutation = AnnotationMutation(
        clientTempId: clientTempId,
        bookId: mutation.bookId,
        action: 'CREATE',
        quoteText: mutation.quoteText,
        noteText: mutation.noteText,
        color: mutation.color,
        anchor: mutation.anchor,
        updatedAt: mutation.updatedAt,
      );
      await _offlineQueueService.enqueue(
        _pendingOperation(
          id: clientTempId,
          entityType: PendingEntityType.annotation,
          payload: createMutation.toJson(),
          createdAt: createMutation.updatedAt,
        ),
      );
      return;
    }

    await _offlineQueueService.enqueue(
      _pendingOperation(
        id: mutation.clientTempId ?? _localId('annotation'),
        entityType: PendingEntityType.annotation,
        payload: mutation.toJson(),
        createdAt: mutation.updatedAt,
      ),
    );
  }

  Future<BookContentChapter> _fetchChapter(int index) async {
    final cached = _chapterCache[index];
    if (cached != null) {
      unawaited(_prefetchImageResources(cached));
      return cached;
    }

    _loadingChapters.add(index);
    notifyListeners();
    try {
      final userId = _authController.activeUserId;
      final serverKey = _authController.activeServerKey;
      if (userId != null && serverKey != null) {
        final local = await _offlineBookCacheService.loadChapter(
          serverKey,
          userId,
          bookId,
          index,
        );
        if (local != null) {
          _chapterCache[index] = local;
          unawaited(_prefetchImageResources(local));
          return local;
        }
      }
      final chapter = await _authController.runAuthorized(
        (accessToken) =>
            _apiClient.getStructuredChapter(accessToken, bookId, index),
      );
      _chapterCache[index] = chapter;
      if (userId != null &&
          serverKey != null &&
          await _offlineBookCacheService.isBookCached(
            serverKey,
            userId,
            bookId,
          )) {
        await _offlineBookCacheService.saveChapter(
          serverKey,
          userId,
          bookId,
          chapter,
        );
      }
      unawaited(_prefetchImageResources(chapter));
      return chapter;
    } finally {
      _loadingChapters.remove(index);
      notifyListeners();
    }
  }

  Future<int?> _resolveChapterIndex(String? anchor) async {
    final parsedAnchor = AnnotationAnchor.parse(anchor ?? '');
    final targetAnchor = parsedAnchor.blockAnchor;
    if (targetAnchor.isEmpty) {
      return 0;
    }

    final chapters = content?.chapters ?? const [];
    final directMatch = chapters.indexWhere(
      (chapter) => chapter.anchor == targetAnchor,
    );
    if (directMatch >= 0) {
      return directMatch;
    }

    for (final entry in _chapterCache.entries) {
      if (_chapterContainsAnchor(entry.value, targetAnchor)) {
        return entry.key;
      }
    }

    for (final summary in chapters) {
      final chapter = await _fetchChapter(summary.chapterIndex);
      if (_chapterContainsAnchor(chapter, targetAnchor)) {
        return summary.chapterIndex;
      }
    }

    return 0;
  }

  bool _chapterContainsAnchor(BookContentChapter chapter, String anchor) {
    if (chapter.anchor == anchor) {
      return true;
    }
    return chapter.blocks.any((block) => block.anchor == anchor);
  }

  Future<void> _prefetchNeighbors(int chapterIndex) async {
    final targets = [chapterIndex - 1, chapterIndex + 1];
    for (final index in targets) {
      if (index < 0 || index >= (content?.chapters.length ?? 0)) {
        continue;
      }
      await _fetchChapter(index);
    }
  }

  Future<void> _prefetchImageResources(BookContentChapter chapter) async {
    final resourceIds = chapter.blocks
        .where((block) => block.isImage)
        .map((block) => block.resourceId)
        .whereType<String>()
        .where((resourceId) => resourceId.isNotEmpty)
        .toSet();
    if (resourceIds.isEmpty) {
      return;
    }

    for (final resourceId in resourceIds) {
      if (imageResourceBytes.containsKey(resourceId) ||
          loadingImageResourceIds.contains(resourceId) ||
          failedImageResourceIds.contains(resourceId)) {
        continue;
      }
      loadingImageResourceIds.add(resourceId);
      notifyListeners();
      try {
        final userId = _authController.activeUserId;
        final serverKey = _authController.activeServerKey;
        if (userId != null && serverKey != null) {
          final local = await _offlineBookCacheService.loadResource(
            serverKey,
            userId,
            bookId,
            resourceId,
          );
          if (local != null) {
            imageResourceBytes[resourceId] = local;
            failedImageResourceIds.remove(resourceId);
            continue;
          }
        }
        final bytes = await _authController.runAuthorized(
          (accessToken) =>
              _apiClient.downloadBookResource(accessToken, bookId, resourceId),
        );
        imageResourceBytes[resourceId] = bytes;
        if (userId != null &&
            serverKey != null &&
            await _offlineBookCacheService.isBookCached(
              serverKey,
              userId,
              bookId,
            )) {
          await _offlineBookCacheService.saveResource(
            serverKey,
            userId,
            bookId,
            resourceId,
            bytes,
          );
        }
        failedImageResourceIds.remove(resourceId);
      } catch (_) {
        failedImageResourceIds.add(resourceId);
      } finally {
        loadingImageResourceIds.remove(resourceId);
        notifyListeners();
      }
    }
  }

  Future<void> retryCurrentChapterImages() async {
    final chapter = currentChapter;
    if (chapter == null) return;
    final resourceIds = chapter.blocks
        .where((block) => block.isImage)
        .map((block) => block.resourceId)
        .whereType<String>()
        .toSet();
    failedImageResourceIds.removeAll(resourceIds);
    notifyListeners();
    await _prefetchImageResources(chapter);
  }

  void _pruneImageCache() {
    final keepChapterIndexes = {
      currentChapterIndex - 1,
      currentChapterIndex,
      currentChapterIndex + 1,
    };
    final keepResourceIds = keepChapterIndexes
        .map((index) => _chapterCache[index])
        .whereType<BookContentChapter>()
        .expand((chapter) => chapter.blocks)
        .where((block) => block.isImage)
        .map((block) => block.resourceId)
        .whereType<String>()
        .toSet();

    imageResourceBytes.removeWhere(
      (resourceId, _) => !keepResourceIds.contains(resourceId),
    );
    failedImageResourceIds.removeWhere(
      (resourceId) => !keepResourceIds.contains(resourceId),
    );
  }

  void _scheduleProgressWrite() {
    if (currentReadingLocation.isEmpty) {
      return;
    }

    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 900), () {
      _progressTimer = null;
      unawaited(_writeCurrentProgress());
    });
  }

  Future<void> flushProgress() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    await _writeCurrentProgress(waitForRemote: false);
  }

  Future<void> _writeCurrentProgress({bool waitForRemote = true}) async {
    final location = currentReadingLocation;
    if (location.isEmpty) return;

    final mutation = ReadingProgressMutation(
      bookId: bookId,
      location: location,
      progressPercent: progressPercent,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    await _persistReaderState(
      progress: ReadingProgressView(
        bookId: bookId,
        location: mutation.location,
        progressPercent: mutation.progressPercent,
        updatedAt: mutation.updatedAt,
      ),
    );

    if (_authController.isOfflineGuest) {
      await _offlineQueueService.enqueue(
        _pendingOperation(
          id: _localId('progress'),
          entityType: PendingEntityType.progress,
          payload: mutation.toJson(),
          createdAt: mutation.updatedAt,
        ),
      );
      return;
    }

    final remoteWrite = _writeProgressToServer(mutation);
    if (waitForRemote) {
      await remoteWrite;
    } else {
      unawaited(remoteWrite);
    }
  }

  Future<void> _writeProgressToServer(ReadingProgressMutation mutation) async {
    try {
      await _authController.runAuthorized(
        (accessToken) => _apiClient.putProgress(accessToken, bookId, mutation),
      );
    } catch (_) {
      await _offlineQueueService.enqueue(
        _pendingOperation(
          id: _localId('progress'),
          entityType: PendingEntityType.progress,
          payload: mutation.toJson(),
          createdAt: mutation.updatedAt,
        ),
      );
    }
  }

  Future<void> _persistReaderState({ReadingProgressView? progress}) async {
    final userId = _authController.activeUserId;
    final serverKey = _authController.activeServerKey;
    if (userId == null || serverKey == null) return;
    await _offlineBookCacheService.saveReaderState(
      serverKey: serverKey,
      userId: userId,
      bookId: bookId,
      annotations: annotations,
      bookmarks: bookmarks,
      progress: progress,
    );
  }

  String _localId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  PendingOperation _pendingOperation({
    required String id,
    required PendingEntityType entityType,
    required Map<String, dynamic> payload,
    required String createdAt,
  }) {
    final serverKey = _authController.activeServerKey;
    final userId = _authController.activeUserId;
    if (serverKey == null || userId == null) {
      throw StateError('无法确定离线操作所属的服务器和用户');
    }
    return PendingOperation(
      id: id,
      serverKey: serverKey,
      userId: userId,
      entityType: entityType,
      payload: payload,
      createdAt: createdAt,
    );
  }

  int _boundPdfPage(int pageNumber, int pageCount) {
    final minimum = pageNumber < 1 ? 1 : pageNumber;
    if (pageCount <= 0) {
      return minimum;
    }
    return minimum > pageCount ? pageCount : minimum;
  }

  int? _parsePdfPage(String? location) {
    if (location == null || location.isEmpty) {
      return null;
    }
    final normalized = location.trim();
    final pageMatch = RegExp(
      r'(?:#page=|pdf-page:|page:)(\d+)',
    ).firstMatch(normalized);
    final raw = pageMatch == null
        ? int.tryParse(normalized)
        : int.tryParse(pageMatch.group(1)!);
    if (raw == null || raw <= 0) {
      return null;
    }
    return _boundPdfPage(raw, pdfPageCount);
  }

  String _pdfLocation(int pageNumber) => '#page=$pageNumber';

  String _firstReadableAnchor(BookContentChapter? chapter) {
    if (chapter == null) {
      return '';
    }
    return chapter.blocks.isEmpty
        ? chapter.anchor
        : chapter.blocks.first.anchor;
  }

  String _lastReadableAnchor(BookContentChapter? chapter) {
    if (chapter == null) {
      return '';
    }
    return chapter.blocks.isEmpty ? chapter.anchor : chapter.blocks.last.anchor;
  }

  String _labelForLocation(String location) {
    if (isPdf) {
      final count = pdfPageCount <= 0 ? '?' : pdfPageCount.toString();
      return '第 $pdfPageNumber / $count 页';
    }
    final chapter = currentChapter;
    if (chapter == null) {
      return location;
    }
    final anchor = AnnotationAnchor.parse(location).blockAnchor;
    final block = chapter.blocks.cast<BookContentBlock?>().firstWhere(
      (item) => item?.anchor == anchor,
      orElse: () => null,
    );
    final excerpt = block?.renderedText.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (excerpt == null || excerpt.isEmpty || anchor == chapter.anchor) {
      return chapter.title;
    }
    final clipped = excerpt.length > 28
        ? '${excerpt.substring(0, 28)}...'
        : excerpt;
    return '${chapter.title} · $clipped';
  }

  Future<void> _refreshBookmarks() async {
    final refreshed = await _authController.runAuthorized(
      (accessToken) => _apiClient.listBookmarks(accessToken, bookId),
    );
    bookmarks = refreshed.where((item) => !item.deleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
  }
}

extension on AnnotationView {
  AnnotationView copyWith({
    String? quoteText,
    String? noteText,
    String? color,
    String? anchor,
    String? updatedAt,
  }) {
    return AnnotationView(
      id: id,
      bookId: bookId,
      quoteText: quoteText ?? this.quoteText,
      noteText: noteText ?? this.noteText,
      color: color ?? this.color,
      anchor: anchor ?? this.anchor,
      version: version,
      deleted: deleted,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
