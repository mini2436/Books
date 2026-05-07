import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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

enum _TabletReaderPanel { toc, notes, bookmarks, settings }

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId, this.initialAnchor});

  final int? bookId;
  final String? initialAnchor;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _TabletReaderPanel? _tabletPanel;
  int _viewportTapZoneVersion = 0;
  String? _viewportTapZone;

  void _dispatchViewportTapZone(String zone) {
    setState(() {
      _viewportTapZone = zone;
      _viewportTapZoneVersion += 1;
    });
  }

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
    final desktop = Responsive.isDesktop(context);
    final windowsReader =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final wideReader = windowsReader || tablet || desktop;

    if (controller.isLoading && controller.currentChapter == null) {
      return Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(color: palette.background),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
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
    void handleChromeToggle() {
      if (wideReader && controller.uiVisible) {
        setState(() {
          _tabletPanel = null;
        });
      }
      controller.toggleUi();
    }

    void handleTabletMenuRequest() {
      if (!wideReader) {
        controller.toggleUi();
        return;
      }
      if (!controller.uiVisible) {
        controller.setUiVisible(true);
        return;
      }
      setState(() {
        _tabletPanel ??= _TabletReaderPanel.settings;
      });
    }

    final body = chapter == null
        ? const Center(child: CircularProgressIndicator())
        : ReaderHtmlView(
            chapter: chapter,
            imageResources: controller.imageResourceBytes,
            failedImageResourceIds: controller.failedImageResourceIds,
            annotations: controller.annotations,
            preferences: preferences,
            palette: palette,
            uiVisible: controller.uiVisible,
            pagedMode: wideReader,
            dualColumn: wideReader,
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
            onSaveAnnotation:
                (
                  selection,
                  existingAnnotation, {
                  required noteText,
                  required color,
                  required underlineStyle,
                }) async {
                  if (existingAnnotation == null) {
                    await controller.addAnnotation(
                      selection: selection,
                      noteText: noteText,
                      color: color,
                      underlineStyle: underlineStyle,
                    );
                    return;
                  }
                  await controller.updateAnnotation(
                    annotation: existingAnnotation,
                    noteText: noteText ?? existingAnnotation.noteText,
                    color: color,
                    selection: selection,
                    underlineStyle: underlineStyle,
                  );
                },
            onOpenAnnotations: (annotations) =>
                _openAnnotationsFromReader(controller, annotations),
            onVisibleAnchorChanged: controller.updateVisibleAnchor,
            onPageBoundaryPrevious: controller.previousChapterFromPageBoundary,
            onPageBoundaryNext: controller.nextChapterFromPageBoundary,
            onToggleUi: handleChromeToggle,
            onMenuRequest: handleTabletMenuRequest,
            viewportTapZone: _viewportTapZone,
            viewportTapZoneVersion: _viewportTapZoneVersion,
          );

    if (wideReader) {
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _dispatchViewportTapZone('left'),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _dispatchViewportTapZone('right'),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              _dispatchViewportTapZone('center'),
          const SingleActivator(LogicalKeyboardKey.keyM):
              handleTabletMenuRequest,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_tabletPanel != null) {
              setState(() => _tabletPanel = null);
              return;
            }
            if (!controller.uiVisible) {
              controller.setUiVisible(true);
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: palette.background),
                          child: Stack(
                            children: [
                              Positioned.fill(child: body),
                              if (controller.hasPendingChapterLoad)
                                const Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: LinearProgressIndicator(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 18,
                    left: 24,
                    right: 28,
                    child: _TabletChromeVisibility(
                      visible: controller.uiVisible,
                      offset: const Offset(0, -0.06),
                      child: _TabletReaderHeader(
                        detail: detail,
                        controller: controller,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 20,
                    top: 112,
                    child: _TabletChromeVisibility(
                      visible: controller.uiVisible,
                      offset: const Offset(0.08, 0),
                      child: _TabletReaderDock(
                        activePanel: _tabletPanel,
                        onSelectPanel: _toggleTabletPanel,
                        onAddBookmark: controller.addBookmark,
                        bookmarkDisabled: controller.hasCurrentLocationBookmark,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 28,
                    bottom: 24,
                    child: _TabletChromeVisibility(
                      visible: controller.uiVisible,
                      offset: const Offset(-0.08, 0),
                      child: _TabletReaderProgressChip(
                        controller: controller,
                        onPreviousPage: () => _dispatchViewportTapZone('left'),
                        onToggleChrome: () =>
                            _dispatchViewportTapZone('center'),
                        onNextPage: () => _dispatchViewportTapZone('right'),
                      ),
                    ),
                  ),
                  _TabletReaderPanelScrim(
                    visible: _tabletPanel != null,
                    onTap: () => setState(() => _tabletPanel = null),
                  ),
                  _TabletReaderPanelHost(
                    panel: _tabletPanel,
                    controller: controller,
                    onClose: () => setState(() => _tabletPanel = null),
                    onEditAnnotation: (annotation) => _openAnnotationComposer(
                      controller,
                      annotation: annotation,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(child: _ReaderLeftPanel(controller: controller)),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(
                  16,
                  controller.uiVisible ? 86 : 24,
                  16,
                  controller.uiVisible ? 108 : 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chapter?.title ?? detail.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
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
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TabletChromeVisibility(
                visible: controller.uiVisible,
                offset: const Offset(0, -0.08),
                child: _MobileReaderTopBar(
                  title: detail.title,
                  onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  onOpenBookmarks: () => _openBookmarksSheet(controller),
                  onOpenNotes: () => _openNotesSheet(controller),
                  onOpenSettings: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => const ReaderSettingsSheet(),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _TabletChromeVisibility(
                visible: controller.uiVisible,
                offset: const Offset(0, 0.12),
                child: _MobileReaderBottomBar(controller: controller),
              ),
            ),
          ],
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

  Future<void> _openBookmarksSheet(ReaderController controller) {
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
              child: _ReaderBookmarksManager(
                controller: controller,
                onClose: () => Navigator.of(context).pop(),
              ),
            );
          },
        ),
      ),
    );
  }

  void _toggleTabletPanel(_TabletReaderPanel panel) {
    setState(() {
      _tabletPanel = _tabletPanel == panel ? null : panel;
    });
  }

  Future<void> _openAnnotationComposer(
    ReaderController controller, {
    AnnotationSelection? selection,
    AnnotationView? annotation,
  }) async {
    final existingAnchor = annotation == null
        ? null
        : AnnotationAnchor.parse(annotation.anchor);
    final palette = AppReaderPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.background,
      barrierColor: palette.mask,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Material(
        color: palette.background,
        child: _AnnotationComposerSheet(
          selectedText: selection?.selectedText ?? annotation?.quoteText ?? '',
          annotation: annotation,
          defaultColor: _defaultAnnotationColor(
            ref.read(readerPreferencesControllerProvider).themeMode,
          ),
          initialUnderlineStyle:
              existingAnchor?.underlineStyle ?? AnnotationUnderlineStyle.none,
          onSubmit:
              ({
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
    final palette = AppReaderPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.background,
      barrierColor: palette.mask,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Material(
        color: palette.background,
        child: SafeArea(
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
  })
  onSubmit;

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
    final mediaQuery = MediaQuery.of(context);
    final palette = AppReaderPalette.of(context);
    final maxSheetHeight =
        (mediaQuery.size.height - mediaQuery.padding.top) * 0.88;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom:
                mediaQuery.viewInsets.bottom + mediaQuery.padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.annotation == null ? '新增批注' : '编辑批注',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: palette.backgroundSoft,
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
                                color.toLowerCase() ==
                                _selectedColor.toLowerCase();
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedColor = color),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Color(
                                    int.parse('0xFF${color.substring(1)}'),
                                  ),
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
                          children: AnnotationUnderlineStyle.values.map((
                            style,
                          ) {
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
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
        ),
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

class _TabletReaderHeader extends StatelessWidget {
  const _TabletReaderHeader({required this.detail, required this.controller});

  final BookDetail detail;
  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final chapterTitle = controller.currentChapter?.title ?? detail.title;

    return Material(
      color: palette.panel.withValues(alpha: 0.94),
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletReaderDock extends StatelessWidget {
  const _TabletReaderDock({
    required this.activePanel,
    required this.onSelectPanel,
    required this.onAddBookmark,
    required this.bookmarkDisabled,
  });

  final _TabletReaderPanel? activePanel;
  final ValueChanged<_TabletReaderPanel> onSelectPanel;
  final Future<void> Function() onAddBookmark;
  final bool bookmarkDisabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Material(
      color: palette.panel.withValues(alpha: 0.96),
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TabletDockButton(
              icon: Icons.menu_book_outlined,
              tooltip: '目录',
              selected: activePanel == _TabletReaderPanel.toc,
              onPressed: () => onSelectPanel(_TabletReaderPanel.toc),
            ),
            _TabletDockButton(
              icon: Icons.sticky_note_2_outlined,
              tooltip: '批注',
              selected: activePanel == _TabletReaderPanel.notes,
              onPressed: () => onSelectPanel(_TabletReaderPanel.notes),
            ),
            _TabletDockButton(
              icon: Icons.bookmarks_outlined,
              tooltip: '书签',
              selected: activePanel == _TabletReaderPanel.bookmarks,
              onPressed: () => onSelectPanel(_TabletReaderPanel.bookmarks),
            ),
            _TabletDockButton(
              icon: Icons.bookmark_add_outlined,
              tooltip: bookmarkDisabled ? '当前位置已加书签' : '添加当前位置书签',
              onPressed: bookmarkDisabled ? null : () => onAddBookmark(),
            ),
            _TabletDockButton(
              icon: Icons.tune,
              tooltip: '阅读设置',
              selected: activePanel == _TabletReaderPanel.settings,
              onPressed: () => onSelectPanel(_TabletReaderPanel.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletDockButton extends StatelessWidget {
  const _TabletDockButton({
    required this.icon,
    required this.tooltip,
    this.selected = false,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected
              ? palette.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon),
            color: selected ? palette.accent : palette.inkSecondary,
          ),
        ),
      ),
    );
  }
}

class _TabletReaderProgressChip extends StatelessWidget {
  const _TabletReaderProgressChip({
    required this.controller,
    required this.onPreviousPage,
    required this.onToggleChrome,
    required this.onNextPage,
  });

  final ReaderController controller;
  final VoidCallback onPreviousPage;
  final VoidCallback onToggleChrome;
  final VoidCallback onNextPage;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Material(
      color: palette.panel.withValues(alpha: 0.96),
      elevation: 10,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TabletProgressButton(
              icon: Icons.chevron_left,
              tooltip: '上一页',
              onPressed: onPreviousPage,
            ),
            const SizedBox(width: 8),
            Text(
              '${controller.progressPercent.toStringAsFixed(1)}%',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.backgroundSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TabletProgressButton(
                    icon: Icons.tune,
                    tooltip: '显示/隐藏界面',
                    onPressed: onToggleChrome,
                    compact: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '菜单',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _TabletProgressButton(
              icon: Icons.chevron_right,
              tooltip: '下一页',
              onPressed: onNextPage,
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletProgressButton extends StatelessWidget {
  const _TabletProgressButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 6,
            vertical: compact ? 6 : 4,
          ),
          child: Icon(
            icon,
            size: compact ? 16 : 20,
            color: palette.inkSecondary,
          ),
        ),
      ),
    );
  }
}

class _TabletChromeVisibility extends StatelessWidget {
  const _TabletChromeVisibility({
    required this.visible,
    required this.offset,
    required this.child,
  });

  final bool visible;
  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: visible ? Offset.zero : offset,
          child: child,
        ),
      ),
    );
  }
}

class _MobileReaderTopBar extends StatelessWidget {
  const _MobileReaderTopBar({
    required this.title,
    required this.onOpenMenu,
    required this.onOpenBookmarks,
    required this.onOpenNotes,
    required this.onOpenSettings,
  });

  final String title;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onOpenNotes;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.panel.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              IconButton(
                onPressed: onOpenMenu,
                icon: const Icon(Icons.menu_rounded),
                tooltip: '目录',
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onOpenBookmarks,
                icon: const Icon(Icons.bookmarks_outlined),
                tooltip: '书签',
              ),
              IconButton(
                onPressed: onOpenNotes,
                icon: const Icon(Icons.edit_note_rounded),
                tooltip: '批注',
              ),
              IconButton(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.tune_rounded),
                tooltip: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileReaderBottomBar extends StatelessWidget {
  const _MobileReaderBottomBar({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final chapterCount = controller.content?.chapters.length ?? 0;
    final chapterNumber = chapterCount == 0
        ? 0
        : controller.currentChapterIndex + 1;
    final progress = controller.progressPercent.clamp(0, 100);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.panel.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '阅读进度 ${progress.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 6,
                        backgroundColor: palette.backgroundSoft,
                        color: palette.accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      chapterCount <= 0
                          ? '正在计算章节进度'
                          : '第 $chapterNumber / $chapterCount 章',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
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

class _TabletReaderPanelScrim extends StatelessWidget {
  const _TabletReaderPanelScrim({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          opacity: visible ? 1 : 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: const ColoredBox(color: Color(0x12000000)),
          ),
        ),
      ),
    );
  }
}

class _TabletReaderPanelHost extends StatelessWidget {
  const _TabletReaderPanelHost({
    required this.panel,
    required this.controller,
    required this.onClose,
    required this.onEditAnnotation,
  });

  final _TabletReaderPanel? panel;
  final ReaderController controller;
  final VoidCallback onClose;
  final ValueChanged<AnnotationView> onEditAnnotation;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: panel == null,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          reverseDuration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            children: [
              ...previousChildren,
              ...?(currentChild != null ? [currentChild] : null),
            ],
          ),
          transitionBuilder: (child, animation) {
            final key = child.key;
            final panelValue = key is ValueKey<_TabletReaderPanel?>
                ? key.value
                : null;
            final alignLeft = panelValue == _TabletReaderPanel.toc;
            final slide =
                Tween<Offset>(
                  begin: alignLeft
                      ? const Offset(-0.08, 0)
                      : const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: panel == null
              ? const SizedBox.shrink(key: ValueKey<_TabletReaderPanel?>(null))
              : _TabletReaderPanelSheet(
                  key: ValueKey<_TabletReaderPanel?>(panel),
                  panel: panel!,
                  controller: controller,
                  onClose: onClose,
                  onEditAnnotation: onEditAnnotation,
                ),
        ),
      ),
    );
  }
}

class _TabletReaderPanelSheet extends StatelessWidget {
  const _TabletReaderPanelSheet({
    super.key,
    required this.panel,
    required this.controller,
    required this.onClose,
    required this.onEditAnnotation,
  });

  final _TabletReaderPanel panel;
  final ReaderController controller;
  final VoidCallback onClose;
  final ValueChanged<AnnotationView> onEditAnnotation;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final alignLeft = panel == _TabletReaderPanel.toc;
    final panelWidth = switch (panel) {
      _TabletReaderPanel.toc => 292.0,
      _TabletReaderPanel.settings => 344.0,
      _TabletReaderPanel.notes => 334.0,
      _TabletReaderPanel.bookmarks => 326.0,
    };
    final panelPadding = EdgeInsets.fromLTRB(
      alignLeft ? 28 : 0,
      92,
      alignLeft ? 0 : 98,
      24,
    );

    return Padding(
      padding: panelPadding,
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: alignLeft ? Alignment.topLeft : Alignment.topRight,
          child: SizedBox(
            width: panelWidth,
            height: constraints.maxHeight,
            child: Material(
              color: palette.panel,
              elevation: 20,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(26),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            switch (panel) {
                              _TabletReaderPanel.toc => '目录与书签',
                              _TabletReaderPanel.notes => '批注管理',
                              _TabletReaderPanel.bookmarks => '书签管理',
                              _TabletReaderPanel.settings => '阅读设置',
                            },
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: onClose,
                            icon: const Icon(Icons.close),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: switch (panel) {
                          _TabletReaderPanel.toc => _ReaderLeftPanel(
                            controller: controller,
                          ),
                          _TabletReaderPanel.notes => _ReaderNotesList(
                            annotations: controller.annotations,
                            onJump: (anchor) async {
                              onClose();
                              await controller.jumpToAnchor(anchor);
                            },
                            onDelete: controller.deleteAnnotation,
                            onEdit: onEditAnnotation,
                          ),
                          _TabletReaderPanel.bookmarks =>
                            _ReaderBookmarksManager(
                              controller: controller,
                              onClose: onClose,
                            ),
                          _TabletReaderPanel.settings =>
                            const ReaderSettingsPanelContent(
                              showHeader: false,
                              compact: true,
                            ),
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
    final compactTileDensity = const VisualDensity(
      horizontal: -2,
      vertical: -3,
    );

    return ColoredBox(
      color: palette.panel,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
        children: [
          Text(
            '目录',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...chapters.map((chapter) {
            final selected =
                chapter.chapterIndex == controller.currentChapterIndex;
            return ListTile(
              dense: true,
              minTileHeight: 0,
              visualDensity: compactTileDensity,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 1,
              ),
              title: Text(
                chapter.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              selected: selected,
              selectedTileColor: palette.accent.withValues(alpha: 0.08),
              onTap: () => controller.openChapter(chapter.chapterIndex),
            );
          }),
          const SizedBox(height: 14),
          Text(
            '书签',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
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
                dense: true,
                minTileHeight: 0,
                visualDensity: compactTileDensity,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 1,
                ),
                title: Text(
                  bookmark.label ?? bookmark.location,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  bookmark.updatedAt.split('T').first,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.inkTertiary),
                ),
                onTap: () => controller.jumpToAnchor(bookmark.location),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReaderBookmarksManager extends StatelessWidget {
  const _ReaderBookmarksManager({
    required this.controller,
    required this.onClose,
  });

  final ReaderController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final currentChapter = controller.currentChapter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.backgroundSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前书签',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.currentReadingLabel.isNotEmpty
                      ? controller.currentReadingLabel
                      : currentChapter?.title ?? '当前位置还在加载中',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onPressed:
                      currentChapter == null ||
                          controller.hasCurrentLocationBookmark
                      ? null
                      : controller.addBookmark,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(
                    controller.hasCurrentLocationBookmark
                        ? '当前位置已加入书签'
                        : '添加当前位置书签',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '历史书签',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('收起'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (controller.bookmarks.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                '还没有书签，先为当前位置加一个吧。',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: controller.bookmarks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final bookmark = controller.bookmarks[index];
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.backgroundSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookmark.label ?? bookmark.location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bookmark.updatedAt.split('T').first,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.inkTertiary),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () async {
                                onClose();
                                await controller.jumpToAnchor(
                                  bookmark.location,
                                );
                              },
                              icon: const Icon(Icons.near_me_outlined),
                              label: const Text('跳转'),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () =>
                                  _confirmDeleteBookmark(context, bookmark),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('删除'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDeleteBookmark(
    BuildContext context,
    BookmarkView bookmark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条书签？'),
        content: Text(
          bookmark.label?.trim().isNotEmpty == true
              ? '将从书签列表移除“${bookmark.label}”。'
              : '删除后将从历史书签中移除这条记录。',
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

    await controller.deleteBookmark(bookmark);
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
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final annotation = annotations[index];
        final color = annotation.color == null
            ? palette.accent
            : Color(int.parse('0xFF${annotation.color!.substring(1)}'));

        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.backgroundSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                  const SizedBox(height: 6),
                  Text(
                    annotation.noteText!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      annotation.updatedAt.split('T').first,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.inkTertiary,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => onJump(annotation.anchor),
                      child: const Text('定位'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => onEdit(annotation),
                      child: const Text('编辑'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
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
