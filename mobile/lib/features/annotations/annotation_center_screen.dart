import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/book_models.dart';
import '../auth/auth_controller.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import 'annotation_center_controller.dart';

class AnnotationCenterScreen extends ConsumerStatefulWidget {
  const AnnotationCenterScreen({super.key});

  @override
  ConsumerState<AnnotationCenterScreen> createState() =>
      _AnnotationCenterScreenState();
}

class _AnnotationCenterScreenState
    extends ConsumerState<AnnotationCenterScreen> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(() {
        setState(() {
          _query = _searchController.text.trim();
        });
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(annotationCenterControllerProvider);
    final palette = AppReaderPalette.of(context);
    final tablet = Responsive.isTablet(context);
    final filteredGroups = _filterGroups(controller.bookGroups, _query);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(annotationCenterControllerProvider).refresh(),
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
                                  '先按书定位，再进入书内查看和搜索具体批注',
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
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索书名、作者或格式',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: _searchController.clear,
                                  icon: const Icon(Icons.close),
                                ),
                          filled: true,
                          fillColor: palette.backgroundSoft,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
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
              if (controller.isLoading && controller.bookGroups.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.bookGroups.isEmpty)
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
              else if (filteredGroups.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '没有找到匹配的书籍批注。',
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
                      final group = filteredGroups[index];
                      return _AnnotationBookCard(
                        group: group,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AnnotationBookDetailScreen(
                                bookId: group.book.id,
                              ),
                            ),
                          );
                        },
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemCount: filteredGroups.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<AnnotationBookGroup> _filterGroups(
    List<AnnotationBookGroup> groups,
    String query,
  ) {
    if (query.isEmpty) {
      return groups;
    }
    final normalized = query.toLowerCase();
    return groups.where((group) {
      final title = group.book.title.toLowerCase();
      final author = (group.book.author ?? '').toLowerCase();
      final format = group.book.format.toLowerCase();
      return title.contains(normalized) ||
          author.contains(normalized) ||
          format.contains(normalized);
    }).toList();
  }
}

class AnnotationBookDetailScreen extends ConsumerStatefulWidget {
  const AnnotationBookDetailScreen({super.key, required this.bookId});

  final int bookId;

  @override
  ConsumerState<AnnotationBookDetailScreen> createState() =>
      _AnnotationBookDetailScreenState();
}

class _AnnotationBookDetailScreenState
    extends ConsumerState<AnnotationBookDetailScreen> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(() {
        setState(() {
          _query = _searchController.text.trim();
        });
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(annotationCenterControllerProvider);
    final palette = AppReaderPalette.of(context);
    final group = _findGroup(controller.bookGroups, widget.bookId);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书籍批注')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '这本书当前没有可查看的批注了。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: palette.inkSecondary),
            ),
          ),
        ),
      );
    }

    final filteredEntries = _filterEntries(group.entries, _query);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          group.book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BookCover(book: group.book, width: 68, height: 96),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.book.title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if ((group.book.author ?? '').trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    group.book.author!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: palette.inkSecondary),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _SummaryChip(
                                    label: '本书批注',
                                    value: group.annotationCount.toString(),
                                  ),
                                  _SummaryChip(
                                    label: '格式',
                                    value: group.book.format.toUpperCase(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '搜索批注内容、笔记或日期',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: _searchController.clear,
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        fillColor: palette.backgroundSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (filteredEntries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '没有找到匹配的批注。',
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList.separated(
                  itemBuilder: (context, index) {
                    final entry = filteredEntries[index];
                    return _AnnotationCard(entry: entry, showBookMeta: false);
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemCount: filteredEntries.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  AnnotationBookGroup? _findGroup(
    List<AnnotationBookGroup> groups,
    int bookId,
  ) {
    for (final group in groups) {
      if (group.book.id == bookId) {
        return group;
      }
    }
    return null;
  }

  List<AnnotationCenterEntry> _filterEntries(
    List<AnnotationCenterEntry> entries,
    String query,
  ) {
    if (query.isEmpty) {
      return entries;
    }
    final normalized = query.toLowerCase();
    return entries.where((entry) {
      final quote = (entry.annotation.quoteText ?? '').toLowerCase();
      final note = (entry.annotation.noteText ?? '').toLowerCase();
      final date = entry.annotation.updatedAt.toLowerCase();
      return quote.contains(normalized) ||
          note.contains(normalized) ||
          date.contains(normalized);
    }).toList();
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

class _AnnotationBookCard extends StatelessWidget {
  const _AnnotationBookCard({required this.group, required this.onTap});

  final AnnotationBookGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final latestAnnotation = group.entries.first.annotation;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _BookCover(book: group.book, width: 68, height: 96),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((group.book.author ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          group.book.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.inkSecondary),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      latestAnnotation.quoteText?.trim().isNotEmpty == true
                          ? latestAnnotation.quoteText!
                          : '最近一条批注',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MiniMetaChip(
                          icon: Icons.sticky_note_2_outlined,
                          label: '${group.annotationCount} 条批注',
                        ),
                        _MiniMetaChip(
                          icon: Icons.schedule_outlined,
                          label: latestAnnotation.updatedAt.split('T').first,
                        ),
                        _MiniMetaChip(
                          icon: Icons.library_books_outlined,
                          label: group.book.format.toUpperCase(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right_rounded, color: palette.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMetaChip extends StatelessWidget {
  const _MiniMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.inkSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.inkSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCover extends ConsumerWidget {
  const _BookCover({
    required this.book,
    required this.width,
    required this.height,
  });

  final BookSummary book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final imageUrl = auth.accessToken == null
        ? null
        : ref
              .read(apiClientProvider)
              .buildUrl('/api/me/books/${book.id}/cover');
    final headers = auth.accessToken == null
        ? null
        : ref.read(apiClientProvider).coverHeaders(auth.accessToken!);

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF6B4328), Color(0xFF8D5A36)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: imageUrl == null
            ? _BookCoverFallback(title: book.title)
            : ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  imageUrl,
                  headers: headers,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _BookCoverFallback(title: book.title),
                ),
              ),
      ),
    );
  }
}

class _BookCoverFallback extends StatelessWidget {
  const _BookCoverFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final initials = title.trim().isEmpty ? '书' : title.trim().characters.first;

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AnnotationCard extends ConsumerWidget {
  const _AnnotationCard({required this.entry, this.showBookMeta = true});

  final AnnotationCenterEntry entry;
  final bool showBookMeta;

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
                  if (showBookMeta) ...[
                    Text(
                      entry.book.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((entry.book.author ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          entry.book.author!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.inkSecondary),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    annotation.quoteText?.trim().isNotEmpty == true
                        ? annotation.quoteText!
                        : '高亮片段',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                      if (showBookMeta)
                        Text(
                          entry.book.format.toUpperCase(),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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

    await ref.read(annotationCenterControllerProvider).deleteAnnotation(entry);
  }
}
