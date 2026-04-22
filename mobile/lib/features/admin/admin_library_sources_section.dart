import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/admin_models.dart';
import '../../shared/theme/reader_theme_extension.dart';
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
                          '配置 WebDAV 或本地目录扫描源，按周期自动扫描并导入新书。',
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
              body: '先添加一个 WebDAV 书库或本地目录，后台就能定时扫描并自动入库。',
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
                      source.isWebDav ? 'WebDAV 扫描源' : '本地目录扫描源',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: source.enabled,
                onChanged: controller.isWorking
                    ? null
                    : (value) => ref
                          .read(adminCenterControllerProvider)
                          .toggleLibrarySourceEnabled(source, value),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoLine(label: '地址', value: endpoint.isEmpty ? '-' : endpoint),
          _InfoLine(
            label: '账号',
            value: source.username?.trim().isNotEmpty == true
                ? source.username!
                : '匿名访问',
          ),
          _InfoLine(
            label: '周期',
            value: '每 ${source.scanIntervalMinutes} 分钟扫描一次',
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
                    : () => ref
                          .read(adminCenterControllerProvider)
                          .rescanLibrarySource(source),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('立即扫描'),
              ),
            ],
          ),
        ],
      ),
    );
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.backgroundSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
    _sourceType = source?.sourceType ?? 'WEBDAV';
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

    return AlertDialog(
      scrollable: true,
      title: Text(widget.source == null ? '新增扫描源' : '编辑扫描源'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '名称'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '请输入名称' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sourceType,
              decoration: const InputDecoration(labelText: '资源类型'),
              items: const [
                DropdownMenuItem(value: 'WEBDAV', child: Text('WebDAV')),
                DropdownMenuItem(value: 'WATCHED_FOLDER', child: Text('本地目录')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _sourceType = value;
                });
              },
            ),
            const SizedBox(height: 12),
            if (isWebDav) ...[
              TextFormField(
                controller: _baseUrlController,
                decoration: const InputDecoration(labelText: 'WebDAV 地址'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? '请输入 WebDAV 地址'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remotePathController,
                decoration: const InputDecoration(labelText: '远程目录'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: '账号'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
            ] else
              TextFormField(
                controller: _rootPathController,
                decoration: const InputDecoration(labelText: '本地目录'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入本地目录' : null,
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _intervalController,
              decoration: const InputDecoration(labelText: '扫描周期（分钟）'),
              keyboardType: TextInputType.number,
              validator: (value) {
                final minutes = int.tryParse(value ?? '');
                if (minutes == null || minutes <= 0) {
                  return '请输入大于 0 的分钟数';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: _enabled,
              contentPadding: EdgeInsets.zero,
              title: const Text('启用定时扫描'),
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
            ),
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
    final minutes = int.parse(_intervalController.text.trim());
    final isWebDav = _sourceType == 'WEBDAV';

    if (widget.source == null) {
      await controller.createLibrarySource(
        name: _nameController.text.trim(),
        sourceType: _sourceType,
        rootPath: isWebDav ? null : _rootPathController.text.trim(),
        baseUrl: isWebDav ? _baseUrlController.text.trim() : null,
        remotePath: isWebDav ? _remotePathController.text.trim() : null,
        username: isWebDav ? _usernameController.text.trim() : null,
        password: isWebDav ? _passwordController.text : null,
        enabled: _enabled,
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
        enabled: _enabled,
        scanIntervalMinutes: minutes,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

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
      child: Padding(padding: const EdgeInsets.all(16), child: child),
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
