import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/book_models.dart';
import '../../data/models/sync_models.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import '../../shared/widgets/centered_scale_dialog.dart';
import '../../shared/widgets/glass_segmented_control.dart';
import '../../shared/widgets/glass_dialog.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/theme/glass_theme.dart';
import '../auth/auth_controller.dart';
import 'bookshelf_controller.dart';

enum _ShelfView { all, groups }

class BookshelfScreen extends ConsumerStatefulWidget {
  const BookshelfScreen({super.key});

  @override
  ConsumerState<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends ConsumerState<BookshelfScreen>
    with SingleTickerProviderStateMixin {
  _ShelfView _view = _ShelfView.all;
  late final AnimationController _contentTransitionController;
  late final Animation<double> _contentFadeAnimation;
  late final Animation<Offset> _contentSlideAnimation;

  @override
  void initState() {
    super.initState();
    _contentTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    final curve = CurvedAnimation(
      parent: _contentTransitionController,
      curve: Curves.easeOutCubic,
    );
    _contentFadeAnimation = Tween<double>(begin: 0.35, end: 1).animate(curve);
    _contentSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.018),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void dispose() {
    _contentTransitionController.dispose();
    super.dispose();
  }

  void _restartContentTransition() {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _contentTransitionController.value = 1;
      return;
    }
    _contentTransitionController.forward(from: 0);
  }

  void _selectShelfView(_ShelfView view) {
    if (_view == view) return;
    setState(() => _view = view);
    _restartContentTransition();
  }

  void _selectBookFilter(BookshelfController controller, String filter) {
    if (controller.selectedFilterKey == filter) return;
    controller.setFilter(filter);
    _restartContentTransition();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(bookshelfControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final isOfflineGuest = auth.isOfflineGuest;
    final palette = AppReaderPalette.of(context);
    final accessToken = auth.accessToken;
    final apiClient = ref.read(apiClientProvider);
    final horizontalPadding = Responsive.usesWideLayout(context) ? 28.0 : 16.0;

    String? coverUrl(BookSummary book) => accessToken == null
        ? null
        : apiClient.buildUrl('/api/me/books/${book.id}/cover');
    final coverHeaders = accessToken == null
        ? null
        : apiClient.coverHeaders(accessToken);
    final avatarVersion = auth.user?.avatarVersion;
    final avatarUrl = auth.user?.hasAvatar == true && accessToken != null
        ? apiClient.buildUrl(
            avatarVersion == null
                ? '/api/me/profile/avatar'
                : '/api/me/profile/avatar?v=${Uri.encodeQueryComponent(avatarVersion)}',
          )
        : null;
    final motionDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final mobileSegmentStyle = Responsive.usesWideLayout(context)
        ? null
        : const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 52)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
          );
    final showFilters =
        _view == _ShelfView.all && controller.filterOptions.length > 1;
    final selectedFilter = controller.filterOptions.firstWhere(
      (option) => option.key == controller.selectedFilterKey,
    );
    final selectedFilterTitle = selectedFilter.label.replaceAll(' · ', '');

    final Widget shelfContent;
    if (controller.isLoading && controller.books.isEmpty) {
      shelfContent = const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (controller.error != null && controller.books.isEmpty) {
      shelfContent = SliverFillRemaining(
        hasScrollBody: false,
        child: _BookshelfEmptyState(
          message: controller.error!,
          onRetry: controller.isLoading ? null : controller.refresh,
        ),
      );
    } else if (controller.books.isEmpty) {
      shelfContent = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            isOfflineGuest
                ? '本机没有可阅读的离线书籍。\n返回登录后，可将书籍下载到本地再离线使用。'
                : '书架空空如也，先从后台导入一本书吧。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: palette.inkSecondary),
          ),
        ),
      );
    } else if (_view == _ShelfView.all) {
      shelfContent = controller.filteredBooks.isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '当前筛选下没有书籍',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: palette.inkSecondary),
                ),
              ),
            )
          : _buildBookGrid(
              context,
              controller: controller,
              books: controller.filteredBooks,
              horizontalPadding: horizontalPadding,
              coverUrl: coverUrl,
              coverHeaders: coverHeaders,
            );
    } else {
      shelfContent = _buildGroupGrid(
        context,
        controller: controller,
        groups: controller.groupedBooks,
        horizontalPadding: horizontalPadding,
        coverUrl: coverUrl,
        coverHeaders: coverHeaders,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    Responsive.usesWideLayout(context) ? 22 : 16,
                    horizontalPadding,
                    12,
                  ),
                  child: _ShelfHeader(
                    initials: isOfflineGuest
                        ? '离'
                        : auth.user?.initials ?? 'PR',
                    avatarUrl: avatarUrl,
                    avatarHeaders: coverHeaders,
                    bookCount: controller.books.length,
                    pendingCount: controller.pendingCount,
                    offlineBookCount: controller.offlineBookCount,
                    isOfflineMode: controller.isOfflineMode,
                    isOfflineGuest: isOfflineGuest,
                    isLoading: controller.isLoading,
                    onSearch: () => context.push('/search'),
                    onRefresh: controller.refresh,
                  ),
                ),
              ),
              if (isOfflineGuest)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      14,
                    ),
                    child: _OfflineGuestBanner(onLogin: auth.exitOfflineMode),
                  ),
                ),
              if (controller.error != null && controller.books.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      14,
                    ),
                    child: _BookshelfErrorBanner(
                      message: controller.error!,
                      onRetry: controller.isLoading ? null : controller.refresh,
                    ),
                  ),
                ),
              if (controller.recentBooks.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8,
                      horizontalPadding,
                      10,
                    ),
                    child: _SectionHeading(
                      title: '最近阅读',
                      detail: '${controller.recentBooks.length} 本',
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 154,
                    child: ListView.separated(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: controller.recentBooks.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        final book = controller.recentBooks[index];
                        return _RecentBookItem(
                          book: book,
                          progress: controller.progressFor(book.id),
                          imageUrl: coverUrl(book),
                          imageBytes: controller.offlineCoverForBook(book.id),
                          headers: coverHeaders,
                          heroTag: 'book-cover-recent-${book.id}',
                          frameHeroTag: 'book-frame-recent-${book.id}',
                          onTap: () => _showBookDetails(
                            context,
                            book: book,
                            controller: controller,
                            imageUrl: coverUrl(book),
                            imageBytes: controller.offlineCoverForBook(book.id),
                            headers: coverHeaders,
                            heroTag: 'book-cover-recent-${book.id}',
                            frameHeroTag: 'book-frame-recent-${book.id}',
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    controller.recentBooks.isEmpty ? 10 : 24,
                    horizontalPadding,
                    14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: motionDuration,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.centerLeft,
                                children: [...previousChildren, ?currentChild],
                              ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.12),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: KeyedSubtree(
                            key: ValueKey((
                              _view,
                              controller.selectedFilterKey,
                            )),
                            child: _SectionHeading(
                              title: _view == _ShelfView.all
                                  ? selectedFilterTitle
                                  : '书籍分组',
                              detail: _view == _ShelfView.all
                                  ? controller.selectedFilterKey ==
                                            bookshelfFilterAll
                                        ? '${controller.books.length} 本'
                                        : '${controller.filteredBooks.length}/${controller.books.length} 本'
                                  : '${controller.groupedBooks.length} 个分组',
                            ),
                          ),
                        ),
                      ),
                      GlassSegmentedControl<_ShelfView>(
                        style: mobileSegmentStyle,
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _ShelfView.all,
                            icon: Icon(Icons.grid_view_rounded, size: 18),
                            label: Text('全部'),
                          ),
                          ButtonSegment(
                            value: _ShelfView.groups,
                            icon: Icon(Icons.folder_copy_outlined, size: 18),
                            label: Text('分组'),
                          ),
                        ],
                        selected: {_view},
                        onSelectionChanged: (value) =>
                            _selectShelfView(value.first),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: motionDuration,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: showFilters
                      ? Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            0,
                            horizontalPadding,
                            18,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isPrimaryFilterSet =
                                  controller.filterOptions.length == 3;
                              final selector = GlassSegmentedControl<String>(
                                style: mobileSegmentStyle,
                                showSelectedIcon: false,
                                expandedInsets: isPrimaryFilterSet
                                    ? EdgeInsets.zero
                                    : null,
                                segments: controller.filterOptions
                                    .map(
                                      (option) => ButtonSegment<String>(
                                        value: option.key,
                                        icon: Icon(
                                          option.key == bookshelfFilterAll
                                              ? Icons.apps_rounded
                                              : option.key ==
                                                    bookshelfFilterRead
                                              ? Icons
                                                    .check_circle_outline_rounded
                                              : option.key ==
                                                    bookshelfFilterUnread
                                              ? Icons.schedule_rounded
                                              : Icons.folder_outlined,
                                          size: 17,
                                        ),
                                        label: Text(option.label),
                                      ),
                                    )
                                    .toList(),
                                selected: {controller.selectedFilterKey},
                                onSelectionChanged: (selection) =>
                                    _selectBookFilter(
                                      controller,
                                      selection.first,
                                    ),
                              );
                              if (!isPrimaryFilterSet) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: selector,
                                  ),
                                );
                              }
                              final selectorWidth = constraints.maxWidth > 480
                                  ? 480.0
                                  : constraints.maxWidth;
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: selectorWidth,
                                  child: selector,
                                ),
                              );
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              SliverFadeTransition(
                opacity: _contentFadeAnimation,
                sliver: shelfContent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookGrid(
    BuildContext context, {
    required BookshelfController controller,
    required List<BookSummary> books,
    required double horizontalPadding,
    required String? Function(BookSummary) coverUrl,
    required Map<String, String>? coverHeaders,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        28 + Responsive.shellBottomClearance(context),
      ),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, index) {
          final book = books[index];
          return SlideTransition(
            position: _contentSlideAnimation,
            child: _BookTile(
              book: book,
              imageUrl: coverUrl(book),
              imageBytes: controller.offlineCoverForBook(book.id),
              headers: coverHeaders,
              isOfflineAvailable: controller.isBookCached(book.id),
              isDownloading: controller.isBookDownloading(book.id),
              onOfflinePressed: controller.isOfflineGuest
                  ? null
                  : () => _toggleOfflineDownload(context, controller, book),
              heroTag: 'book-cover-grid-${book.id}',
              frameHeroTag: 'book-frame-grid-${book.id}',
              onTap: () => _showBookDetails(
                context,
                book: book,
                controller: controller,
                imageUrl: coverUrl(book),
                imageBytes: controller.offlineCoverForBook(book.id),
                headers: coverHeaders,
                heroTag: 'book-cover-grid-${book.id}',
                frameHeroTag: 'book-frame-grid-${book.id}',
              ),
            ),
          );
        }, childCount: books.length),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: Responsive.bookshelfColumns(context),
          crossAxisSpacing: Responsive.usesWideLayout(context) ? 18 : 14,
          mainAxisSpacing: Responsive.usesWideLayout(context) ? 20 : 16,
          childAspectRatio: Responsive.usesWideLayout(context) ? 0.58 : 0.48,
        ),
      ),
    );
  }

  Widget _buildGroupGrid(
    BuildContext context, {
    required BookshelfController controller,
    required Map<String, List<BookSummary>> groups,
    required double horizontalPadding,
    required String? Function(BookSummary) coverUrl,
    required Map<String, String>? coverHeaders,
  }) {
    final entries = groups.entries.toList()
      ..sort((left, right) {
        if (left.key == '未分组') return 1;
        if (right.key == '未分组') return -1;
        return left.key.compareTo(right.key);
      });
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1280
        ? 6
        : width >= 900
        ? 4
        : width >= 600
        ? 3
        : 2;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        28 + Responsive.shellBottomClearance(context),
      ),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, index) {
          final entry = entries[index];
          final frameHeroTag = 'book-group-frame-${entry.key}';
          final titleHeroTag = 'book-group-title-${entry.key}';
          return SlideTransition(
            position: _contentSlideAnimation,
            child: _GroupFolderTile(
              name: entry.key,
              books: entry.value,
              imageUrlFor: coverUrl,
              headers: coverHeaders,
              frameHeroTag: frameHeroTag,
              titleHeroTag: titleHeroTag,
              onEdit: entry.key == '未分组' || controller.isOfflineGuest
                  ? null
                  : () async {
                      await _showRenameGroupDialog(
                        context,
                        name: entry.key,
                        controller: controller,
                      );
                    },
              onTap: () async {
                await _showGroupFolder(
                  context,
                  name: entry.key,
                  controller: controller,
                  imageUrlFor: coverUrl,
                  headers: coverHeaders,
                  frameHeroTag: frameHeroTag,
                  titleHeroTag: titleHeroTag,
                );
              },
            ),
          );
        }, childCount: entries.length),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 20,
          mainAxisSpacing: 22,
          childAspectRatio: 1.02,
        ),
      ),
    );
  }
}

class BookshelfSearchScreen extends ConsumerStatefulWidget {
  const BookshelfSearchScreen({super.key});

  @override
  ConsumerState<BookshelfSearchScreen> createState() =>
      _BookshelfSearchScreenState();
}

class _BookshelfSearchScreenState extends ConsumerState<BookshelfSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(bookshelfControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final apiClient = ref.read(apiClientProvider);
    final results = controller.searchBooks(_query);
    final horizontalPadding = Responsive.usesWideLayout(context) ? 28.0 : 16.0;
    final accessToken = auth.accessToken;
    final headers = accessToken == null
        ? null
        : apiClient.coverHeaders(accessToken);

    return Scaffold(
      appBar: AppBar(title: const Text('搜索藏书')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12,
                horizontalPadding,
                12,
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '输入书名、作者、简介或分组',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            if (_query.trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  10,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '找到 ${results.length} 本书',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppReaderPalette.of(context).inkSecondary,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _query.trim().isEmpty
                  ? const _SearchEmptyState(
                      icon: Icons.manage_search_rounded,
                      title: '搜索你的藏书',
                      message: '输入书名、作者或简介关键词。',
                    )
                  : results.isEmpty
                  ? const _SearchEmptyState(
                      icon: Icons.search_off_rounded,
                      title: '没有找到匹配的书',
                      message: '试试其他关键词或分组名。',
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        6,
                        horizontalPadding,
                        24,
                      ),
                      physics: const BouncingScrollPhysics(),
                      itemCount: results.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: Responsive.bookshelfColumns(context),
                        crossAxisSpacing: Responsive.usesWideLayout(context)
                            ? 18
                            : 14,
                        mainAxisSpacing: Responsive.usesWideLayout(context)
                            ? 20
                            : 16,
                        childAspectRatio: 0.58,
                      ),
                      itemBuilder: (context, index) {
                        final book = results[index];
                        final imageUrl = accessToken == null
                            ? null
                            : apiClient.buildUrl(
                                '/api/me/books/${book.id}/cover',
                              );
                        final heroTag = 'book-cover-search-${book.id}';
                        final frameHeroTag = 'book-frame-search-${book.id}';
                        return _BookTile(
                          book: book,
                          imageUrl: imageUrl,
                          imageBytes: controller.offlineCoverForBook(book.id),
                          headers: headers,
                          isOfflineAvailable: controller.isBookCached(book.id),
                          isDownloading: controller.isBookDownloading(book.id),
                          onOfflinePressed: controller.isOfflineGuest
                              ? null
                              : () => _toggleOfflineDownload(
                                  context,
                                  controller,
                                  book,
                                ),
                          heroTag: heroTag,
                          frameHeroTag: frameHeroTag,
                          onTap: () => _showBookDetails(
                            context,
                            book: book,
                            controller: controller,
                            imageUrl: imageUrl,
                            imageBytes: controller.offlineCoverForBook(book.id),
                            headers: headers,
                            heroTag: heroTag,
                            frameHeroTag: frameHeroTag,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: palette.inkTertiary),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfHeader extends StatelessWidget {
  const _ShelfHeader({
    required this.initials,
    required this.avatarUrl,
    required this.avatarHeaders,
    required this.bookCount,
    required this.pendingCount,
    required this.offlineBookCount,
    required this.isOfflineMode,
    required this.isOfflineGuest,
    required this.isLoading,
    required this.onSearch,
    required this.onRefresh,
  });

  final String initials;
  final String? avatarUrl;
  final Map<String, String>? avatarHeaders;
  final int bookCount;
  final int pendingCount;
  final int offlineBookCount;
  final bool isOfflineMode;
  final bool isOfflineGuest;
  final bool isLoading;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Row(
      children: [
        SizedBox.square(
          dimension: 42,
          child: Material(
            color: palette.accent.withValues(alpha: 0.12),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: avatarUrl == null
                ? Center(
                    child: Text(
                      initials,
                      style: TextStyle(color: palette.accent),
                    ),
                  )
                : Image.network(
                    avatarUrl!,
                    key: ValueKey(avatarUrl),
                    headers: avatarHeaders,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Text(
                        initials,
                        style: TextStyle(color: palette.accent),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '书架',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isOfflineGuest
                    ? '$bookCount 本离线藏书 · $pendingCount 项待同步'
                    : isOfflineMode
                    ? '$bookCount 本藏书 · 离线模式 · $offlineBookCount 本可离线'
                    : pendingCount == 0
                    ? '$bookCount 本藏书 · $offlineBookCount 本可离线 · 已同步'
                    : '$bookCount 本藏书 · $offlineBookCount 本可离线 · $pendingCount 项待同步',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '搜索藏书',
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          tooltip: '刷新书架',
          onPressed: isLoading ? null : onRefresh,
          icon: isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _OfflineGuestBanner extends StatelessWidget {
  const _OfflineGuestBanner({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return GlassSurface(
      level: GlassSurfaceLevel.subtle,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(Icons.offline_bolt_rounded, size: 20, color: palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '离线使用中：可阅读、搜索并暂存批注，登录原账户后同步。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
            ),
          ),
          TextButton(onPressed: onLogin, child: const Text('登录同步')),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 9),
        Text(
          detail,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.inkTertiary),
        ),
      ],
    );
  }
}

class _RecentBookItem extends StatelessWidget {
  const _RecentBookItem({
    required this.book,
    required this.progress,
    required this.onTap,
    required this.heroTag,
    required this.frameHeroTag,
    this.imageUrl,
    this.imageBytes,
    this.headers,
  });

  final BookSummary book;
  final ReadingProgressView? progress;
  final VoidCallback onTap;
  final Object heroTag;
  final Object frameHeroTag;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final percent = (progress?.progressPercent ?? 0).clamp(0, 100).toDouble();
    return SizedBox(
      width: 244,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: _BookHeroFrame(
              heroTag: frameHeroTag,
              borderRadius: 14,
              shadow: false,
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: _BookCover(
                        title: book.title,
                        imageUrl: imageUrl,
                        imageBytes: imageBytes,
                        headers: headers,
                        badge: book.format.toUpperCase(),
                        heroTag: heroTag,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                book.author ?? '未知作者',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.inkSecondary),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '最后阅读',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: palette.inkTertiary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatLastReadTime(progress?.updatedAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: palette.inkTertiary),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: percent / 100,
                                  minHeight: 4,
                                  backgroundColor: palette.line,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '已读 ${percent.round()}%',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: palette.inkTertiary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatefulWidget {
  const _BookTile({
    required this.book,
    required this.onTap,
    this.heroTag,
    this.frameHeroTag,
    this.imageUrl,
    this.imageBytes,
    this.headers,
    this.isOfflineAvailable = false,
    this.isDownloading = false,
    this.onOfflinePressed,
  });

  final BookSummary book;
  final VoidCallback onTap;
  final Object? heroTag;
  final Object? frameHeroTag;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final Map<String, String>? headers;
  final bool isOfflineAvailable;
  final bool isDownloading;
  final VoidCallback? onOfflinePressed;

  @override
  State<_BookTile> createState() => _BookTileState();
}

class _BookTileState extends State<_BookTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final titleStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.3,
        ) ??
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.3);
    final titleLineHeight =
        MediaQuery.textScalerOf(context).scale(titleStyle.fontSize ?? 12) *
        (titleStyle.height ?? 1);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.025 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: _BookHeroFrame(
                heroTag: widget.frameHeroTag,
                borderRadius: 12,
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _BookCover(
                          title: widget.book.title,
                          imageUrl: widget.imageUrl,
                          imageBytes: widget.imageBytes,
                          headers: widget.headers,
                          badge: widget.book.format.toUpperCase(),
                          elevated: _hovered,
                          heroTag: widget.heroTag,
                          isOfflineAvailable: widget.isOfflineAvailable,
                          isDownloading: widget.isDownloading,
                          onOfflinePressed: widget.onOfflinePressed,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: titleLineHeight * 2,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            widget.book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.book.author ?? widget.book.format.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: palette.inkTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.title,
    this.imageUrl,
    this.imageBytes,
    this.headers,
    this.badge,
    this.elevated = false,
    this.heroTag,
    this.isOfflineAvailable = false,
    this.isDownloading = false,
    this.onOfflinePressed,
  });

  final String title;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final Map<String, String>? headers;
  final String? badge;
  final bool elevated;
  final Object? heroTag;
  final bool isOfflineAvailable;
  final bool isDownloading;
  final VoidCallback? onOfflinePressed;

  @override
  Widget build(BuildContext context) {
    final cover = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: elevated ? 0.2 : 0.1),
            blurRadius: elevated ? 18 : 9,
            offset: Offset(0, elevated ? 8 : 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF70472D), Color(0xFF9A6844)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: imageBytes != null
                  ? Image.memory(imageBytes!, fit: BoxFit.cover)
                  : imageUrl == null
                  ? _BookFallback(title: title)
                  : Image.network(
                      imageUrl!,
                      headers: headers,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _BookFallback(title: title),
                    ),
            ),
            if (badge != null)
              Positioned(
                top: 7,
                right: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            if (onOfflinePressed != null)
              Positioned(
                right: 7,
                bottom: 7,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.58),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: isDownloading ? null : onOfflinePressed,
                    child: SizedBox.square(
                      dimension: 32,
                      child: Center(
                        child: isDownloading
                            ? const SizedBox.square(
                                dimension: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isOfflineAvailable
                                    ? Icons.offline_pin_rounded
                                    : Icons.download_for_offline_outlined,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (heroTag == null || MediaQuery.of(context).disableAnimations) {
      return cover;
    }
    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: true,
      child: Material(color: Colors.transparent, child: cover),
    );
  }
}

class _BookHeroFrame extends StatelessWidget {
  const _BookHeroFrame({
    required this.heroTag,
    required this.borderRadius,
    this.dialog = false,
    this.shadow = true,
  });

  final Object? heroTag;
  final double borderRadius;
  final bool dialog;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final frame = GlassSurface(
      level: dialog ? GlassSurfaceLevel.elevated : GlassSurfaceLevel.subtle,
      borderRadius: BorderRadius.circular(borderRadius),
      blur: dialog,
      shadow: shadow,
      child: const SizedBox.expand(),
    );
    if (heroTag == null || MediaQuery.of(context).disableAnimations) {
      return frame;
    }
    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: true,
      child: Material(color: Colors.transparent, child: frame),
    );
  }
}

class _BookFallback extends StatelessWidget {
  const _BookFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 22, height: 2, color: Colors.white54),
          const Spacer(),
          Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupFolderTile extends StatelessWidget {
  const _GroupFolderTile({
    required this.name,
    required this.books,
    required this.imageUrlFor,
    required this.headers,
    required this.frameHeroTag,
    required this.titleHeroTag,
    required this.onTap,
    this.onEdit,
  });

  final String name;
  final List<BookSummary> books;
  final String? Function(BookSummary) imageUrlFor;
  final Map<String, String>? headers;
  final Object frameHeroTag;
  final Object titleHeroTag;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _GroupFolderHeroFrame(heroTag: frameHeroTag, dialog: false),
                Positioned.fill(
                  top: 24,
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _GroupCoverArtwork(
                    books: books,
                    imageUrlFor: imageUrlFor,
                    headers: headers,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: _GroupNameHero(
                    name: name,
                    heroTag: titleHeroTag,
                    expanded: false,
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: '修改分组名称',
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
              ],
            ),
          ),
          Text(
            '${books.length} 本书',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: palette.inkTertiary),
          ),
        ],
      ),
    );
  }
}

String _formatLastReadTime(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value)?.toLocal();
  if (parsed == null) {
    return '时间未知';
  }
  final now = DateTime.now();
  final date = DateUtils.dateOnly(parsed);
  final today = DateUtils.dateOnly(now);
  final time =
      '${parsed.hour.toString().padLeft(2, '0')}:'
      '${parsed.minute.toString().padLeft(2, '0')}:'
      '${parsed.second.toString().padLeft(2, '0')}';
  if (date == today) {
    return '今天 $time';
  }
  if (date == today.subtract(const Duration(days: 1))) {
    return '昨天 $time';
  }
  if (parsed.year == now.year) {
    return '${parsed.month}月${parsed.day}日 $time';
  }
  return '${parsed.year}年${parsed.month}月${parsed.day}日 $time';
}

class _GroupNameHero extends StatelessWidget {
  const _GroupNameHero({
    required this.name,
    required this.heroTag,
    required this.expanded,
  });

  final String name;
  final Object? heroTag;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final expandedStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final text = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: expanded ? expandedStyle : compactStyle,
    );
    if (heroTag == null || MediaQuery.of(context).disableAnimations) {
      return text;
    }
    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder:
          (flightContext, animation, direction, fromContext, toContext) {
            final beginStyle = direction == HeroFlightDirection.push
                ? compactStyle
                : expandedStyle;
            final endStyle = direction == HeroFlightDirection.push
                ? expandedStyle
                : compactStyle;
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final progress = Curves.easeOutCubic.transform(animation.value);
                return Material(
                  color: Colors.transparent,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle.lerp(beginStyle, endStyle, progress),
                  ),
                );
              },
            );
          },
      child: Material(color: Colors.transparent, child: text),
    );
  }
}

class _GroupFolderHeroFrame extends StatelessWidget {
  const _GroupFolderHeroFrame({required this.heroTag, required this.dialog});

  final Object? heroTag;
  final bool dialog;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final frame = Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: dialog ? 28 : 12,
          child: Container(
            width: dialog ? 96 : 72,
            height: dialog ? 24 : 22,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.22),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
          ),
        ),
        Positioned.fill(
          top: dialog ? 14 : 12,
          child: GlassSurface(
            level: dialog
                ? GlassSurfaceLevel.elevated
                : GlassSurfaceLevel.standard,
            borderRadius: BorderRadius.circular(dialog ? 24 : 17),
            blur: dialog,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
    if (heroTag == null || MediaQuery.of(context).disableAnimations) {
      return frame;
    }
    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      child: Material(color: Colors.transparent, child: frame),
    );
  }
}

class _GroupCoverArtwork extends StatelessWidget {
  const _GroupCoverArtwork({
    required this.books,
    required this.imageUrlFor,
    required this.headers,
  });

  final List<BookSummary> books;
  final String? Function(BookSummary) imageUrlFor;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final visibleBooks = books.take(4).toList(growable: false);
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
        childAspectRatio: 0.72,
      ),
      itemCount: visibleBooks.length,
      itemBuilder: (_, index) => _cover(visibleBooks[index]),
    );
  }

  Widget _cover(BookSummary book) => _BookCover(
    title: book.title,
    imageUrl: imageUrlFor(book),
    headers: headers,
  );
}

Future<void> _showRenameGroupDialog(
  BuildContext context, {
  required String name,
  required BookshelfController controller,
}) async {
  final formKey = GlobalKey<FormState>();
  final textController = TextEditingController(text: name)
    ..selection = TextSelection(baseOffset: 0, extentOffset: name.length);

  String? renamedGroup;
  try {
    renamedGroup = await showCenteredScaleDialog<String>(
      context,
      builder: (dialogContext) {
        void submit() {
          if (formKey.currentState?.validate() != true) {
            return;
          }
          Navigator.of(dialogContext).pop(textController.text.trim());
        }

        return GlassAlertDialog(
          title: const Text('修改分组名称'),
          content: SizedBox(
            width: 360,
            child: Form(
              key: formKey,
              child: TextFormField(
                controller: textController,
                autofocus: true,
                maxLength: 120,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '分组名称',
                  helperText: '使用已有名称会将两个分组合并',
                ),
                validator: (value) {
                  final normalized = value?.trim() ?? '';
                  if (normalized.isEmpty) {
                    return '请输入分组名称';
                  }
                  if (normalized == '未分组') {
                    return '“未分组”是系统保留名称';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => submit(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(onPressed: submit, child: const Text('保存')),
          ],
        );
      },
    );
  } finally {
    textController.dispose();
  }

  if (renamedGroup == null || renamedGroup == name || !context.mounted) {
    return;
  }
  try {
    final updatedBooks = await controller.renameGroup(name, renamedGroup);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分组已改为“$renamedGroup”，更新 $updatedBooks 本书')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分组重命名失败：$error')));
    }
  }
}

Future<void> _showGroupFolder(
  BuildContext context, {
  required String name,
  required BookshelfController controller,
  required String? Function(BookSummary) imageUrlFor,
  required Map<String, String>? headers,
  required Object frameHeroTag,
  required Object titleHeroTag,
}) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: '关闭分组',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final wideDialog = Responsive.usesWideLayout(dialogContext);
        final dialogInset = wideDialog ? 24.0 : 16.0;
        final dialogWidth = (screenSize.width - dialogInset * 2)
            .clamp(280.0, 880.0)
            .toDouble();
        return ListenableBuilder(
          listenable: controller,
          builder: (_, _) {
            final visibleBooks =
                controller.groupedBooks[name] ?? const <BookSummary>[];
            final gridWidth = dialogWidth - 48;
            final columns = gridWidth >= 720
                ? 6
                : gridWidth >= 500
                ? 4
                : 3;
            final tileAspectRatio = wideDialog ? 0.58 : 0.43;
            final tileWidth = (gridWidth - (columns - 1) * 16) / columns;
            final rows = visibleBooks.isEmpty
                ? 0
                : (visibleBooks.length + columns - 1) ~/ columns;
            final naturalGridHeight = rows == 0
                ? 0.0
                : rows * (tileWidth / tileAspectRatio) + (rows - 1) * 18;
            final maxDialogHeight = wideDialog
                ? (screenSize.height - dialogInset * 2)
                      .clamp(280.0, 680.0)
                      .toDouble()
                : (screenSize.height * 0.66).clamp(320.0, 560.0).toDouble();
            final dialogHeight = wideDialog
                ? maxDialogHeight
                : (140 + naturalGridHeight)
                      .clamp(280.0, maxDialogHeight)
                      .toDouble();
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: EdgeInsets.all(dialogInset),
              child: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _GroupFolderHeroFrame(
                      heroTag: reduceMotion ? null : frameHeroTag,
                      dialog: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _GroupNameHero(
                                  name: name,
                                  heroTag: reduceMotion ? null : titleHeroTag,
                                  expanded: true,
                                ),
                              ),
                              Text('${visibleBooks.length} 本'),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: '关闭',
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (gridContext, constraints) {
                                final columns = constraints.maxWidth >= 720
                                    ? 6
                                    : constraints.maxWidth >= 500
                                    ? 4
                                    : 3;
                                return GridView.builder(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 18,
                                        childAspectRatio: tileAspectRatio,
                                      ),
                                  itemCount: visibleBooks.length,
                                  itemBuilder: (tileContext, index) {
                                    final book = visibleBooks[index];
                                    final coverHeroTag =
                                        'book-cover-group-$name-${book.id}';
                                    final frameHeroTag =
                                        'book-frame-group-$name-${book.id}';
                                    return _BookTile(
                                      book: book,
                                      imageUrl: imageUrlFor(book),
                                      imageBytes: controller
                                          .offlineCoverForBook(book.id),
                                      headers: headers,
                                      isOfflineAvailable: controller
                                          .isBookCached(book.id),
                                      isDownloading: controller
                                          .isBookDownloading(book.id),
                                      onOfflinePressed:
                                          controller.isOfflineGuest
                                          ? null
                                          : () => _toggleOfflineDownload(
                                              tileContext,
                                              controller,
                                              book,
                                            ),
                                      heroTag: coverHeroTag,
                                      frameHeroTag: frameHeroTag,
                                      onTap: () => _showBookDetails(
                                        tileContext,
                                        book: book,
                                        controller: controller,
                                        imageUrl: imageUrlFor(book),
                                        imageBytes: controller
                                            .offlineCoverForBook(book.id),
                                        headers: headers,
                                        heroTag: coverHeroTag,
                                        frameHeroTag: frameHeroTag,
                                        onReadRequested: (anchor) async {
                                          if (dialogContext.mounted) {
                                            Navigator.of(dialogContext).pop();
                                          }
                                          if (context.mounted) {
                                            context.push(
                                              _readerLocation(book, anchor),
                                            );
                                          }
                                        },
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.12, 1, curve: Curves.easeOutCubic),
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    ),
  );
}

class _BookDialogResult {
  const _BookDialogResult({this.anchor});
  final String? anchor;
}

String _readerLocation(BookSummary book, String? anchor) =>
    anchor == null || anchor.isEmpty
    ? '/reader/${book.id}'
    : '/reader/${book.id}?anchor=${Uri.encodeQueryComponent(anchor)}';

Future<void> _toggleOfflineDownload(
  BuildContext context,
  BookshelfController controller,
  BookSummary book,
) async {
  if (controller.isBookCached(book.id)) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: const Text('删除离线下载？'),
        content: Text('删除“${book.title}”的本地文件。在线书架中的书籍不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除下载'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.removeOfflineDownload(book.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已删除“${book.title}”的离线文件')));
      }
    }
    return;
  }

  try {
    await controller.downloadForOffline(book);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('“${book.title}”已可离线阅读')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.error ?? '离线下载失败')));
    }
  }
}

Future<void> _showBookDetails(
  BuildContext context, {
  required BookSummary book,
  required BookshelfController controller,
  required String? imageUrl,
  required Uint8List? imageBytes,
  required Map<String, String>? headers,
  Object? heroTag,
  Object? frameHeroTag,
  Future<void> Function(String? anchor)? onReadRequested,
}) async {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  final result = await Navigator.of(context, rootNavigator: true)
      .push<_BookDialogResult>(
        PageRouteBuilder<_BookDialogResult>(
          opaque: false,
          barrierDismissible: true,
          barrierLabel: '关闭书籍详情',
          barrierColor: Colors.black.withValues(alpha: 0.46),
          transitionDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 360),
          reverseTransitionDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          pageBuilder: (dialogContext, _, _) => _BookDetailsDialog(
            book: book,
            controller: controller,
            imageUrl: imageUrl,
            imageBytes: imageBytes,
            headers: headers,
            heroTag: reduceMotion ? null : heroTag,
            frameHeroTag: reduceMotion ? null : frameHeroTag,
          ),
          transitionsBuilder: (_, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: const Interval(0.08, 1, curve: Curves.easeOutCubic),
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.018),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        ),
      );
  if (result == null || !context.mounted) return;
  final anchor = result.anchor;
  if (onReadRequested != null) {
    await onReadRequested(anchor);
    return;
  }
  context.push(_readerLocation(book, anchor));
}

class _BookDetailsDialog extends StatefulWidget {
  const _BookDetailsDialog({
    required this.book,
    required this.controller,
    required this.imageUrl,
    required this.imageBytes,
    required this.headers,
    required this.heroTag,
    required this.frameHeroTag,
  });

  final BookSummary book;
  final BookshelfController controller;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final Map<String, String>? headers;
  final Object? heroTag;
  final Object? frameHeroTag;

  @override
  State<_BookDetailsDialog> createState() => _BookDetailsDialogStateV2();
}

class _BookDetailsDialogStateV2 extends State<_BookDetailsDialog> {
  static const _ungroupedSelection = '__ungrouped__';
  static const _createGroupSelection = '__create_group__';

  late final Future<List<AnnotationView>> _annotations;
  late final TextEditingController _newGroupController;
  late String _groupSelection;
  String? _currentGroup;
  bool _savingGroup = false;

  @override
  void initState() {
    super.initState();
    _annotations = widget.controller.loadAnnotations(widget.book.id);
    _currentGroup = widget.book.groupName?.trim();
    if (_currentGroup?.isEmpty == true) _currentGroup = null;
    _groupSelection = _currentGroup ?? _ungroupedSelection;
    _newGroupController = TextEditingController();
  }

  @override
  void dispose() {
    _newGroupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= 780;
    final compactHeight = screen.height < 720;
    final dialogHeight = compactHeight ? screen.height * 0.95 : 650.0;
    final contentPadding = wide ? 28.0 : 18.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: wide ? 32 : 12,
        vertical: compactHeight ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SizedBox(
          height: dialogHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: _BookHeroFrame(
                  heroTag: widget.frameHeroTag,
                  borderRadius: 26,
                  dialog: true,
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: EdgeInsets.all(contentPadding),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 282,
                              child: _buildOverview(context),
                            ),
                            const SizedBox(width: 28),
                            VerticalDivider(
                              width: 1,
                              color: AppReaderPalette.of(context).line,
                            ),
                            const SizedBox(width: 28),
                            Expanded(child: _buildWorkspace(context)),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(
                              height: compactHeight ? 158 : 182,
                              child: _buildCompactOverview(context),
                            ),
                            Divider(
                              height: 25,
                              color: AppReaderPalette.of(context).line,
                            ),
                            Expanded(child: _buildWorkspace(context)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverview(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final description = widget.book.description?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: 156,
            height: 234,
            child: _BookCover(
              title: widget.book.title,
              imageUrl: widget.imageUrl,
              imageBytes: widget.imageBytes,
              headers: widget.headers,
              badge: widget.book.format.toUpperCase(),
              elevated: true,
              heroTag: widget.heroTag,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          widget.book.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.book.author ?? '未知作者',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaLabel(
              icon: Icons.description_outlined,
              text: widget.book.format.toUpperCase(),
            ),
            _MetaLabel(
              icon: Icons.folder_outlined,
              text: _currentGroup ?? '无分组',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '简介',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              description == null || description.isEmpty
                  ? '暂无书籍简介'
                  : description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.inkSecondary,
                height: 1.65,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactOverview(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          height: 156,
          child: _BookCover(
            title: widget.book.title,
            imageUrl: widget.imageUrl,
            imageBytes: widget.imageBytes,
            headers: widget.headers,
            badge: widget.book.format.toUpperCase(),
            elevated: true,
            heroTag: widget.heroTag,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.book.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                widget.book.author ?? '未知作者',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
              ),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MetaLabel(
                    icon: Icons.description_outlined,
                    text: widget.book.format.toUpperCase(),
                  ),
                  _MetaLabel(
                    icon: Icons.folder_outlined,
                    text: _currentGroup ?? '无分组',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '批注',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 9),
            Text(
              '点击即可定位到原文',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkTertiary),
            ),
            const Spacer(),
            if (MediaQuery.sizeOf(context).width >= 780)
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildAnnotationList(context)),
        if (!widget.controller.isOfflineGuest) ...[
          Divider(height: 28, color: palette.line),
          _buildGroupSelector(context),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
              label: const Text('关闭'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () =>
                    Navigator.of(context).pop(const _BookDialogResult()),
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('开始阅读'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnnotationList(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return FutureBuilder<List<AnnotationView>>(
      future: _annotations,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '批注加载失败：${snapshot.error}',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.inkSecondary),
            ),
          );
        }
        final annotations = snapshot.data ?? const [];
        if (annotations.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  size: 34,
                  color: palette.inkTertiary,
                ),
                const SizedBox(height: 10),
                Text('这本书还没有批注', style: TextStyle(color: palette.inkSecondary)),
              ],
            ),
          );
        }
        return ListView.separated(
          itemCount: annotations.length,
          separatorBuilder: (_, _) => Divider(color: palette.line),
          itemBuilder: (context, index) {
            final annotation = annotations[index];
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(
                Icons.format_quote_rounded,
                color: _annotationColor(annotation, palette.accent),
              ),
              title: Text(
                annotation.quoteText?.trim().isNotEmpty == true
                    ? annotation.quoteText!
                    : (annotation.noteText ?? '未命名批注'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: annotation.noteText?.trim().isNotEmpty == true
                  ? Text(
                      annotation.noteText!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
              onTap: () => Navigator.of(
                context,
              ).pop(_BookDialogResult(anchor: annotation.anchor)),
            );
          },
        );
      },
    );
  }

  Widget _buildGroupSelector(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final existingGroups =
        widget.controller.groupNames
            .map((group) => group.trim())
            .where((group) => group.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final availableValues = <String>{
      _ungroupedSelection,
      _createGroupSelection,
      ...existingGroups,
    };
    if (!availableValues.contains(_groupSelection)) {
      _groupSelection = _currentGroup ?? _ungroupedSelection;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '书籍分组',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 9),
        DropdownButtonFormField<String>(
          key: ValueKey('$_groupSelection-${existingGroups.join('|')}'),
          initialValue: _groupSelection,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.drive_file_move_outline),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(
              value: _ungroupedSelection,
              child: Text('无分组'),
            ),
            const DropdownMenuItem(
              value: _createGroupSelection,
              child: Text('新增分组…'),
            ),
            ...existingGroups.map(
              (group) => DropdownMenuItem(value: group, child: Text(group)),
            ),
          ],
          onChanged: _savingGroup
              ? null
              : (value) async {
                  if (value == null) return;
                  if (value == _createGroupSelection) {
                    setState(() => _groupSelection = value);
                    return;
                  }
                  await _applyGroup(
                    value == _ungroupedSelection ? null : value,
                  );
                },
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _groupSelection == _createGroupSelection
              ? Padding(
                  key: const ValueKey('new-group-input'),
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newGroupController,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            hintText: '输入新分组名称',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _createGroup(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _savingGroup ? null : _createGroup,
                        child: _savingGroup
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('创建并加入'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  key: const ValueKey('group-hint'),
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    '仅显示当前仍包含书籍的分组',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.inkTertiary,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _createGroup() async {
    final name = _newGroupController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入分组名称')));
      return;
    }
    await _applyGroup(name);
    if (mounted) _newGroupController.clear();
  }

  Future<void> _applyGroup(String? groupName) async {
    final normalized = groupName?.trim();
    final nextGroup = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (nextGroup == _currentGroup) {
      setState(() {
        _groupSelection = nextGroup ?? _ungroupedSelection;
      });
      return;
    }

    setState(() => _savingGroup = true);
    try {
      await widget.controller.updateBookGroup(widget.book.id, nextGroup);
      if (!mounted) return;
      setState(() {
        _currentGroup = nextGroup;
        _groupSelection = nextGroup ?? _ungroupedSelection;
      });
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextGroup == null ? '已设为无分组' : '已加入“$nextGroup”'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分组更新失败：$error')));
    } finally {
      if (mounted) setState(() => _savingGroup = false);
    }
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.inkSecondary),
            const SizedBox(width: 5),
            Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: palette.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

Color _annotationColor(AnnotationView annotation, Color fallback) {
  final value = annotation.color;
  if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    return fallback;
  }
  return Color(int.parse('FF${value.substring(1)}', radix: 16));
}

class _BookshelfErrorBanner extends StatelessWidget {
  const _BookshelfErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _BookshelfEmptyState extends StatelessWidget {
  const _BookshelfEmptyState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 42,
                color: palette.inkSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                '书架暂时没加载出来',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 9),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.inkSecondary, height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
