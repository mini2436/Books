import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/book_models.dart';
import '../../data/models/sync_models.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import '../settings/reader_preferences_controller.dart';
import 'models/annotation_anchor.dart';
import 'reader_controller.dart';
import 'widgets/reader_html_view.dart';
import 'widgets/reader_settings_sheet.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.bookId,
    this.initialAnchor,
  });

  final int? bookId;
  final String? initialAnchor;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    if (widget.bookId == null) {
      return const Scaffold(body: Center(child: Text('无效的书籍参数')));
    }

    final controller = ref.watch(
      readerControllerProvider(
        ReaderRouteArgs(
          bookId: widget.bookId!,
          initialAnchor: widget.initialAnchor,
        ),
      ),
    );
    final preferences = ref.watch(readerPreferencesControllerProvider).value;
    final palette = AppReaderPalette.of(context);
    final tablet = Responsive.isTablet(context);

    if (controller.isLoading && controller.detail == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (controller.error != null && controller.detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('阅读器')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(controller.error!),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: controller.load,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final detail = controller.detail!;
    if (!controller.isSupported) {
      return _UnsupportedReaderView(detail: detail);
    }

    final chapter = controller.currentChapter;
    final body = chapter == null
        ? const Center(child: CircularProgressIndicator())
        : ReaderHtmlView(
            chapter: chapter,
            annotations: controller.annotations,
            preferences: preferences,
            palette: palette,
            uiVisible: controller.uiVisible,
            focusedAnchor: controller.focusedAnchor,
            anchorJumpVersion: controller.anchorJumpVersion,
            onHighlight: (selection, existingAnnotation) async {
              if (existingAnnotation != null) {
                final existingAnchor = AnnotationAnchor.parse(
                  existingAnnotation.anchor,
                );
                await controller.updateAnnotation(
                  annotation: existingAnnotation,
                  noteText: existingAnnotation.noteText,
                  color:
                      existingAnnotation.color ??
                      _defaultAnnotationColor(preferences.themeMode),
                  selection: selection,
                  underlineStyle: existingAnchor.underlineStyle,
                );
                return;
              }
              await controller.addHighlight(
                selection: selection,
                color: _defaultAnnotationColor(preferences.themeMode),
              );
            },
            onAnnotate: (selection, existingAnnotation) =>
                _openAnnotationComposer(
                  controller,
                  selection: selection,
                  annotation: existingAnnotation,
                ),
            onOpenAnnotations: (annotations) =>
                _openAnnotationsFromReader(controller, annotations),
            onToggleUi: controller.toggleUi,
          );

    if (tablet) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (controller.tocVisible)
                SizedBox(
                  width: Responsive.sidePanelWidth,
                  child: _ReaderLeftPanel(controller: controller),
                ),
              Expanded(
                child: Column(
                  children: [
                    _ReaderTopBar(
                      detail: detail,
                      controller: controller,
                      onSettings: () => controller.setInspectorTab(
                        ReaderInspectorTab.settings,
                      ),
                      onNotes: () =>
                          controller.setInspectorTab(ReaderInspectorTab.notes),
                      tablet: true,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: Responsive.readerMaxWidth,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chapter?.title ?? detail.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                if (controller.isCurrentChapterLoading)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 16),
                                    child: LinearProgressIndicator(),
                                  ),
                                Expanded(child: body),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    _ReaderFooter(controller: controller),
                  ],
                ),
              ),
              if (controller.inspectorVisible)
                SizedBox(
                  width: Responsive.sidePanelWidth,
                  child: _ReaderRightPanel(
                    controller: controller,
                    onEditAnnotation: (annotation) =>
                        _openAnnotationComposer(
                          controller,
                          annotation: annotation,
                        ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(child: _ReaderLeftPanel(controller: controller)),
      ),
      appBar: controller.uiVisible
          ? AppBar(
              title: Text(
                detail.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  onPressed: () async => controller.addBookmark(),
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  onPressed: () => _openNotesSheet(controller),
                  icon: const Icon(Icons.edit_note),
                ),
                IconButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => const ReaderSettingsSheet(),
                  ),
                  icon: const Icon(Icons.tune),
                ),
              ],
            )
          : null,
      bottomNavigationBar: controller.uiVisible
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: palette.panel,
                border: Border(top: BorderSide(color: palette.line)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: controller.progressPercent / 100,
                      backgroundColor: palette.backgroundSoft,
                      color: palette.accent,
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                          icon: const Icon(Icons.list_alt_outlined),
                        ),
                        IconButton(
                          onPressed: () => controller.addBookmark(),
                          icon: const Icon(Icons.bookmark_add_outlined),
                        ),
                        IconButton(
                          onPressed: () => _openNotesSheet(controller),
                          icon: const Icon(Icons.sticky_note_2_outlined),
                        ),
                        IconButton(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) => const ReaderSettingsSheet(),
                          ),
                          icon: const Icon(Icons.palette_outlined),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: controller.previousChapter,
                          child: const Text('上一章'),
                        ),
                        TextButton(
                          onPressed: controller.nextChapter,
                          child: const Text('下一章'),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            24,
            16,
            controller.uiVisible ? 24 : 40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chapter?.title ?? detail.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              if (controller.isCurrentChapterLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNotesSheet(ReaderController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.82,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.paddingOf(context).bottom + 20,
              ),
              child: _ReaderNotesList(
                annotations: controller.annotations,
                onJump: (anchor) async {
                  Navigator.of(context).pop();
                  await controller.jumpToAnchor(anchor);
                },
                onDelete: controller.deleteAnnotation,
                onEdit: (annotation) =>
                    _openAnnotationComposer(controller, annotation: annotation),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openAnnotationComposer(
    ReaderController controller, {
    AnnotationSelection? selection,
    AnnotationView? annotation,
  }) async {
    final existingAnchor = annotation == null
        ? null
        : AnnotationAnchor.parse(annotation.anchor);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AnnotationComposerSheet(
        selectedText: selection?.selectedText ?? annotation?.quoteText ?? '',
        annotation: annotation,
        defaultColor: _defaultAnnotationColor(
          ref.read(readerPreferencesControllerProvider).themeMode,
        ),
        initialUnderlineStyle:
            existingAnchor?.underlineStyle ?? AnnotationUnderlineStyle.none,
        onSubmit: ({
          required noteText,
          required color,
          required underlineStyle,
        }) async {
          if (annotation == null) {
            if (selection == null) {
              return;
            }
            await controller.addAnnotation(
              selection: selection,
              noteText: noteText,
              color: color,
              underlineStyle: underlineStyle,
            );
          } else {
            await controller.updateAnnotation(
              annotation: annotation,
              noteText: noteText,
              color: color,
              selection: selection,
              underlineStyle: underlineStyle,
            );
          }
        },
      ),
    );
  }

  Future<void> _openAnnotationsFromReader(
    ReaderController controller,
    List<AnnotationView> annotations,
  ) async {
    if (annotations.isEmpty) {
      return;
    }
    if (annotations.length == 1) {
      await _openAnnotationComposer(controller, annotation: annotations.first);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          itemBuilder: (context, index) {
            final annotation = annotations[index];
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                annotation.quoteText?.trim().isNotEmpty == true
                    ? annotation.quoteText!
                    : '高亮片段',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                annotation.noteText?.trim().isNotEmpty == true
                    ? annotation.noteText!
                    : '点击编辑这条批注',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _openAnnotationComposer(
                  controller,
                  annotation: annotation,
                );
              },
            );
          },
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemCount: annotations.length,
        ),
      ),
    );
  }

  String _defaultAnnotationColor(ReaderThemeMode themeMode) {
    switch (themeMode) {
      case ReaderThemeMode.eyeCare:
        return '#4A6B3F';
      case ReaderThemeMode.night:
        return '#C3924A';
      case ReaderThemeMode.paper:
      case ReaderThemeMode.kraft:
        return '#7A4A24';
    }
  }
}

const List<String> _annotationColors = [
  '#C3924A',
  '#7A4A24',
  '#4A6B3F',
  '#9C3C34',
  '#C86B3C',
  '#D0A43F',
  '#437A7D',
  '#5A63A3',
  '#7E4A9E',
  '#2D6A4F',
  '#B85C7A',
  '#6E727A',
];

class _AnnotationComposerSheet extends StatefulWidget {
  const _AnnotationComposerSheet({
    required this.selectedText,
    required this.defaultColor,
    required this.initialUnderlineStyle,
    required this.onSubmit,
    this.annotation,
  });

  final String selectedText;
  final String defaultColor;
  final AnnotationUnderlineStyle initialUnderlineStyle;
  final AnnotationView? annotation;
  final Future<void> Function({
    required String? noteText,
    required String color,
    required AnnotationUnderlineStyle underlineStyle,
  }) onSubmit;

  @override
  State<_AnnotationComposerSheet> createState() =>
      _AnnotationComposerSheetState();
}

class _AnnotationComposerSheetState extends State<_AnnotationComposerSheet> {
  late final TextEditingController _noteController;
  late String _selectedColor;
  late AnnotationUnderlineStyle _underlineStyle;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(
      text: widget.annotation?.noteText ?? '',
    );
    _selectedColor = widget.annotation?.color ?? widget.defaultColor;
    _underlineStyle = widget.initialUnderlineStyle;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom +
            20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.annotation == null ? '新增批注' : '编辑批注',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppReaderPalette.of(context).backgroundSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(widget.selectedText),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '批注内容',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '颜色',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final color = _annotationColors[index];
                final selected =
                    color.toLowerCase() == _selectedColor.toLowerCase();
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(int.parse('0xFF${color.substring(1)}')),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemCount: _annotationColors.length,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '下划线',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AnnotationUnderlineStyle.values.map((style) {
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _UnderlineOptionChip(
                    label: switch (style) {
                      AnnotationUnderlineStyle.none => '无线条',
                      AnnotationUnderlineStyle.solid => '直线',
                      AnnotationUnderlineStyle.dotted => '点线',
                      AnnotationUnderlineStyle.wavy => '波浪线',
                    },
                    selected: _underlineStyle == style,
                    onTap: () {
                      setState(() {
                        _underlineStyle = style;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.annotation == null ? '保存批注' : '更新批注'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await widget.onSubmit(
        noteText: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        color: _selectedColor,
        underlineStyle: _underlineStyle,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _UnderlineOptionChip extends StatelessWidget {
  const _UnderlineOptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.12) : scheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnsupportedReaderView extends StatelessWidget {
  const _UnsupportedReaderView({required this.detail});

  final BookDetail detail;

  @override
  Widget build(BuildContext context) {
    final reason = switch (detail.format) {
      'pdf' => 'PDF 暂时仍通过桌面 Web 浏览器阅读。',
      _ when !detail.hasStructuredContent => '该书尚未生成统一正文，请在桌面端继续阅读。',
      _ => '当前移动端仅支持 TXT / EPUB 的统一正文阅读。',
    };

    return Scaffold(
      appBar: AppBar(title: Text(detail.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.desktop_windows_outlined, size: 40),
              const SizedBox(height: 18),
              Text(
                detail.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                reason,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.detail,
    required this.controller,
    required this.onSettings,
    required this.onNotes,
    required this.tablet,
  });

  final BookDetail detail;
  final ReaderController controller;
  final VoidCallback onSettings;
  final VoidCallback onNotes;
  final bool tablet;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: controller.uiVisible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !controller.uiVisible,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                    return;
                  }
                  context.go('/shelf');
                },
                icon: const Icon(Icons.arrow_back_ios_new),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      detail.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (tablet)
                      Text(
                        '${controller.progressPercent.toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: controller.toggleToc,
                icon: Icon(
                  controller.tocVisible
                      ? Icons.menu_open
                      : Icons.menu_book_outlined,
                ),
              ),
              IconButton(
                onPressed: () {
                  controller.toggleInspector();
                  onNotes();
                },
                icon: const Icon(Icons.edit_note),
              ),
              IconButton(
                onPressed: () {
                  controller.toggleInspector();
                  onSettings();
                },
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderFooter extends StatelessWidget {
  const _ReaderFooter({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: controller.uiVisible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !controller.uiVisible,
        child: Container(
          decoration: BoxDecoration(
            color: palette.panel,
            border: Border(top: BorderSide(color: palette.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Text('${controller.progressPercent.toStringAsFixed(1)}%'),
              const Spacer(),
              TextButton(
                onPressed: controller.previousChapter,
                child: const Text('上一章'),
              ),
              TextButton(
                onPressed: controller.nextChapter,
                child: const Text('下一章'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderLeftPanel extends StatelessWidget {
  const _ReaderLeftPanel({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final chapters = controller.content?.chapters ?? const [];

    return ColoredBox(
      color: palette.panel,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        children: [
          Text(
            '目录',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ...chapters.map((chapter) {
            final selected =
                chapter.chapterIndex == controller.currentChapterIndex;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(chapter.title),
              selected: selected,
              selectedTileColor: palette.accent.withValues(alpha: 0.08),
              onTap: () => controller.openChapter(chapter.chapterIndex),
            );
          }),
          const SizedBox(height: 20),
          Text(
            '书签',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (controller.bookmarks.isEmpty)
            Text(
              '还没有书签',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
            )
          else
            ...controller.bookmarks.map(
              (bookmark) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(bookmark.label ?? bookmark.location),
                subtitle: Text(bookmark.updatedAt.split('T').first),
                onTap: () => controller.jumpToAnchor(bookmark.location),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReaderRightPanel extends StatelessWidget {
  const _ReaderRightPanel({
    required this.controller,
    required this.onEditAnnotation,
  });

  final ReaderController controller;
  final ValueChanged<AnnotationView> onEditAnnotation;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return ColoredBox(
      color: palette.panel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<ReaderInspectorTab>(
              segments: const [
                ButtonSegment(
                  value: ReaderInspectorTab.notes,
                  label: Text('笔记'),
                ),
                ButtonSegment(
                  value: ReaderInspectorTab.settings,
                  label: Text('设置'),
                ),
              ],
              selected: {controller.inspectorTab},
              onSelectionChanged: (selection) =>
                  controller.setInspectorTab(selection.first),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: switch (controller.inspectorTab) {
                ReaderInspectorTab.notes => _ReaderNotesList(
                  annotations: controller.annotations,
                  onJump: controller.jumpToAnchor,
                  onDelete: controller.deleteAnnotation,
                  onEdit: onEditAnnotation,
                ),
                ReaderInspectorTab.settings =>
                  const ReaderSettingsPanelContent(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderNotesList extends StatelessWidget {
  const _ReaderNotesList({
    required this.annotations,
    required this.onJump,
    required this.onDelete,
    required this.onEdit,
  });

  final List<AnnotationView> annotations;
  final Future<void> Function(String anchor) onJump;
  final Future<void> Function(AnnotationView annotation) onDelete;
  final ValueChanged<AnnotationView> onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    if (annotations.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
            child: Text(
              '暂时还没有批注',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: annotations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final annotation = annotations[index];
        final color = annotation.color == null
            ? palette.accent
            : Color(int.parse('0xFF${annotation.color!.substring(1)}'));

        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.backgroundSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  annotation.quoteText ?? '高亮片段',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if ((annotation.noteText ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(annotation.noteText!),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      annotation.updatedAt.split('T').first,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.inkTertiary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => onJump(annotation.anchor),
                      child: const Text('定位'),
                    ),
                    TextButton(
                      onPressed: () => onEdit(annotation),
                      child: const Text('编辑'),
                    ),
                    TextButton(
                      onPressed: () => onDelete(annotation),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
