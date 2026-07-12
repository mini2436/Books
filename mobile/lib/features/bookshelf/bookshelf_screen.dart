import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/book_models.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import '../auth/auth_controller.dart';
import 'bookshelf_controller.dart';

class BookshelfScreen extends ConsumerWidget {
  const BookshelfScreen({super.key});

  static const double _phoneCoverAspectRatio = 0.64;
  static const double _wideCoverAspectRatio = 0.68;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(bookshelfControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final palette = AppReaderPalette.of(context);
    final tablet = Responsive.isTablet(context);
    final columns = tablet ? Responsive.bookshelfColumns(context) : 2;
    const gridGap = 16.0;
    final horizontalPadding = tablet ? 24.0 : 16.0;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final availableWidth =
        viewportWidth - (horizontalPadding * 2) - (gridGap * (columns - 1));
    final tileWidth = availableWidth / columns;
    final coverAspectRatio = tablet
        ? _wideCoverAspectRatio
        : _phoneCoverAspectRatio;
    final imageHeight = tileWidth / coverAspectRatio;
    final tileHeight = imageHeight + (tablet ? 82 : 102);
    final childAspectRatio = tileWidth / tileHeight;
    final filteredBooks = controller.filteredBooks;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(bookshelfControllerProvider).refresh(),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.isTablet(context) ? 24 : 16,
                    Responsive.isTablet(context) ? 24 : 18,
                    Responsive.isTablet(context) ? 24 : 16,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: Material(
                              color: palette.accent.withValues(alpha: 0.12),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child:
                                  auth.user?.hasAvatar == true &&
                                      auth.accessToken != null
                                  ? Image.network(
                                      ref
                                          .read(apiClientProvider)
                                          .buildUrl('/api/me/profile/avatar'),
                                      key: ValueKey(auth.user?.avatarVersion),
                                      headers: ref
                                          .read(apiClientProvider)
                                          .coverHeaders(auth.accessToken!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Center(
                                        child: Text(
                                          auth.user?.initials ?? 'PR',
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Text(auth.user?.initials ?? 'PR'),
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '服务：${controller.serviceBaseUrl}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: palette.inkTertiary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: controller.isLoading
                                ? null
                                : () => ref
                                      .read(bookshelfControllerProvider)
                                      .refresh(),
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _SummaryChip(
                                    label: '藏书',
                                    value: controller.books.length.toString(),
                                  ),
                                  const SizedBox(width: 12),
                                  _SummaryChip(
                                    label: '待同步',
                                    value: controller.pendingCount.toString(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: tablet ? 260 : 156,
                            child: _BookshelfSearchButton(
                              onTap: () => context.push('/search'),
                            ),
                          ),
                        ],
                      ),
                      if (controller.error != null) ...[
                        const SizedBox(height: 14),
                        _BookshelfErrorBanner(
                          message: controller.error!,
                          onRetry: controller.isLoading
                              ? null
                              : () => ref
                                    .read(bookshelfControllerProvider)
                                    .refresh(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (controller.recentBooks.isNotEmpty)
                SliverToBoxAdapter(
                  child: _RecentReadingSection(
                    books: controller.recentBooks,
                    controller: controller,
                    accessToken: auth.accessToken,
                    onOpenBook: (bookId) => _openBook(
                      context,
                      ref.read(bookshelfControllerProvider),
                      bookId,
                    ),
                  ),
                ),
              if (controller.isLoading && controller.books.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.error != null && controller.books.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _BookshelfEmptyState(
                    message: controller.error!,
                    onRetry: controller.isLoading
                        ? null
                        : () => ref.read(bookshelfControllerProvider).refresh(),
                  ),
                )
              else if (controller.books.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      '书架空空如也，先从后台导入一本书吧。',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _AllBooksHeader(
                    horizontalPadding: horizontalPadding,
                    selectedFilterKey: controller.selectedFilterKey,
                    options: controller.filterOptions,
                    onFilterChanged: controller.setFilter,
                  ),
                ),
                if (filteredBooks.isEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 180,
                      child: Center(
                        child: Text(
                          '当前筛选下没有书籍',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: palette.inkSecondary),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8,
                      horizontalPadding,
                      24,
                    ),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final book = filteredBooks[index];
                        return _BookTile(
                          title: book.title,
                          author: book.author,
                          description: book.description,
                          coverAspectRatio: coverAspectRatio,
                          imageUrl: auth.accessToken == null
                              ? null
                              : ref
                                    .read(apiClientProvider)
                                    .buildUrl('/api/me/books/${book.id}/cover'),
                          headers: auth.accessToken == null
                              ? null
                              : ref
                                    .read(apiClientProvider)
                                    .coverHeaders(auth.accessToken!),
                          badge: book.format.toUpperCase(),
                          onTap: () => _openBook(
                            context,
                            ref.read(bookshelfControllerProvider),
                            book.id,
                          ),
                        );
                      }, childCount: filteredBooks.length),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: gridGap,
                        mainAxisSpacing: gridGap,
                        childAspectRatio: childAspectRatio,
                      ),
                    ),
                  ),
              ],
            ],
          ),
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
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(bookshelfControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final tablet = Responsive.isTablet(context);
    final results = controller.searchBooks(_query);
    final columns = tablet ? Responsive.bookshelfColumns(context) : 2;
    const gridGap = 16.0;
    final horizontalPadding = tablet ? 24.0 : 16.0;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final tileWidth =
        (viewportWidth - (horizontalPadding * 2) - (gridGap * (columns - 1))) /
        columns;
    final coverAspectRatio = tablet
        ? BookshelfScreen._wideCoverAspectRatio
        : BookshelfScreen._phoneCoverAspectRatio;
    final imageHeight = tileWidth / coverAspectRatio;
    final tileHeight = imageHeight + (tablet ? 82 : 102);

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
              child: _BookshelfSearchBar(
                query: _query,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                onClear: () => setState(() => _query = ''),
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
                child: _SearchResultHint(
                  query: _query,
                  totalCount: controller.books.length,
                  visibleCount: results.length,
                ),
              ),
            Expanded(
              child: _query.trim().isEmpty
                  ? const _SearchPrompt()
                  : results.isEmpty
                  ? const _SearchPrompt(
                      icon: Icons.search_off_rounded,
                      title: '没有找到匹配的书',
                      message: '试试书名、作者或简介中的其他关键词。',
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
                        crossAxisCount: columns,
                        crossAxisSpacing: gridGap,
                        mainAxisSpacing: gridGap,
                        childAspectRatio: tileWidth / tileHeight,
                      ),
                      itemBuilder: (context, index) {
                        final book = results[index];
                        return _BookTile(
                          title: book.title,
                          author: book.author,
                          description: book.description,
                          coverAspectRatio: coverAspectRatio,
                          imageUrl: auth.accessToken == null
                              ? null
                              : ref
                                    .read(apiClientProvider)
                                    .buildUrl('/api/me/books/${book.id}/cover'),
                          headers: auth.accessToken == null
                              ? null
                              : ref
                                    .read(apiClientProvider)
                                    .coverHeaders(auth.accessToken!),
                          badge: book.format.toUpperCase(),
                          onTap: () => _openBook(
                            context,
                            ref.read(bookshelfControllerProvider),
                            book.id,
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

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt({
    this.icon = Icons.manage_search_rounded,
    this.title = '搜索你的藏书',
    this.message = '输入书名、作者或简介关键词。',
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

class _AllBooksHeader extends StatelessWidget {
  const _AllBooksHeader({
    required this.horizontalPadding,
    required this.selectedFilterKey,
    required this.options,
    required this.onFilterChanged,
  });

  final double horizontalPadding;
  final String selectedFilterKey;
  final List<BookshelfFilterOption> options;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '全部书籍',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Material(
            color: palette.backgroundSoft,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedFilterKey,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                  items: options
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option.key,
                          child: Text(option.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      onFilterChanged(value);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentReadingSection extends ConsumerWidget {
  const _RecentReadingSection({
    required this.books,
    required this.controller,
    required this.accessToken,
    required this.onOpenBook,
  });

  final List<BookSummary> books;
  final BookshelfController controller;
  final String? accessToken;
  final ValueChanged<int> onOpenBook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    final horizontalPadding = Responsive.isTablet(context) ? 24.0 : 16.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 4, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近阅读',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(right: horizontalPadding),
              itemCount: books.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final book = books[index];
                final progress = controller.progressForBook(book.id);
                return SizedBox(
                  width: 112,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onOpenBook(book.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 0.68,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: accessToken == null
                                ? _BookFallback(title: book.title)
                                : Image.network(
                                    ref
                                        .read(apiClientProvider)
                                        .buildUrl(
                                          '/api/me/books/${book.id}/cover',
                                        ),
                                    headers: ref
                                        .read(apiClientProvider)
                                        .coverHeaders(accessToken!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        _BookFallback(title: book.title),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value:
                                (progress?.progressPercent ?? 0).clamp(0, 100) /
                                100,
                            minHeight: 4,
                            color: palette.accent,
                            backgroundColor: palette.backgroundSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openBook(
  BuildContext context,
  BookshelfController controller,
  int bookId,
) async {
  await context.push('/reader/$bookId');
  await controller.refresh();
}

class _BookshelfErrorBanner extends StatelessWidget {
  const _BookshelfErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi_off_rounded, color: colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(width: 10),
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
          constraints: const BoxConstraints(maxWidth: 360),
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
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.inkSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              if (onRetry != null)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return SizedBox(
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.backgroundSoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
              ),
              const SizedBox(width: 10),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookshelfSearchButton extends StatelessWidget {
  const _BookshelfSearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return SizedBox(
      height: 56,
      child: Material(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                const Icon(Icons.search_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '搜索藏书',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.inkSecondary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.inkTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultHint extends StatelessWidget {
  const _SearchResultHint({
    required this.query,
    required this.totalCount,
    required this.visibleCount,
  });

  final String query;
  final int totalCount;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Row(
      children: [
        Icon(Icons.manage_search_rounded, size: 16, color: palette.inkTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '“$query” 共找到 $visibleCount / $totalCount 本',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.inkTertiary),
          ),
        ),
      ],
    );
  }
}

class _BookshelfSearchBar extends StatefulWidget {
  const _BookshelfSearchBar({
    required this.query,
    required this.onChanged,
    required this.onClear,
    this.autofocus = false,
  });

  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool autofocus;

  @override
  State<_BookshelfSearchBar> createState() => _BookshelfSearchBarState();
}

class _BookshelfSearchBarState extends State<_BookshelfSearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _BookshelfSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query == _controller.text) {
      return;
    }
    _controller.value = TextEditingValue(
      text: widget.query,
      selection: TextSelection.collapsed(offset: widget.query.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索书名、作者、简介',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: widget.query.isEmpty
            ? null
            : IconButton(
                onPressed: widget.onClear,
                icon: const Icon(Icons.close_rounded),
                tooltip: '清空搜索',
              ),
        filled: true,
        fillColor: palette.backgroundSoft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.accent.withValues(alpha: 0.28)),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.title,
    required this.badge,
    required this.onTap,
    required this.coverAspectRatio,
    this.author,
    this.description,
    this.imageUrl,
    this.headers,
  });

  final String title;
  final String badge;
  final VoidCallback onTap;
  final double coverAspectRatio;
  final String? author;
  final String? description;
  final String? imageUrl;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final secondaryLine = (author ?? '').trim().isNotEmpty
        ? author!.trim()
        : badge;
    final tertiaryLine = (description ?? '').trim();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: coverAspectRatio,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6A4426), Color(0xFF2E221B)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: imageUrl == null
                        ? _BookFallback(title: title)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              imageUrl!,
                              headers: headers,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _BookFallback(title: title),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(14),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.28),
                            Colors.white.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.18, 1],
                        ),
                      ),
                      child: const SizedBox(width: 10),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.08),
                            Colors.black.withValues(alpha: 0.22),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const SizedBox(height: 42),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.54),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            secondaryLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.inkSecondary,
              fontWeight: (author ?? '').trim().isNotEmpty
                  ? FontWeight.w500
                  : FontWeight.w600,
            ),
          ),
          if (tertiaryLine.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              tertiaryLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _BookFallback extends StatelessWidget {
  const _BookFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.35,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
