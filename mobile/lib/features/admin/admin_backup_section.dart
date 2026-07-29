import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/admin_models.dart';
import '../../shared/localization/localized_text.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/widgets/centered_scale_dialog.dart';
import '../../shared/widgets/glass_action_button.dart';
import '../../shared/widgets/glass_dialog.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../data/services/backup_download_launcher.dart';
import 'admin_center_controller.dart';

const _allBackupUserDataTypes = <String>{
  'BOOK_ACCESS',
  'BOOK_GROUPS',
  'ANNOTATIONS',
  'BOOKMARKS',
  'READING_HISTORY',
  'READING_PROGRESS',
};

class AdminBackupSection extends ConsumerStatefulWidget {
  const AdminBackupSection({super.key, required this.controller});

  final AdminCenterController controller;

  @override
  ConsumerState<AdminBackupSection> createState() => _AdminBackupSectionState();
}

class _AdminBackupSectionState extends ConsumerState<AdminBackupSection> {
  PlatformFile? _selectedFile;
  AdminBackupPreview? _preview;
  bool _saving = false;
  String _exportScope = 'FULL';
  Set<int> _exportUserIds = <int>{};
  Set<int> _exportBookIds = <int>{};
  final Set<String> _exportDataTypes = {..._allBackupUserDataTypes};
  Map<int, int> _userMappings = <int, int>{};
  String _restoreScope = 'FULL';
  Set<String> _restoreDataTypes = {..._allBackupUserDataTypes};
  String _restoreMode = 'MERGE';

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.canManageBackups) {
      return const _BackupCard(
        child: _SectionIntroduction(
          icon: Icons.lock_outline_rounded,
          title: '仅超级管理员可使用备份恢复',
          body: '完整备份包含账号、书籍和阅读数据，馆员账号无法导出或覆盖系统数据。',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BackupCard(
          child: _SectionIntroduction(
            icon: Icons.shield_outlined,
            title: '系统备份与恢复',
            body: '完整保存数据库、封面、正文缓存以及服务器当前可读取的书籍原文件。建议在升级或迁移前生成一份新备份。',
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final operation = widget.controller.backupOperation;
            final exportPanel = _ExportPanel(
              isDisabled: widget.controller.isWorking || _saving,
              isExporting:
                  operation == AdminBackupOperation.exporting || _saving,
              onExport: _exportBackup,
              scope: _exportScope,
              selectedUserCount: _exportUserIds.length,
              selectedBookCount: _exportBookIds.length,
              dataTypes: _exportDataTypes,
              canExport:
                  _exportScope != 'USER_DATA' || _exportUserIds.isNotEmpty,
              onScopeChanged: (value) => setState(() {
                _exportScope = value;
                _exportBookIds.clear();
              }),
              onSelectUsers: _selectExportUsers,
              onSelectBooks: _selectExportBooks,
              onDataTypeChanged: (type, selected) => setState(() {
                if (selected) {
                  _exportDataTypes.add(type);
                } else if (_exportDataTypes.length > 1) {
                  _exportDataTypes.remove(type);
                }
              }),
            );
            final restorePanel = _RestorePanel(
              selectedFile: _selectedFile,
              preview: _preview,
              isBusy: widget.controller.isWorking,
              operation: operation,
              progress: widget.controller.backupProgress,
              startedAt: widget.controller.backupOperationStartedAt,
              onPick: _pickBackup,
              onClear: _clearSelection,
              onRestore: _confirmAndRestore,
              targetUsers: widget.controller.users,
              userMappings: _userMappings,
              restoreScope: _restoreScope,
              restoreDataTypes: _restoreDataTypes,
              restoreMode: _restoreMode,
              onRestoreScopeChanged: (value) => setState(() {
                _restoreScope = value;
                _userMappings.clear();
                _restoreMode = 'MERGE';
              }),
              onRestoreDataTypeChanged: (type, selected) => setState(() {
                if (selected) {
                  _restoreDataTypes.add(type);
                } else if (_restoreDataTypes.length > 1) {
                  _restoreDataTypes.remove(type);
                }
              }),
              onMappingChanged: (sourceId, targetId) => setState(() {
                if (targetId == null) {
                  _userMappings.remove(sourceId);
                } else {
                  _userMappings[sourceId] = targetId;
                }
              }),
              onRestoreModeChanged: (value) =>
                  setState(() => _restoreMode = value),
            );
            if (constraints.maxWidth >= 840) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: exportPanel),
                    const SizedBox(width: 14),
                    Expanded(child: restorePanel),
                  ],
                ),
              );
            }
            return Column(
              children: [exportPanel, const SizedBox(height: 14), restorePanel],
            );
          },
        ),
      ],
    );
  }

  Future<void> _exportBackup() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      final scopeName = _exportScope.toLowerCase().replaceAll('_', '-');
      final fileName = 'private-reader-$scopeName-$stamp.zip';
      final controller = ref.read(adminCenterControllerProvider);
      if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
        final downloadUrl = await controller.createBackupDownloadUrl(
          scope: _exportScope,
          userIds: _exportUserIds.toList(),
          bookIds: _exportBookIds.toList(),
          dataTypes: _exportDataTypes.toList(),
        );
        if (downloadUrl == null || !mounted) return;
        await startSystemBackupDownload(downloadUrl, fileName);
        if (mounted) controller.markBackupSaved();
        return;
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存轻阅备份',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        lockParentWindow: true,
      );
      if (path == null || !mounted) return;
      final saved = await controller.exportBackupToFile(
        destinationPath: path,
        scope: _exportScope,
        userIds: _exportUserIds.toList(),
        bookIds: _exportBookIds.toList(),
        dataTypes: _exportDataTypes.toList(),
      );
      if (saved && mounted) {
        controller.markBackupSaved();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('备份已生成，但未能保存到所选位置。')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBackup() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择轻阅备份',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
      withData: kIsWeb,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    setState(() {
      _selectedFile = file;
      _preview = null;
    });
    final preview = await ref
        .read(adminCenterControllerProvider)
        .previewBackup(
          fileName: file.name,
          filePath: file.path,
          fileBytes: file.bytes,
        );
    if (!mounted || _selectedFile != file) return;
    setState(() {
      _preview = preview;
      _userMappings = <int, int>{};
      _restoreScope = preview?.scope ?? 'FULL';
      _restoreDataTypes = preview == null
          ? {..._allBackupUserDataTypes}
          : preview.dataTypes.isEmpty
          ? {..._allBackupUserDataTypes}
          : preview.dataTypes.toSet();
      _restoreMode = 'MERGE';
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedFile = null;
      _preview = null;
      _userMappings.clear();
      _restoreScope = 'FULL';
      _restoreDataTypes = {..._allBackupUserDataTypes};
      _restoreMode = 'MERGE';
    });
  }

  Future<void> _confirmAndRestore() async {
    final file = _selectedFile;
    final preview = _preview;
    if (file == null || preview == null) return;
    if (_restoreScope == 'USER_DATA' && _userMappings.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个源用户并指定当前系统的目标用户。')));
      return;
    }
    if (_restoreScope == 'USER_DATA' && _restoreDataTypes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一种要恢复的用户数据。')));
      return;
    }
    final bool? confirmed;
    if (_restoreScope == 'FULL') {
      confirmed = await showCenteredScaleDialog<bool>(
        context,
        barrierDismissible: false,
        builder: (context) => _RestoreConfirmationDialog(preview: preview),
      );
    } else {
      confirmed = await showCenteredScaleDialog<bool>(
        context,
        builder: (context) => _ScopedRestoreConfirmationDialog(
          preview: preview,
          restoreScope: _restoreScope,
          dataTypes: _restoreDataTypes,
          replace: _restoreMode == 'REPLACE',
        ),
      );
    }
    if (confirmed != true || !mounted) return;
    await ref
        .read(adminCenterControllerProvider)
        .restoreBackup(
          fileName: file.name,
          filePath: file.path,
          fileBytes: file.bytes,
          restoreScope: _restoreScope,
          userMappings: _restoreScope == 'USER_DATA' ? _userMappings : null,
          dataTypes: _restoreScope == 'USER_DATA'
              ? _restoreDataTypes.toList()
              : const [],
          mode: _restoreMode,
        );
  }

  Future<void> _selectExportUsers() async {
    final selected = await _showMultiSelectDialog<AdminUserView>(
      title: '选择要备份的用户',
      items: widget.controller.users,
      selectedIds: _exportUserIds,
      idOf: (item) => item.id,
      labelOf: (item) => item.username,
    );
    if (selected != null && mounted) setState(() => _exportUserIds = selected);
  }

  Future<void> _selectExportBooks() async {
    final selected = await _showMultiSelectDialog<AdminBookSummary>(
      title: _exportScope == 'BOOKS' ? '选择要备份的书籍' : '限制到指定书籍（可选）',
      items: widget.controller.books,
      selectedIds: _exportBookIds,
      idOf: (item) => item.id,
      labelOf: (item) => item.author?.trim().isNotEmpty == true
          ? '${item.title} · ${item.author}'
          : item.title,
    );
    if (selected != null && mounted) setState(() => _exportBookIds = selected);
  }

  Future<Set<int>?> _showMultiSelectDialog<T>({
    required String title,
    required List<T> items,
    required Set<int> selectedIds,
    required int Function(T item) idOf,
    required String Function(T item) labelOf,
  }) {
    final working = {...selectedIds};
    return showCenteredScaleDialog<Set<int>>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => GlassAlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('当前没有可选择的数据。'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final id = idOf(item);
                      return CheckboxListTile(
                        value: working.contains(id),
                        title: Text(labelOf(item)),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (selected) => setDialogState(() {
                          selected == true
                              ? working.add(id)
                              : working.remove(id);
                        }),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(working),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportPanel extends StatelessWidget {
  const _ExportPanel({
    required this.isDisabled,
    required this.isExporting,
    required this.onExport,
    required this.scope,
    required this.selectedUserCount,
    required this.selectedBookCount,
    required this.dataTypes,
    required this.canExport,
    required this.onScopeChanged,
    required this.onSelectUsers,
    required this.onSelectBooks,
    required this.onDataTypeChanged,
  });

  final bool isDisabled;
  final bool isExporting;
  final VoidCallback onExport;
  final String scope;
  final int selectedUserCount;
  final int selectedBookCount;
  final Set<String> dataTypes;
  final bool canExport;
  final ValueChanged<String> onScopeChanged;
  final VoidCallback onSelectUsers;
  final VoidCallback onSelectBooks;
  final void Function(String type, bool selected) onDataTypeChanged;

  @override
  Widget build(BuildContext context) {
    return _BackupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeading(
            icon: Icons.archive_outlined,
            title: '导出备份',
            body: scope == 'FULL'
                ? '生成可完整迁移到另一套轻阅服务的 ZIP 文件。'
                : scope == 'BOOKS'
                ? '仅导出书籍、封面、正文缓存与原文件。'
                : '按用户和数据类型导出阅读数据，恢复时再映射目标用户。',
          ),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'FULL', label: Text('全量')),
              ButtonSegment(value: 'BOOKS', label: Text('书籍')),
              ButtonSegment(value: 'USER_DATA', label: Text('用户数据')),
            ],
            selected: {scope},
            onSelectionChanged: isDisabled
                ? null
                : (value) => onScopeChanged(value.first),
          ),
          const SizedBox(height: 18),
          if (scope == 'FULL') ...[
            const _IncludedItem(
              icon: Icons.storage_rounded,
              label: '账号、权限与系统配置',
            ),
            const _IncludedItem(
              icon: Icons.menu_book_rounded,
              label: '书籍、封面与结构化正文',
            ),
            const _IncludedItem(
              icon: Icons.history_rounded,
              label: '批注、书签、阅读历史与进度',
            ),
          ] else if (scope == 'BOOKS') ...[
            _SelectionButton(
              icon: Icons.menu_book_outlined,
              label: selectedBookCount == 0
                  ? '全部书籍'
                  : '已选择 $selectedBookCount 本书',
              onPressed: isDisabled ? null : onSelectBooks,
            ),
            const SizedBox(height: 10),
            Text(
              '不选择时导出全部书籍；相同文件会在恢复时自动去重。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppReaderPalette.of(context).inkSecondary,
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _SelectionButton(
                    icon: Icons.people_outline_rounded,
                    label: selectedUserCount == 0
                        ? '选择用户（必选）'
                        : '已选择 $selectedUserCount 个用户',
                    onPressed: isDisabled ? null : onSelectUsers,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SelectionButton(
                    icon: Icons.menu_book_outlined,
                    label: selectedBookCount == 0
                        ? '全部相关书籍'
                        : '限定 $selectedBookCount 本',
                    onPressed: isDisabled ? null : onSelectBooks,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _userDataTypeLabels.entries.map((entry) {
                return FilterChip(
                  label: Text(entry.value),
                  selected: dataTypes.contains(entry.key),
                  onSelected: isDisabled
                      ? null
                      : (selected) => onDataTypeChanged(entry.key, selected),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: GlassActionButton(
              label: isExporting
                  ? '正在生成备份'
                  : scope == 'FULL'
                  ? '导出全量备份'
                  : scope == 'BOOKS'
                  ? '导出书籍备份'
                  : '导出用户数据',
              icon: Icons.download_rounded,
              loading: isExporting,
              onPressed: isDisabled || !canExport ? null : onExport,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '备份不会暂停阅读服务，但大书库导出期间会增加磁盘读取压力。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppReaderPalette.of(context).inkSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _RestorePanel extends StatelessWidget {
  const _RestorePanel({
    required this.selectedFile,
    required this.preview,
    required this.isBusy,
    required this.operation,
    required this.progress,
    required this.startedAt,
    required this.onPick,
    required this.onClear,
    required this.onRestore,
    required this.targetUsers,
    required this.userMappings,
    required this.restoreScope,
    required this.restoreDataTypes,
    required this.restoreMode,
    required this.onRestoreScopeChanged,
    required this.onRestoreDataTypeChanged,
    required this.onMappingChanged,
    required this.onRestoreModeChanged,
  });

  final PlatformFile? selectedFile;
  final AdminBackupPreview? preview;
  final bool isBusy;
  final AdminBackupOperation operation;
  final AdminBackupProgress? progress;
  final DateTime? startedAt;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final VoidCallback onRestore;
  final List<AdminUserView> targetUsers;
  final Map<int, int> userMappings;
  final String restoreScope;
  final Set<String> restoreDataTypes;
  final String restoreMode;
  final ValueChanged<String> onRestoreScopeChanged;
  final void Function(String type, bool selected) onRestoreDataTypeChanged;
  final void Function(int sourceId, int? targetId) onMappingChanged;
  final ValueChanged<String> onRestoreModeChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return _BackupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeading(
            icon: Icons.settings_backup_restore_rounded,
            title: '导入与恢复',
            body: '先校验备份类型和内容，再按范围恢复到当前系统。',
          ),
          const SizedBox(height: 18),
          if (selectedFile == null)
            _FileDropArea(isBusy: isBusy, onPick: onPick)
          else ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.backgroundSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.folder_zip_outlined, color: palette.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedFile!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatBytes(selectedFile!.size),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.inkSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '移除文件',
                      onPressed: isBusy ? null : onClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (operation == AdminBackupOperation.previewing && preview == null)
              const _PreviewLoading()
            else if (preview != null)
              _BackupSummary(preview: preview!),
            if (preview?.isFull == true) ...[
              const SizedBox(height: 16),
              _RestoreScopeSelector(
                value: restoreScope,
                enabled: !isBusy,
                onChanged: onRestoreScopeChanged,
              ),
            ],
            if (preview != null && restoreScope == 'USER_DATA') ...[
              const SizedBox(height: 16),
              _RestoreDataTypeSelector(
                preview: preview!,
                availableTypes: preview!.dataTypes.isEmpty
                    ? _allBackupUserDataTypes
                    : preview!.dataTypes.toSet(),
                selectedTypes: restoreDataTypes,
                enabled: !isBusy,
                onChanged: onRestoreDataTypeChanged,
              ),
              const SizedBox(height: 16),
              _UserMappingEditor(
                sourceUsers: preview!.sourceUsers,
                targetUsers: targetUsers,
                mappings: userMappings,
                mode: restoreMode,
                enabled: !isBusy,
                onMappingChanged: onMappingChanged,
                onModeChanged: onRestoreModeChanged,
              ),
            ],
            if (progress != null &&
                (operation == AdminBackupOperation.restoring ||
                    progress!.isFailed ||
                    progress!.isCompleted)) ...[
              const SizedBox(height: 16),
              _RestoreProgressPanel(progress: progress!, startedAt: startedAt),
            ],
          ],
          const SizedBox(height: 16),
          _RiskNotice(
            palette: palette,
            preview: preview,
            restoreScope: restoreScope,
            restoreDataTypes: restoreDataTypes,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: restoreScope == 'FULL' && preview != null
                    ? Theme.of(context).colorScheme.error
                    : null,
                foregroundColor: restoreScope == 'FULL' && preview != null
                    ? Theme.of(context).colorScheme.onError
                    : null,
              ),
              onPressed:
                  preview == null ||
                      isBusy ||
                      (restoreScope == 'USER_DATA' &&
                          (userMappings.isEmpty || restoreDataTypes.isEmpty))
                  ? null
                  : onRestore,
              icon: const Icon(Icons.restore_rounded),
              label: Text(
                operation == AdminBackupOperation.restoring
                    ? '正在恢复 ${progress?.percent ?? 0}%'
                    : operation == AdminBackupOperation.previewing
                    ? '正在校验备份'
                    : restoreScope == 'FULL'
                    ? '开始全量恢复'
                    : restoreScope == 'BOOKS'
                    ? '导入书籍备份'
                    : '恢复用户数据',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileDropArea extends StatelessWidget {
  const _FileDropArea({required this.isBusy, required this.onPick});

  final bool isBusy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.upload_file_rounded, size: 32, color: palette.accent),
              const SizedBox(height: 10),
              Text(
                '选择轻阅备份文件',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '仅支持由系统导出的 .zip 文件',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: isBusy ? null : onPick,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('选择文件'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupSummary extends StatelessWidget {
  const _BackupSummary({required this.preview});

  final AdminBackupPreview preview;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 18, color: palette.accent),
            const SizedBox(width: 8),
            Text(
              '备份校验通过',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '格式 v${preview.formatVersion}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${_backupScopeLabel(preview.scope)} · 创建于 ${_formatDateTime(preview.createdAt)}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip(label: '用户', value: preview.sourceUsers.length),
            _CountChip(label: '书籍', value: preview.books),
            _CountChip(label: '批注', value: preview.annotations),
            _CountChip(label: '书签', value: preview.bookmarks),
            _CountChip(label: '历史', value: preview.histories),
            _CountChip(label: '进度', value: preview.progresses),
          ],
        ),
      ],
    );
  }
}

class _RestoreScopeSelector extends StatelessWidget {
  const _RestoreScopeSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择恢复范围',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              '全量备份包含完整数据，但不必全部覆盖；可以只导入书籍，或只恢复指定用户的阅读数据。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.inkSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'FULL',
                    icon: Icon(Icons.storage_rounded, size: 17),
                    label: Text('完整系统'),
                  ),
                  ButtonSegment(
                    value: 'BOOKS',
                    icon: Icon(Icons.menu_book_rounded, size: 17),
                    label: Text('仅书籍'),
                  ),
                  ButtonSegment(
                    value: 'USER_DATA',
                    icon: Icon(Icons.person_outline_rounded, size: 17),
                    label: Text('用户数据'),
                  ),
                ],
                selected: {value},
                onSelectionChanged: enabled
                    ? (selection) => onChanged(selection.first)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreDataTypeSelector extends StatelessWidget {
  const _RestoreDataTypeSelector({
    required this.preview,
    required this.availableTypes,
    required this.selectedTypes,
    required this.enabled,
    required this.onChanged,
  });

  final AdminBackupPreview preview;
  final Set<String> availableTypes;
  final Set<String> selectedTypes;
  final bool enabled;
  final void Function(String type, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择用户数据',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              '只恢复勾选的类型；选择“替换所选范围”时，也只会清理这些类型对应的数据。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.inkSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allBackupUserDataTypes
                  .where(availableTypes.contains)
                  .map((type) {
                    final count = _restoreDataTypeCount(preview, type);
                    return FilterChip(
                      selected: selectedTypes.contains(type),
                      onSelected: enabled
                          ? (selected) => onChanged(type, selected)
                          : null,
                      label: Text(
                        count == null
                            ? _userDataTypeLabels[type] ?? type
                            : '${_userDataTypeLabels[type] ?? type} $count',
                      ),
                    );
                  })
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserMappingEditor extends StatelessWidget {
  const _UserMappingEditor({
    required this.sourceUsers,
    required this.targetUsers,
    required this.mappings,
    required this.mode,
    required this.enabled,
    required this.onMappingChanged,
    required this.onModeChanged,
  });

  final List<AdminBackupUserView> sourceUsers;
  final List<AdminUserView> targetUsers;
  final Map<int, int> mappings;
  final String mode;
  final bool enabled;
  final void Function(int sourceId, int? targetId) onMappingChanged;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '目标用户映射',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              '只为需要恢复的源用户选择目标用户；未选择的用户会保持跳过，源系统 ID 不会直接使用。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: palette.inkSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ...sourceUsers.map(
              (source) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<int>(
                  key: ValueKey('${source.id}-${mappings[source.id]}'),
                  initialValue: mappings[source.id],
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: source.displayName?.trim().isNotEmpty == true
                        ? '${source.displayName} · ${source.username}'
                        : source.username,
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  hint: const Text('选择当前系统用户'),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text('不恢复此用户'),
                    ),
                    ...targetUsers.map(
                      (target) => DropdownMenuItem<int>(
                        value: target.id,
                        child: Text(
                          target.username,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: enabled
                      ? (value) => onMappingChanged(source.id, value)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 2),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'MERGE', label: Text('合并数据')),
                ButtonSegment(value: 'REPLACE', label: Text('替换所选范围')),
              ],
              selected: {mode},
              onSelectionChanged: enabled
                  ? (value) => onModeChanged(value.first)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopedRestoreConfirmationDialog extends StatelessWidget {
  const _ScopedRestoreConfirmationDialog({
    required this.preview,
    required this.restoreScope,
    required this.dataTypes,
    required this.replace,
  });

  final AdminBackupPreview preview;
  final String restoreScope;
  final Set<String> dataTypes;
  final bool replace;

  @override
  Widget build(BuildContext context) {
    final isBooks = restoreScope == 'BOOKS';
    final selectedLabels = _allBackupUserDataTypes
        .where(dataTypes.contains)
        .map((type) => _userDataTypeLabels[type] ?? type)
        .join('、');
    return GlassAlertDialog(
      title: Text(isBooks ? '确认导入书籍？' : '确认恢复用户数据？'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text(
          isBooks
              ? '将导入 ${preview.books} 本书。当前系统中原文件相同的书籍会自动跳过，不会覆盖用户阅读数据。'
              : replace
              ? '将只替换已映射用户的“$selectedLabels”。其他用户和未勾选的数据类型保持不变。'
              : '将把已选择的“$selectedLabels”合并到目标用户；未勾选的数据类型保持不变。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(isBooks ? '确认导入' : '确认恢复'),
        ),
      ],
    );
  }
}

class _RestoreConfirmationDialog extends StatefulWidget {
  const _RestoreConfirmationDialog({required this.preview});

  final AdminBackupPreview preview;

  @override
  State<_RestoreConfirmationDialog> createState() =>
      _RestoreConfirmationDialogState();
}

class _RestoreConfirmationDialogState
    extends State<_RestoreConfirmationDialog> {
  final _confirmationController = TextEditingController();

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = _confirmationController.text.trim() == '恢复系统';
    return GlassAlertDialog(
      title: const Text('确认覆盖当前系统？'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '当前系统中的账号、书籍和阅读数据将被备份内容替换。完成后所有设备都需要重新登录。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onErrorContainer,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '请输入“恢复系统”继续',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmationController,
              autofocus: true,
              decoration: const InputDecoration(hintText: '恢复系统'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('确认全量恢复'),
        ),
      ],
    );
  }
}

class _SectionIntroduction extends StatelessWidget {
  const _SectionIntroduction({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _PanelHeading(icon: icon, title: title, body: body, prominent: true);
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.icon,
    required this.title,
    required this.body,
    this.prominent = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: palette.accent),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    (prominent
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.inkSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IncludedItem extends StatelessWidget {
  const _IncludedItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Icon(icon, size: 19, color: palette.inkSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Icon(Icons.check_rounded, size: 18, color: palette.accent),
        ],
      ),
    );
  }
}

class _RiskNotice extends StatelessWidget {
  const _RiskNotice({
    required this.palette,
    required this.preview,
    required this.restoreScope,
    required this.restoreDataTypes,
  });

  final AppReaderPalette palette;
  final AdminBackupPreview? preview;
  final String restoreScope;
  final Set<String> restoreDataTypes;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: palette.inkSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            preview != null && restoreScope == 'FULL'
                ? '全量恢复不可撤销。请先导出当前系统备份，并确认文件来源可信。'
                : preview != null && restoreScope == 'USER_DATA'
                ? '只处理已映射用户和勾选的 ${restoreDataTypes.length} 类数据；替换模式不会影响其他类型。'
                : '系统会先校验文件；相同原文件的书籍会自动去重。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.inkSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionButton extends StatelessWidget {
  const _SelectionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text('正在校验备份内容…'),
      ],
    );
  }
}

class _RestoreProgressPanel extends StatelessWidget {
  const _RestoreProgressPanel({
    required this.progress,
    required this.startedAt,
  });

  final AdminBackupProgress progress;
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt!);
    final detail = progress.total > 0
        ? '${progress.current}/${progress.total}'
        : '${progress.percent}%';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  progress.isFailed
                      ? Icons.error_outline_rounded
                      : progress.isCompleted
                      ? Icons.check_circle_outline_rounded
                      : Icons.sync_rounded,
                  size: 19,
                  color: progress.isFailed
                      ? Theme.of(context).colorScheme.error
                      : palette.accent,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    progress.message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress.percent.clamp(0, 100) / 100,
              minHeight: 7,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 9),
            Text(
              '总进度 ${progress.percent}% · 已用时 ${_formatElapsed(elapsed)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          '$label $value',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GlassCard(child: child);
}

const _userDataTypeLabels = <String, String>{
  'BOOK_ACCESS': '书籍权限',
  'BOOK_GROUPS': '个人分组',
  'ANNOTATIONS': '批注',
  'BOOKMARKS': '书签',
  'READING_HISTORY': '阅读历史',
  'READING_PROGRESS': '阅读进度',
};

int? _restoreDataTypeCount(AdminBackupPreview preview, String type) =>
    switch (type) {
      'ANNOTATIONS' => preview.annotations,
      'BOOKMARKS' => preview.bookmarks,
      'READING_HISTORY' => preview.histories,
      'READING_PROGRESS' => preview.progresses,
      _ => null,
    };

String _backupScopeLabel(String scope) => switch (scope) {
  'FULL' => '全量备份',
  'BOOKS' => '书籍备份',
  'USER_DATA' => '用户数据备份',
  _ => scope,
};

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _formatDateTime(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}

String _formatElapsed(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds.remainder(60);
  if (minutes <= 0) return '$seconds 秒';
  return '$minutes 分 ${seconds.toString().padLeft(2, '0')} 秒';
}
