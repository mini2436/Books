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
  final Map<int, BookContentChapter> _chapterCache = {};
  final Set<int> _loadingChapters = {};
  List<AnnotationView> annotations = const [];
  List<BookmarkView> bookmarks = const [];
  bool isLoading = true;
  String? error;
  bool uiVisible = true;
  bool tocVisible = true;
  bool inspectorVisible = true;
  ReaderInspectorTab inspectorTab = ReaderInspectorTab.notes;
  int currentChapterIndex = 0;
  String? focusedAnchor;
  int anchorJumpVersion = 0;
  Timer? _progressTimer;

  bool get isSupported => detail?.supportsStructuredReader == true;

  BookContentChapter? get currentChapter => _chapterCache[currentChapterIndex];

  double get progressPercent {
    final chapterCount = content?.chapters.length ?? 0;
    if (chapterCount <= 1) {
      return 0;
    }
    return ((currentChapterIndex + 1) / chapterCount) * 100;
  }

  bool get isCurrentChapterLoading =>
      _loadingChapters.contains(currentChapterIndex);

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
  }) async {
    final summaries = content?.chapters ?? const [];
    if (chapterIndex < 0 || chapterIndex >= summaries.length) {
      return;
    }

    currentChapterIndex = chapterIndex;
    notifyListeners();

    await _fetchChapter(chapterIndex);
    unawaited(_prefetchNeighbors(chapterIndex));

    if (persistProgress) {
      _scheduleProgressWrite();
    }
  }

  Future<void> nextChapter() => openChapter(currentChapterIndex + 1);

  Future<void> previousChapter() => openChapter(currentChapterIndex - 1);

  Future<void> jumpToAnchor(String anchor) async {
    final chapterIndex = await _resolveChapterIndex(anchor);
    if (chapterIndex == null) {
      return;
    }
    focusedAnchor = anchor;
    anchorJumpVersion += 1;
    notifyListeners();
    await openChapter(chapterIndex);
  }

  Future<void> addBookmark() async {
    final chapter = currentChapter;
    if (chapter == null) {
      return;
    }

    final mutation = BookmarkMutation(
      bookId: bookId,
      action: 'CREATE',
      location: chapter.anchor,
      label: chapter.title,
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
          location: chapter.anchor,
          label: chapter.title,
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
          location: chapter.anchor,
          label: chapter.title,
          deleted: false,
          updatedAt: mutation.updatedAt,
        ),
        ...bookmarks,
      ];
    }

    notifyListeners();
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

  void _scheduleProgressWrite() {
    final chapter = currentChapter;
    if (chapter == null) {
      return;
    }

    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 900), () async {
      final mutation = ReadingProgressMutation(
        bookId: bookId,
        location: chapter.anchor,
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
