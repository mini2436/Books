import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/admin_models.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import '../auth/auth_controller.dart';
import 'admin_center_controller.dart';

class AdminBookDetailScreen extends ConsumerStatefulWidget {
  const AdminBookDetailScreen({super.key, required this.bookId});

  final int bookId;

  @override
  ConsumerState<AdminBookDetailScreen> createState() =>
      _AdminBookDetailScreenState();
}

class _AdminBookDetailScreenState extends ConsumerState<AdminBookDetailScreen> {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _groupController = TextEditingController();
  bool _seededMetadata = false;
  bool _seededGroup = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final controller = ref.read(adminCenterControllerProvider);
      await controller.loadBookDetail(widget.bookId, force: true);
      await controller.loadBookViewers(widget.bookId, force: true);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(adminCenterControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final detail = controller.bookDetailFor(widget.bookId);
    AdminBookSummary? summary;
    for (final book in controller.books) {
      if (book.id == widget.bookId) {
        summary = book;
        break;
      }
    }
    final title = detail?.title ?? summary?.title ?? '图书详情';
    final author = detail?.author ?? summary?.author;
    final viewers = controller.viewersForBook(widget.bookId);
    final availableUsers = controller.grantableUsers
        .where((user) => viewers.every((viewer) => viewer.userId != user.id))
        .toList();
    final isTablet = Responsive.isTablet(context);
    final loading =
        controller.isLoadingBookDetail(widget.bookId) && detail == null;

    if (!_seededGroup && detail != null) {
      _groupController.text = detail.groupName ?? '';
      _seededGroup = true;
    }
    if (!_seededMetadata && detail != null) {
      _titleController.text = detail.title;
      _authorController.text = detail.author ?? '';
      _seededMetadata = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await controller.loadBookDetail(widget.bookId, force: true);
              await controller.loadBookViewers(widget.bookId, force: true);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  await controller.loadBookDetail(widget.bookId, force: true);
                  await controller.loadBookViewers(widget.bookId, force: true);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    isTablet ? 24 : 16,
                    16,
                    isTablet ? 24 : 16,
                    24,
                  ),
                  child: isTablet
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 280,
                              child: _BookProfileCard(
                                bookId: widget.bookId,
                                title: title,
                                author: author,
                                accessToken: auth.accessToken,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: _BookDetailOperations(
                                detail: detail,
                                summary: summary,
                                titleController: _titleController,
                                authorController: _authorController,
                                groupController: _groupController,
                                availableUsers: availableUsers,
                                viewers: viewers,
                                controller: controller,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _BookProfileCard(
                              bookId: widget.bookId,
                              title: title,
                              author: author,
                              accessToken: auth.accessToken,
                            ),
                            const SizedBox(height: 14),
                            _BookDetailOperations(
                              detail: detail,
                              summary: summary,
                              titleController: _titleController,
                              authorController: _authorController,
                              groupController: _groupController,
                              availableUsers: availableUsers,
                              viewers: viewers,
                              controller: controller,
                            ),
                          ],
                        ),
                ),
              ),
      ),
    );
  }
}

class _BookProfileCard extends ConsumerWidget {
  const _BookProfileCard({
    required this.bookId,
    required this.title,
    required this.author,
    required this.accessToken,
  });

  final int bookId;
  final String title;
  final String? author;
  final String? accessToken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    final imageUrl = accessToken == null
        ? null
        : ref.read(apiClientProvider).buildUrl('/api/me/books/$bookId/cover');
    final headers = accessToken == null
        ? null
        : ref.read(apiClientProvider).coverHeaders(accessToken!);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.72,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5D3A22), Color(0xFF93633A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: imageUrl == null
                    ? _DetailCoverFallback(title: title)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          imageUrl,
                          headers: headers,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _DetailCoverFallback(title: title),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if ((author ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                author!,
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

class _BookDetailOperations extends StatelessWidget {
  const _BookDetailOperations({
    required this.detail,
    required this.summary,
    required this.titleController,
    required this.authorController,
    required this.groupController,
    required this.availableUsers,
    required this.viewers,
    required this.controller,
  });

  final AdminBookDetail? detail;
  final AdminBookSummary? summary;
  final TextEditingController titleController;
  final TextEditingController authorController;
  final TextEditingController groupController;
  final List<AdminUserView> availableUsers;
  final List<BookViewerView> viewers;
  final AdminCenterController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '书籍信息',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: titleController,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: '书名',
                  hintText: '请输入书名',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: authorController,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: '作者（可选）',
                  hintText: '留空可清除作者',
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: controller.isWorking
                      ? null
                      : () async {
                          await controller.updateBookMetadata(
                            detail?.id ?? summary!.id,
                            titleController.text,
                            authorController.text,
                          );
                          if (!context.mounted) {
                            return;
                          }
                          final message = controller.error ?? controller.notice;
                          if (message != null) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(message)));
                          }
                        },
                  child: Text(controller.isWorking ? '保存中...' : '保存书籍信息'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _DetailPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '图书分组',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 520;
                  return Flex(
                    direction: compact ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: compact
                        ? CrossAxisAlignment.stretch
                        : CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: compact ? 0 : 1,
                        child: TextField(
                          controller: groupController,
                          decoration: const InputDecoration(
                            labelText: '分组名称',
                            hintText: '例如：经典文学 / 待整理 / 管理样书',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: compact ? 0 : 12,
                        height: compact ? 12 : 0,
                      ),
                      FilledButton(
                        onPressed: controller.isWorking
                            ? null
                            : () async {
                                await controller.updateBookGroup(
                                  detail?.id ?? summary!.id,
                                  groupController.text,
                                );
                              },
                        child: Text(controller.isWorking ? '保存中...' : '保存'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _DetailPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '相关信息',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoPill(
                    label: '格式',
                    value: detail?.format ?? summary?.format ?? '-',
                  ),
                  _InfoPill(
                    label: '插件',
                    value: detail?.pluginId ?? summary?.pluginId ?? '-',
                  ),
                  _InfoPill(
                    label: '来源',
                    value: detail?.sourceType ?? summary?.sourceType ?? '-',
                  ),
                  _InfoPill(
                    label: '状态',
                    value:
                        (detail?.sourceMissing ??
                            summary?.sourceMissing ??
                            false)
                        ? '源文件缺失'
                        : '正常',
                  ),
                  _InfoPill(
                    label: '结构化正文',
                    value: detail?.hasStructuredContent == true ? '可用' : '未生成',
                  ),
                  _InfoPill(
                    label: '更新时间',
                    value: _formatDate(
                      detail?.updatedAt ?? summary?.updatedAt ?? '',
                    ),
                  ),
                ],
              ),
              if ((detail?.description ?? summary?.description ?? '')
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  detail?.description ?? summary!.description!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.inkSecondary,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _DetailPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '绑定解绑用户',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Text(
                '可绑定用户',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (availableUsers.isEmpty)
                Text(
                  '没有尚未绑定的启用用户。',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
                )
              else
                ...availableUsers.map(
                  (user) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(_initials(user.username)),
                    ),
                    title: Text(user.username),
                    subtitle: Text(adminRoleLabel(user.role)),
                    trailing: FilledButton.tonalIcon(
                      onPressed: controller.isWorking
                          ? null
                          : () async {
                              await controller.grantBookToUser(
                                detail?.id ?? summary!.id,
                                user.id,
                              );
                              if (context.mounted) {
                                _showOperationMessage(context, controller);
                              }
                            },
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('绑定'),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                '当前可见用户',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (controller.isLoadingViewers(detail?.id ?? summary?.id ?? 0) &&
                  viewers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (viewers.isEmpty)
                Text(
                  '当前还没有可见人员。',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
                )
              else
                ...viewers.map(
                  (viewer) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.backgroundSoft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              child: Text(_initials(viewer.username)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    viewer.username,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    adminRoleLabel(viewer.role),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: palette.inkSecondary),
                                  ),
                                ],
                              ),
                            ),
                            if (viewer.isGlobalAccess)
                              _InfoPill(label: '权限', value: '角色可见')
                            else
                              TextButton.icon(
                                onPressed: controller.isWorking
                                    ? null
                                    : () async {
                                        await controller.revokeBookFromUser(
                                          detail?.id ?? summary!.id,
                                          viewer,
                                        );
                                        if (context.mounted) {
                                          _showOperationMessage(
                                            context,
                                            controller,
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.link_off),
                                label: const Text('解绑'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _initials(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '?';
  }
  return normalized.substring(0, normalized.length >= 2 ? 2 : 1).toUpperCase();
}

void _showOperationMessage(
  BuildContext context,
  AdminCenterController controller,
) {
  final message = controller.error ?? controller.notice;
  if (message == null || message.isEmpty) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.line),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

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
        child: Text(
          '$label · $value',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
        ),
      ),
    );
  }
}

class _DetailCoverFallback extends StatelessWidget {
  const _DetailCoverFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            title,
            maxLines: 5,
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

String _formatDate(String value) {
  return value.split('T').first;
}
