class WebOfflineBookStore {
  Future<void> close() async {}

  Future<List<Map<String, Object?>>> listBooks({
    String? serverKey,
    int? userId,
  }) async => const [];

  Future<Map<String, Object?>?> getBook(
    String serverKey,
    int userId,
    int bookId,
  ) async => null;

  Future<void> putBook(Map<String, Object?> row) async {}

  Future<void> updateBook(
    String serverKey,
    int userId,
    int bookId,
    Map<String, Object?> values,
  ) async {}

  Future<void> deleteBook(String serverKey, int userId, int bookId) async {}

  Future<void> putChapter(Map<String, Object?> row) async {}

  Future<Map<String, Object?>?> getChapter(
    String serverKey,
    int userId,
    int bookId,
    int chapterIndex,
  ) async => null;

  Future<void> putResource(Map<String, Object?> row) async {}

  Future<Map<String, Object?>?> getResource(
    String serverKey,
    int userId,
    int bookId,
    String resourceId,
  ) async => null;
}
