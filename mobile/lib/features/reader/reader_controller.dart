import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/book_models.dart';
import '../../data/models/sync_models.dart';
import '../../data/services/api_client.dart';
import '../../data/services/offline_queue_service.dart';
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
    required AnnotationChangeNotifier annotationChangeNotifier,
  }) : _authController = authController,
       _apiClient = apiClient,
       _offlineQueueService = offlineQueueService,
       _annotationChangeNotifier = annotationChangeNotifier {
    unawaited(load());
  }

  final int bookId;
  final String? initialAnchor;
  final AuthController _authController;
  final ApiClient _apiClient;
  final OfflineQueueService _offlineQueueService;
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
    notifyListeners();

    try {
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
        final results = await Future.wait([
          loadedAnnotationsFuture,
          loadedBookmarksFuture,
          _authController.runAuthorized(
            (accessToken) => _apiClient.pullSync(accessToken),
          ),
          _authController.runAuthorized(
            (accessToken) => _apiClient.downloadBookFile(accessToken, bookId),
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
        return;
      }

      if (!loadedDetail.supportsStructuredReader) {
        annotations = await loadedAnnotationsFuture;
        bookmarks = await loadedBookmarksFuture;
        return;
      }

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
      currentChapterIndex = await _resolveChapterIndex(initialLocation) ?? 0;
      if (initialLocation != null && initialLocation.isNotEmpty) {
        focusedAnchor = initialLocation;
        _currentVisibleAnchor = AnnotationAnchor.parse(
          initialLocation,
        ).blockAnchor;
        anchorJumpVersion += 1;
      }
      await openChapter(currentChapterIndex, persistProgress: false);
    } catch (caught) {
      error = caught.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
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
        PendingOperation(
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

    notifyListeners();
  }

  Future<void> deleteBookmark(BookmarkView bookmark) async {
    final mutation = BookmarkMutation(
      bookmarkId: bookmark.id > 0 ? bookmark.id : null,
      bookId: bookId,
      action: 'DELETE',
      location: bookmark.location,
      label: bookmark.label,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    final previous = bookmarks;
    bookmarks = bookmarks.where((item) => item.id != bookmark.id).toList();
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
      bookmarks = previous;
      notifyListeners();
      await _offlineQueueService.enqueue(
        PendingOperation(
          id: _localId('bookmark'),
          entityType: PendingEntityType.bookmark,
          payload: mutation.toJson(),
          createdAt: mutation.updatedAt,
        ),
      );
    }
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
    notifyListeners();

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
      await _offlineQueueService.enqueue(
        PendingOperation(
          id: _localId('annotation'),
          entityType: PendingEntityType.annotation,
          payload: mutation.toJson(),
          createdAt: mutation.updatedAt,
        ),
      );
    }
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
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveAnnotation({
    required String quoteText,
    required String? noteText,
    required String anchor,
    required String color,
  }) async {
    final mutation = AnnotationMutation(
      clientTempId: _localId('annotation'),
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
        id: -DateTime.now().millisecondsSinceEpoch,
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
    notifyListeners();

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
      await _offlineQueueService.enqueue(
        PendingOperation(
          id: mutation.clientTempId ?? _localId('annotation'),
          entityType: PendingEntityType.annotation,
          payload: mutation.toJson(),
          createdAt: mutation.updatedAt,
        ),
      );
    }
    notifyListeners();
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
      final chapter = await _authController.runAuthorized(
        (accessToken) =>
            _apiClient.getStructuredChapter(accessToken, bookId, index),
      );
      _chapterCache[index] = chapter;
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
        final bytes = await _authController.runAuthorized(
          (accessToken) =>
              _apiClient.downloadBookResource(accessToken, bookId, resourceId),
        );
        imageResourceBytes[resourceId] = bytes;
        failedImageResourceIds.remove(resourceId);
      } catch (_) {
        failedImageResourceIds.add(resourceId);
      } finally {
        loadingImageResourceIds.remove(resourceId);
        notifyListeners();
      }
    }
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
    final location = currentReadingLocation;
    if (location.isEmpty) {
      return;
    }

    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 900), () async {
      final mutation = ReadingProgressMutation(
        bookId: bookId,
        location: location,
        progressPercent: progressPercent,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );

      try {
        await _authController.runAuthorized(
          (accessToken) =>
              _apiClient.putProgress(accessToken, bookId, mutation),
        );
      } catch (_) {
        await _offlineQueueService.enqueue(
          PendingOperation(
            id: _localId('progress'),
            entityType: PendingEntityType.progress,
            payload: mutation.toJson(),
            createdAt: mutation.updatedAt,
          ),
        );
      }
    });
  }

  String _localId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

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
      updatedAt: updatedAt,
    );
  }
}
