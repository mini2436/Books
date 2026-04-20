import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/book_models.dart';
import '../../data/models/sync_models.dart';
import '../../data/services/api_client.dart';
import '../../data/services/offline_queue_service.dart';
import 'annotation_change_notifier.dart';
import '../auth/auth_controller.dart';

final annotationCenterControllerProvider =
    ChangeNotifierProvider<AnnotationCenterController>((ref) {
      return AnnotationCenterController(
        authController: ref.read(authControllerProvider),
        apiClient: ref.watch(apiClientProvider),
        offlineQueueService: ref.watch(offlineQueueServiceProvider),
        annotationChangeNotifier: ref.read(annotationChangeNotifierProvider),
      );
    });

class AnnotationCenterEntry {
  const AnnotationCenterEntry({
    required this.annotation,
    required this.book,
  });

  final AnnotationView annotation;
  final BookSummary book;
}

class AnnotationCenterController extends ChangeNotifier {
  AnnotationCenterController({
    required AuthController authController,
    required ApiClient apiClient,
    required OfflineQueueService offlineQueueService,
    required AnnotationChangeNotifier annotationChangeNotifier,
  }) : _authController = authController,
       _apiClient = apiClient,
       _offlineQueueService = offlineQueueService,
       _annotationChangeNotifier = annotationChangeNotifier {
    _authController.addListener(_handleAuthChanged);
    _annotationChangeNotifier.addListener(_handleAnnotationChanged);
    _handleAuthChanged();
  }

  final AuthController _authController;
  final ApiClient _apiClient;
  final OfflineQueueService _offlineQueueService;
  final AnnotationChangeNotifier _annotationChangeNotifier;

  List<AnnotationCenterEntry> _entries = const [];
  bool _isLoading = false;
  String? _error;

  List<AnnotationCenterEntry> get entries => _entries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get annotationCount => _entries.length;
  int get bookCount => _entries.map((entry) => entry.book.id).toSet().length;

  Future<void> refresh() async {
    if (!_authController.isAuthenticated) {
      _entries = const [];
      _error = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final books = await _authController.runAuthorized(
        (accessToken) => _apiClient.listMyBooks(accessToken),
      );

      final annotationResults = await Future.wait(
        books.map(
          (book) => _authController.runAuthorized(
            (accessToken) => _apiClient.listAnnotations(accessToken, book.id),
          ),
        ),
      );

      final nextEntries = <AnnotationCenterEntry>[];
      for (var index = 0; index < books.length; index++) {
        final book = books[index];
        final annotations = annotationResults[index];
        for (final annotation in annotations.where((item) => !item.deleted)) {
          nextEntries.add(
            AnnotationCenterEntry(annotation: annotation, book: book),
          );
        }
      }

      nextEntries.sort(
        (left, right) =>
            right.annotation.updatedAt.compareTo(left.annotation.updatedAt),
      );
      _entries = nextEntries;
    } catch (caught) {
      _error = caught.toString();
      _entries = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteAnnotation(AnnotationCenterEntry entry) async {
    final mutation = AnnotationMutation(
      annotationId: entry.annotation.id,
      bookId: entry.book.id,
      action: 'DELETE',
      quoteText: entry.annotation.quoteText,
      noteText: entry.annotation.noteText,
      color: entry.annotation.color,
      anchor: entry.annotation.anchor,
      baseVersion: entry.annotation.version,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    final previousEntries = _entries;
    _entries = _entries
        .where((item) => item.annotation.id != entry.annotation.id)
        .toList();
    notifyListeners();

    try {
      await _authController.runAuthorized(
        (accessToken) => _apiClient.pushSync(
          accessToken,
          SyncPushRequest(annotations: [mutation]),
        ),
      );
      await refresh();
      _annotationChangeNotifier.markChanged();
    } catch (_) {
      _entries = previousEntries;
      notifyListeners();
      await _offlineQueueService.enqueue(
        PendingOperation(
          id: 'annotation-${DateTime.now().microsecondsSinceEpoch}',
          entityType: PendingEntityType.annotation,
          payload: mutation.toJson(),
          createdAt: mutation.updatedAt,
        ),
      );
      _error = '当前离线，删除操作已加入待同步队列';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChanged);
    _annotationChangeNotifier.removeListener(_handleAnnotationChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (_authController.isAuthenticated) {
      unawaited(refresh());
    } else {
      _entries = const [];
      _error = null;
      notifyListeners();
    }
  }

  void _handleAnnotationChanged() {
    if (_authController.isAuthenticated) {
      unawaited(refresh());
    }
  }
}
