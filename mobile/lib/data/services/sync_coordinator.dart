import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/sync_models.dart';
import 'api_client.dart';
import 'offline_queue_service.dart';

typedef AuthorizedRunner =
    Future<T> Function<T>(Future<T> Function(String accessToken) action);

class SyncCoordinator {
  SyncCoordinator({
    required this.apiClient,
    required this.offlineQueueService,
    required this.runAuthorized,
    required this.isAuthenticated,
    required Listenable authListenable,
  }) : _authListenable = authListenable {
    _authListenable.addListener(_handleAuthChanged);
    _subscription = Connectivity().onConnectivityChanged.listen(
      (_) => unawaited(flushPendingOperations()),
    );
  }

  final ApiClient apiClient;
  final OfflineQueueService offlineQueueService;
  final AuthorizedRunner runAuthorized;
  final bool Function() isAuthenticated;
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

    final operations = await offlineQueueService.loadPending();
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

    await runAuthorized(
      (accessToken) => apiClient.pushSync(accessToken, request),
    );
    await offlineQueueService.deleteByIds(
      operations.map((item) => item.id).toList(),
    );
    return operations.length;
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
