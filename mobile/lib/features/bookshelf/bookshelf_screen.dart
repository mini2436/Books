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
