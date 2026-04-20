import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import 'annotation_center_controller.dart';

class AnnotationCenterScreen extends ConsumerWidget {
  const AnnotationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(annotationCenterControllerProvider);
    final palette = AppReaderPalette.of(context);
    final tablet = Responsive.isTablet(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(annotationCenterControllerProvider).refresh(),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    tablet ? 24 : 16,
                    tablet ? 24 : 18,
                    tablet ? 24 : 16,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '批注管理',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '集中查看、回跳和清理你的阅读批注',
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
                                      .read(annotationCenterControllerProvider)
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
                            label: '批注总数',
                            value: controller.annotationCount.toString(),
                          ),
                          _SummaryChip(
                            label: '涉及书籍',
                            value: controller.bookCount.toString(),
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
              if (controller.isLoading && controller.entries.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '还没有批注，去阅读器里划一段喜欢的内容吧。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: palette.inkSecondary,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    tablet ? 24 : 16,
                    8,
                    tablet ? 24 : 16,
                    24,
                  ),
                  sliver: SliverList.separated(
                    itemBuilder: (context, index) {
                      final entry = controller.entries[index];
                      return _AnnotationCard(entry: entry);
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemCount: controller.entries.length,
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

class _AnnotationCard extends ConsumerWidget {
  const _AnnotationCard({required this.entry});

  final AnnotationCenterEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    final annotation = entry.annotation;
    final stripeColor = annotation.color == null
        ? palette.accent
        : Color(int.parse('0xFF${annotation.color!.substring(1)}'));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 92,
              decoration: BoxDecoration(
                color: stripeColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.book.title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if ((entry.book.author ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        entry.book.author!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.inkSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    annotation.quoteText?.trim().isNotEmpty == true
                        ? annotation.quoteText!
                        : '高亮片段',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if ((annotation.noteText ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      annotation.noteText!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        annotation.updatedAt.split('T').first,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.inkTertiary,
                        ),
                      ),
                      Text(
                        entry.book.format.toUpperCase(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.inkSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => context.push(
                          '/reader/${entry.book.id}?anchor=${Uri.encodeComponent(annotation.anchor)}',
                        ),
                        icon: const Icon(Icons.menu_book_outlined),
                        label: const Text('打开原文'),
                      ),
                      TextButton.icon(
                        onPressed: () => _confirmDelete(context, ref),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条批注？'),
        content: Text(
          entry.annotation.noteText?.trim().isNotEmpty == true
              ? '删除后将同步移除这条批注和附带笔记。'
              : '删除后将同步移除这条高亮批注。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await ref
        .read(annotationCenterControllerProvider)
        .deleteAnnotation(entry);
  }
}
