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

  List<BookSummary> get books => _books;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get pendingCount => _pendingCount;

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
      final count = await _offlineQueueService.pendingCount();
      _books = nextBooks;
      _pendingCount = count;
    } catch (error) {
      _error = error.toString();
      _books = const [];
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
}
