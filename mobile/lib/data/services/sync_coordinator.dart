import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/sync_models.dart';
import 'api_client.dart';
import 'offline_book_cache_service.dart';
import 'offline_queue_service.dart';

typedef AuthorizedRunner =
    Future<T> Function<T>(Future<T> Function(String accessToken) action);

class SyncCoordinator {
  SyncCoordinator({
    required this.apiClient,
    required this.offlineQueueService,
    required this.offlineBookCacheService,
    required this.runAuthorized,
    required this.isAuthenticated,
    required this.currentServerKey,
    required this.currentUserId,
    required Listenable authListenable,
  }) : _authListenable = authListenable {
    _authListenable.addListener(_handleAuthChanged);
    _subscription = Connectivity().onConnectivityChanged.listen(
      (_) => unawaited(flushPendingOperations()),
    );
  }

  final ApiClient apiClient;
  final OfflineQueueService offlineQueueService;
  final OfflineBookCacheService offlineBookCacheService;
  final AuthorizedRunner runAuthorized;
  final bool Function() isAuthenticated;
  final String? Function() currentServerKey;
  final int? Function() currentUserId;
  final Listenable _authListenable;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<int>? _flushInFlight;

  Future<int> flushPendingOperations() {
    _flushInFlight ??= _flushInternal().whenComplete(() {
      _flushInFlight = null;
    });
    return _flushInFlight!;
  }

  void dispose() {
    _authListenable.removeListener(_handleAuthChanged);
    _subscription?.cancel();
  }

  void _handleAuthChanged() {
    if (isAuthenticated()) {
      unawaited(flushPendingOperations());
    }
  }

  Future<int> _flushInternal() async {
    if (!isAuthenticated()) {
      return 0;
    }

    final serverKey = currentServerKey();
    final userId = currentUserId();
    if (serverKey == null || userId == null) {
      return 0;
    }

    final operations = await offlineQueueService.loadPending(
      serverKey: serverKey,
      userId: userId,
    );
    if (operations.isEmpty) {
      return 0;
    }

    final request = _compact(operations);
    final hasPayload =
        request.annotations.isNotEmpty ||
        request.bookmarks.isNotEmpty ||
        request.progresses.isNotEmpty;

    if (!hasPayload) {
      await offlineQueueService.deleteByIds(
        operations.map((item) => item.id).toList(),
      );
      return 0;
    }

    final response = await runAuthorized(
      (accessToken) => apiClient.pushSync(accessToken, request),
    );
    await offlineBookCacheService.applyAnnotationMappings(
      serverKey: serverKey,
      userId: userId,
      mappings: response.annotationMappings,
    );
    final conflictedAnnotationIds = response.conflicts
        .where((conflict) => conflict.entityType == 'annotation')
        .map((conflict) => conflict.entityId)
        .toSet();
    final completedOperationIds = operations
        .where((operation) {
          if (operation.entityType != PendingEntityType.annotation ||
              conflictedAnnotationIds.isEmpty) {
            return true;
          }
          final mutation = AnnotationMutation.fromJson(operation.payload);
          return mutation.annotationId == null ||
              !conflictedAnnotationIds.contains(mutation.annotationId);
        })
        .map((operation) => operation.id)
        .toList();
    await offlineQueueService.deleteByIds(completedOperationIds);
    return completedOperationIds.length;
  }

  SyncPushRequest _compact(List<PendingOperation> operations) {
    final annotations = <AnnotationMutation>[];
    final bookmarks = <BookmarkMutation>[];
    final progressByBook = <int, ReadingProgressMutation>{};

    for (final operation in operations) {
      switch (operation.entityType) {
        case PendingEntityType.annotation:
          annotations.add(AnnotationMutation.fromJson(operation.payload));
        case PendingEntityType.bookmark:
          bookmarks.add(BookmarkMutation.fromJson(operation.payload));
        case PendingEntityType.progress:
          final progress = ReadingProgressMutation.fromJson(operation.payload);
          progressByBook[progress.bookId] = progress;
      }
    }

    return SyncPushRequest(
      annotations: annotations,
      bookmarks: bookmarks,
      progresses: progressByBook.values.toList(),
    );
  }
}
