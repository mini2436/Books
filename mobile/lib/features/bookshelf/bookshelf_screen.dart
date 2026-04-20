import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import '../auth/auth_controller.dart';
import 'bookshelf_controller.dart';

class BookshelfScreen extends ConsumerWidget {
  const BookshelfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(bookshelfControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final palette = AppReaderPalette.of(context);
    final columns = Responsive.bookshelfColumns(context);

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
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: palette.accent.withValues(
                              alpha: 0.12,
                            ),
                            foregroundColor: palette.accent,
                            child: Text(auth.user?.initials ?? 'PR'),
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
                                Text(
                                  '以统一正文为核心的移动阅读入口',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: palette.inkSecondary),
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
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SummaryChip(
                            label: '藏书',
                            value: controller.books.length.toString(),
                          ),
                          _SummaryChip(
                            label: '待同步',
                            value: controller.pendingCount.toString(),
                          ),
                        ],
                      ),
                      if (controller.error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          controller.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (controller.isLoading && controller.books.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
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
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.isTablet(context) ? 24 : 16,
                    8,
                    Responsive.isTablet(context) ? 24 : 16,
                    24,
                  ),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final book = controller.books[index];
                      return _BookTile(
                        title: book.title,
                        subtitle: book.author ?? book.format.toUpperCase(),
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
                        onTap: () => context.push('/reader/${book.id}'),
                      );
                    }, childCount: controller.books.length),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: Responsive.isTablet(context) ? 20 : 16,
                      mainAxisSpacing: Responsive.isTablet(context) ? 20 : 16,
                      childAspectRatio: 0.56,
                    ),
                  ),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
    this.imageUrl,
    this.headers,
  });

  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;
  final String? imageUrl;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6B4328), Color(0xFF8D5A36)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: imageUrl == null
                        ? _BookFallback(title: title)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.inkTertiary),
          ),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
