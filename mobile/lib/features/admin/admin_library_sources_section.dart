import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:private_reader_mobile/shared/localization/localized_text.dart';
import 'package:private_reader_mobile/shared/localization/app_localizations.dart';

import '../../data/models/admin_models.dart';
import '../../data/services/local_library_folder_picker.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_dialog.dart';
import 'admin_center_controller.dart';

class AdminLibrarySourcesSection extends ConsumerWidget {
  const AdminLibrarySourcesSection({super.key, required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionCard(
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
                          '资源扫描入库',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '本地目录由当前设备手动选择并按需上传；只有 WebDAV 支持服务端定时扫描。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: controller.isWorking
                        ? null
                        : () => _showSourceDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('新增扫描源'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaChip(
                    icon: Icons.sync_alt_rounded,
                    label: '${controller.librarySourceCount} 个扫描源',
                  ),
                  _MetaChip(
                    icon: Icons.history_rounded,
                    label: '${controller.importJobCount} 条近期记录',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (controller.librarySources.isEmpty)
          const _SectionCard(
            child: _EmptyBlock(
              title: '还没有扫描源',
              body: '添加本地上传目录或 WebDAV。普通目录需要手动选择后刷新，避免多端文件权限失效。',
            ),
          )
        else
          ...controller.librarySources.map(
            (source) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _LibrarySourceCard(
                source: source,
                controller: controller,
                onEdit: () => _showSourceDialog(context, ref, source: source),
              ),
            ),
          ),
        const SizedBox(height: 6),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最近导入记录',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '用于确认扫描任务是否实际入库，以及最近处理了哪本书。',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
              ),
              const SizedBox(height: 16),
              if (controller.importJobs.isEmpty)
                const _EmptyBlock(
                  title: '暂无导入记录',
                  body: '第一次扫描完成后，这里会显示最近的入库结果。',
                )
              else
                ...controller.importJobs
                    .take(8)
                    .map(
                      (job) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ImportJobTile(job: job),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showSourceDialog(
    BuildContext context,
    WidgetRef ref, {
    AdminLibrarySourceView? source,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _LibrarySourceDialog(source: source),
    );
  }
}

class _LibrarySourceCard extends ConsumerWidget {
  const _LibrarySourceCard({
    required this.source,
    required this.controller,
    required this.onEdit,
  });

  final AdminLibrarySourceView source;
  final AdminCenterController controller;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    final endpoint = source.isWebDav
        ? '${source.baseUrl ?? ''}${source.remotePath ?? ''}'
        : (source.rootPath ?? '');

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      source.isWebDav ? 'WebDAV 托管扫描' : '客户端手动上传目录',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (source.isWebDav)
                Switch(
                  value: source.enabled,
                  onChanged: controller.isWorking
                      ? null
                      : (value) => ref
                            .read(adminCenterControllerProvider)
                            .toggleLibrarySourceEnabled(source, value),
                )
              else
                _StatusPill(label: '仅手动扫描', highlighted: true),
            ],
          ),
          const SizedBox(height: 14),
          _InfoLine(
            label: source.isWebDav ? '地址' : '目录',
            value: endpoint.isEmpty ? '-' : endpoint,
          ),
          if (source.isWebDav)
            _InfoLine(
              label: '账号',
              value: source.username?.trim().isNotEmpty == true
                  ? source.username!
                  : '匿名访问',
            ),
          _InfoLine(
            label: '方式',
            value: source.isWebDav
                ? '每 ${source.scanIntervalMinutes} 分钟自动扫描'
                : '每次由当前设备重新选择目录并手动扫描',
          ),
          _InfoLine(
            label: '上次扫描',
            value: source.lastScanAt == null
                ? '尚未扫描'
                : _formatDateTime(source.lastScanAt!),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: controller.isWorking ? null : onEdit,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('编辑'),
              ),
              FilledButton.tonalIcon(
                onPressed: controller.isWorking
                    ? null
                    : () => source.isWebDav
                          ? ref
                                .read(adminCenterControllerProvider)
                                .rescanLibrarySource(source)
                          : _pickAndScanClientFolder(context, ref),
                icon: Icon(
                  source.isWebDav
                      ? Icons.sync_rounded
                      : Icons.drive_folder_upload_outlined,
                ),
                label: Text(source.isWebDav ? '立即扫描' : '选择目录并扫描'),
              ),
              TextButton.icon(
                onPressed: controller.isWorking
                    ? null
                    : () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('删除任务'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndScanClientFolder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final picker = LocalLibraryFolderPicker();
    try {
      final folder = await picker.pickFolder();
      if (folder == null || !context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => GlassAlertDialog(
          title: const Text('确认手动扫描'),
          content: Text(
            '已选择“${folder.displayName}”，发现 ${folder.files.length} 个支持的图书文件。'
            '服务端会先比较摘要，只上传新增或发生变化的文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('开始扫描'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await ref
          .read(adminCenterControllerProvider)
          .scanClientLibrarySource(source, folder, picker);
    } on LocalFolderPickerException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: const Text('删除同步任务？'),
        content: Text('将删除“${source.name}”的扫描配置和文件摘要。已经导入的图书会继续保留，不会从书库删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除任务'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(adminCenterControllerProvider).deleteLibrarySource(source);
    }
  }
}

class _ImportJobTile extends StatelessWidget {
  const _ImportJobTile({required this.job});

  final AdminImportJobView job;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final title = job.bookTitle?.trim().isNotEmpty == true
        ? job.bookTitle!
        : '未关联书籍';
    final sourceName = job.sourceName?.trim().isNotEmpty == true
        ? job.sourceName!
        : '未知扫描源';

    return GlassCard(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StatusPill(
                label: job.status,
                highlighted: job.status == 'COMPLETED',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$sourceName · ${_formatDateTime(job.updatedAt)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
          ),
          if ((job.message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              job.message!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibrarySourceDialog extends ConsumerStatefulWidget {
  const _LibrarySourceDialog({this.source});

  final AdminLibrarySourceView? source;

  @override
  ConsumerState<_LibrarySourceDialog> createState() =>
      _LibrarySourceDialogState();
}

class _LibrarySourceDialogState extends ConsumerState<_LibrarySourceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _rootPathController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _remotePathController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _intervalController;
  late String _sourceType;
  late bool _enabled;
  PickedLocalLibraryFolder? _selectedFolder;
  final LocalLibraryFolderPicker _folderPicker = LocalLibraryFolderPicker();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _nameController = TextEditingController(text: source?.name ?? '');
    _rootPathController = TextEditingController(text: source?.rootPath ?? '');
    _baseUrlController = TextEditingController(text: source?.baseUrl ?? '');
    _remotePathController = TextEditingController(
      text: source?.remotePath ?? '/',
    );
    _usernameController = TextEditingController(text: source?.username ?? '');
    _passwordController = TextEditingController(text: source?.password ?? '');
    _intervalController = TextEditingController(
      text: (source?.scanIntervalMinutes ?? 60).toString(),
    );
    _sourceType = source == null || source.isWebDav
        ? (source?.sourceType ?? 'CLIENT_FOLDER')
        : 'CLIENT_FOLDER';
    _enabled = source?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rootPathController.dispose();
    _baseUrlController.dispose();
    _remotePathController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWebDav = _sourceType == 'WEBDAV';

    return GlassAlertDialog(
      scrollable: true,
      title: Text(widget.source == null ? '新增扫描源' : '编辑扫描源'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: context.tr('名称')),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? context.tr('请输入名称')
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sourceType,
              borderRadius: BorderRadius.circular(16),
              decoration: InputDecoration(
                labelText: context.tr('资源类型'),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'CLIENT_FOLDER', child: Text('本地上传目录')),
                DropdownMenuItem(value: 'WEBDAV', child: Text('WebDAV')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _sourceType = value;
                  if (value == 'CLIENT_FOLDER') {
                    _enabled = false;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            if (isWebDav) ...[
              TextFormField(
                controller: _baseUrlController,
                decoration: InputDecoration(labelText: context.tr('WebDAV 地址')),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? context.tr('请输入 WebDAV 地址')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remotePathController,
                decoration: InputDecoration(labelText: context.tr('远程目录')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: context.tr('账号')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: context.tr('密码')),
                obscureText: true,
              ),
            ] else ...[
              _FolderSelectionField(
                displayPath: _rootPathController.text.trim(),
                fileCount: _selectedFolder?.files.length,
                onPressed: _pickFolder,
              ),
              const SizedBox(height: 10),
              const _InlineHint(
                icon: Icons.touch_app_outlined,
                text: '不会自动扫描。以后每次刷新都需要由当前设备重新选择目录，兼容浏览器、桌面和移动端权限。',
              ),
            ],
            if (isWebDav) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _intervalController,
                decoration: InputDecoration(labelText: context.tr('扫描周期（分钟）')),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final minutes = int.tryParse(value ?? '');
                  if (minutes == null || minutes <= 0) {
                    return context.tr('请输入大于 0 的分钟数');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _enabled,
                contentPadding: EdgeInsets.zero,
                title: const Text('启用定时扫描'),
                subtitle: const Text('仅 WebDAV 会由服务端按周期自动访问'),
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? '保存中...' : '保存'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    final controller = ref.read(adminCenterControllerProvider);
    final isWebDav = _sourceType == 'WEBDAV';
    if (!isWebDav && _rootPathController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请通过“选择目录”按钮指定上传目录')));
      return;
    }
    final minutes = isWebDav ? int.parse(_intervalController.text.trim()) : 60;

    if (widget.source == null) {
      await controller.createLibrarySource(
        name: _nameController.text.trim(),
        sourceType: _sourceType,
        rootPath: isWebDav ? null : _rootPathController.text.trim(),
        baseUrl: isWebDav ? _baseUrlController.text.trim() : null,
        remotePath: isWebDav ? _remotePathController.text.trim() : null,
        username: isWebDav ? _usernameController.text.trim() : null,
        password: isWebDav ? _passwordController.text : null,
        enabled: isWebDav && _enabled,
        scanIntervalMinutes: minutes,
      );
    } else {
      await controller.updateLibrarySource(
        sourceId: widget.source!.id,
        name: _nameController.text.trim(),
        sourceType: _sourceType,
        rootPath: isWebDav ? null : _rootPathController.text.trim(),
        baseUrl: isWebDav ? _baseUrlController.text.trim() : null,
        remotePath: isWebDav ? _remotePathController.text.trim() : null,
        username: isWebDav ? _usernameController.text.trim() : null,
        password: isWebDav ? _passwordController.text : null,
        enabled: isWebDav && _enabled,
        scanIntervalMinutes: minutes,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickFolder() async {
    try {
      final folder = await _folderPicker.pickFolder();
      if (folder == null || !mounted) return;
      setState(() {
        _selectedFolder = folder;
        _rootPathController.text = folder.displayPath;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = folder.displayName;
        }
      });
    } on LocalFolderPickerException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassCard(child: child);
  }
}

class _FolderSelectionField extends StatelessWidget {
  const _FolderSelectionField({
    required this.displayPath,
    required this.fileCount,
    required this.onPressed,
  });

  final String displayPath;
  final int? fileCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final hasSelection = displayPath.isNotEmpty;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: palette.backgroundSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                Icons.folder_open_outlined,
                color: hasSelection ? palette.accent : palette.inkSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSelection ? displayPath : '尚未选择目录',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fileCount == null
                          ? '点击调用系统目录选择器，不能手动输入路径'
                          : '已识别 $fileCount 个支持的图书文件',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: palette.inkSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
          ),
        ),
      ],
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: palette.inkSecondary),
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

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.highlighted});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted
            ? palette.accent.withValues(alpha: 0.14)
            : palette.backgroundSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: highlighted ? palette.accent : palette.inkSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _formatDateTime(String value) {
  final normalized = value.replaceFirst('T', ' ');
  return normalized.length > 16 ? normalized.substring(0, 16) : normalized;
}
