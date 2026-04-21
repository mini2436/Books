import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/models/admin_models.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import '../auth/auth_controller.dart';
import 'admin_center_controller.dart';

class AdminCenterScreen extends ConsumerWidget {
  const AdminCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final controller = ref.watch(adminCenterControllerProvider);
    final palette = AppReaderPalette.of(context);
    final tablet = Responsive.isTablet(context);
    final showEmptyLoading =
        controller.isLoading &&
        controller.books.isEmpty &&
        controller.annotations.isEmpty &&
        controller.bookmarks.isEmpty &&
        controller.users.isEmpty;

    if (!(auth.user?.canAccessAdmin ?? false)) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '当前账号没有后台权限。',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: palette.inkSecondary),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(adminCenterControllerProvider).refresh(),
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
                                  '后台管理',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '面向管理员的用户、角色、图书与阅读数据维护入口',
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
                                      .read(adminCenterControllerProvider)
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
                            label: '书籍',
                            value: '${controller.bookCount}',
                          ),
                          _SummaryChip(
                            label: '批注',
                            value: '${controller.annotationCount}',
                          ),
                          _SummaryChip(
                            label: '书签',
                            value: '${controller.bookmarkCount}',
                          ),
                          if (controller.canManageUsers)
                            _SummaryChip(
                              label: '启用用户',
                              value: '${controller.activeUserCount}',
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: controller.availableSections
                              .map(
                                (section) => Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: ChoiceChip(
                                    label: Text(_sectionLabel(section)),
                                    selected:
                                        controller.selectedSection == section,
                                    onSelected: (_) => ref
                                        .read(adminCenterControllerProvider)
                                        .setSection(section),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      if (controller.notice != null) ...[
                        const SizedBox(height: 16),
                        _BannerMessage(
                          icon: Icons.check_circle_outline,
                          message: controller.notice!,
                          foregroundColor: palette.accent,
                          backgroundColor: palette.accent.withValues(alpha: 0.12),
                          onClose: ref
                              .read(adminCenterControllerProvider)
                              .clearBanner,
                        ),
                      ],
                      if (controller.error != null) ...[
                        const SizedBox(height: 12),
                        _BannerMessage(
                          icon: Icons.error_outline,
                          message: controller.error!,
                          foregroundColor: Theme.of(context).colorScheme.error,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.75),
                          onClose: ref
                              .read(adminCenterControllerProvider)
                              .clearBanner,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (showEmptyLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    tablet ? 24 : 16,
                    8,
                    tablet ? 24 : 16,
                    24,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _SectionBody(
                      section: controller.selectedSection,
                      controller: controller,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton:
          controller.selectedSection == AdminSection.users &&
              controller.canManageUsers
          ? FloatingActionButton.extended(
              onPressed: controller.isWorking
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (context) => CreateUserDialog(
                        onSubmit: (username, password, role) => ref
                            .read(adminCenterControllerProvider)
                            .createUser(
                              username: username,
                              password: password,
                              role: role,
                            ),
                      ),
                    ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('新建用户'),
            )
          : null,
    );
  }
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({
    required this.section,
    required this.controller,
  });

  final AdminSection section;
  final AdminCenterController controller;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case AdminSection.users:
        return _UserManagementSection(controller: controller);
      case AdminSection.roles:
        return _RoleManagementSection(controller: controller);
      case AdminSection.books:
        return _BookManagementSection(controller: controller);
      case AdminSection.annotations:
        return _AnnotationManagementSection(controller: controller);
      case AdminSection.bookmarks:
        return _BookmarkManagementSection(controller: controller);
    }
  }
}

class _UserManagementSection extends ConsumerWidget {
  const _UserManagementSection({required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);

    if (!controller.canManageUsers) {
      return _EmptyPanel(
        title: '仅超级管理员可管理用户',
        body: '当前角色可以继续管理图书、批注与书签，但不能新增或停用用户。',
      );
    }

    return Column(
      children: [
        _PanelCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '用户管理',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '管理后台账号、启用状态与当前角色。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '共 ${controller.users.length} 人',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (controller.users.isEmpty)
          const _EmptyPanel(
            title: '暂无用户数据',
            body: '刷新后台后，这里会显示可管理的账号列表。',
          )
        else
          ...controller.users.map(
            (user) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          child: Text(
                            user.username.substring(0, user.username.length >= 2 ? 2 : 1).toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.username,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID ${user.id} · ${adminRoleLabel(user.role)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: palette.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: user.enabled,
                          onChanged: controller.isWorking
                              ? null
                              : (value) => ref
                                    .read(adminCenterControllerProvider)
                                    .updateUserEnabled(user, value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoleManagementSection extends ConsumerWidget {
  const _RoleManagementSection({required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);

    if (!controller.canManageUsers) {
      return const _EmptyPanel(
        title: '仅超级管理员可调整角色',
        body: '角色编排会影响后台权限范围，因此当前账号无法修改。',
      );
    }

    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: controller.roleSummaries
              .map(
                (role) => SizedBox(
                  width: Responsive.isTablet(context) ? 220 : double.infinity,
                  child: _PanelCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          role.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: palette.inkSecondary,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${role.userCount} 人',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        ...controller.users.map(
          (user) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _PanelCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.username,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          user.enabled ? '当前启用' : '当前停用',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: palette.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DropdownButton<String>(
                    value: user.role,
                    items: adminRoles
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(adminRoleLabel(role)),
                          ),
                        )
                        .toList(),
                    onChanged: controller.isWorking
                        ? null
                        : (role) {
                            if (role == null) {
                              return;
                            }
                            ref
                                .read(adminCenterControllerProvider)
                                .updateUserRole(user, role);
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookManagementSection extends StatelessWidget {
  const _BookManagementSection({required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Column(
      children: [
        _PanelCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '导入图书',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '从本机选择图书文件并上传到后台，成功后会自动出现在下方书籍列表中。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '支持格式：TXT / EPUB / PDF',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.inkTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _UploadBookButton(controller: controller),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (controller.books.isEmpty)
          const _EmptyPanel(
            title: '还没有可管理的书籍',
            body: '先导入一本图书，这里会显示格式、来源与当前状态。',
          )
        else
          ...controller.books.map(
            (book) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if ((book.author ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        book.author!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.inkSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MetaPill(label: '格式', value: book.format),
                        _MetaPill(label: '插件', value: book.pluginId),
                        _MetaPill(label: '来源', value: book.sourceType),
                        _MetaPill(
                          label: '状态',
                          value: book.sourceMissing ? '源文件缺失' : '正常',
                        ),
                      ],
                    ),
                    if ((book.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        book.description!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '更新于 ${_formatDate(book.updatedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.inkTertiary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) => BookAccessSheet(book: book),
                          ),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('可见人员'),
                        ),
                        if (controller.canAssignBooks)
                          FilledButton.tonalIcon(
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (context) => BookAccessSheet(book: book),
                            ),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('分配读者'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _UploadBookButton extends ConsumerWidget {
  const _UploadBookButton({required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: controller.isWorking
          ? null
          : () => _pickAndUpload(context, ref),
      icon: const Icon(Icons.upload_file_outlined),
      label: Text(controller.isWorking ? '上传中...' : '导入图书'),
    );
  }

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub', 'pdf'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final filePath = result.files.single.path;
    if (filePath == null || filePath.trim().isEmpty) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    await ref.read(adminCenterControllerProvider).uploadBook(filePath);
  }
}

class BookAccessSheet extends ConsumerStatefulWidget {
  const BookAccessSheet({super.key, required this.book});

  final AdminBookSummary book;

  @override
  ConsumerState<BookAccessSheet> createState() => _BookAccessSheetState();
}

class _BookAccessSheetState extends ConsumerState<BookAccessSheet> {
  int? _selectedUserId;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(adminCenterControllerProvider)
          .loadBookViewers(widget.book.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(adminCenterControllerProvider);
    final palette = AppReaderPalette.of(context);
    final viewers = controller.viewersForBook(widget.book.id);
    final loading = controller.isLoadingViewers(widget.book.id);
    final availableUsers = controller.grantableUsers
        .where(
          (user) => viewers.every((viewer) => viewer.userId != user.id),
        )
        .toList();

    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight =
        (mediaQuery.size.height - mediaQuery.padding.top) * 0.88;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 18,
            bottom: mediaQuery.viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.book.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '查看当前可见人员，并将这本书分配给更多用户。',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (controller.canAssignBooks) ...[
                        _PanelCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '分配给指定人员',
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '选择一位当前还看不到这本书的用户，立即添加到可见范围。',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: palette.inkSecondary,
                                ),
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<int>(
                                initialValue: _selectedUserId,
                                decoration: const InputDecoration(
                                  labelText: '选择用户',
                                ),
                                items: availableUsers
                                    .map(
                                      (user) => DropdownMenuItem<int>(
                                        value: user.id,
                                        child: Text(
                                          '${user.username} · ${adminRoleLabel(user.role)}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: controller.isWorking
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _selectedUserId = value;
                                        });
                                      },
                              ),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed:
                                      controller.isWorking ||
                                          _selectedUserId == null
                                      ? null
                                      : () async {
                                          await ref
                                              .read(adminCenterControllerProvider)
                                              .grantBookToUser(
                                                widget.book.id,
                                                _selectedUserId!,
                                              );
                                          if (!mounted) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedUserId = null;
                                          });
                                        },
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: Text(
                                    controller.isWorking ? '分配中...' : '确认分配',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        '当前可见人员',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (loading && viewers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (viewers.isEmpty)
                        const _EmptyPanel(
                          title: '暂无可见人员信息',
                          body: '刷新后如果仍为空，说明当前书籍还没有有效访问者。',
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: viewers.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final viewer = viewers[index];
                            return _PanelCard(
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    child: Text(
                                      viewer.username.substring(
                                        0,
                                        viewer.username.length >= 2 ? 2 : 1,
                                      ).toUpperCase(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          viewer.username,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          adminRoleLabel(viewer.role),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: palette.inkSecondary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _StatusChip(
                                    label: viewer.isGlobalAccess ? '角色可见' : '已分配',
                                    highlighted: viewer.isGlobalAccess,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
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

class _AnnotationManagementSection extends ConsumerWidget {
  const _AnnotationManagementSection({required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    if (controller.annotations.isEmpty) {
      return const _EmptyPanel(
        title: '还没有批注记录',
        body: '用户产生高亮与批注后，这里会出现全局列表。',
      );
    }

    return Column(
      children: controller.annotations
          .map(
            (annotation) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PanelCard(
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
                                annotation.bookTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${annotation.username} · ${_formatDate(annotation.updatedAt)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: palette.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        _StatusChip(
                          label: annotation.deleted ? '已隐藏' : '显示中',
                          highlighted: !annotation.deleted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      annotation.quoteText?.trim().isNotEmpty == true
                          ? annotation.quoteText!
                          : '无摘录文本',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((annotation.noteText ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(annotation.noteText!),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '定位：${annotation.anchor}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: palette.inkTertiary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: controller.isWorking
                              ? null
                              : () => ref
                                    .read(adminCenterControllerProvider)
                                    .updateAnnotationDeleted(
                                      annotation,
                                      !annotation.deleted,
                                    ),
                          icon: Icon(
                            annotation.deleted
                                ? Icons.restore_from_trash_outlined
                                : Icons.delete_outline,
                          ),
                          label: Text(annotation.deleted ? '恢复' : '隐藏'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _BookmarkManagementSection extends ConsumerWidget {
  const _BookmarkManagementSection({required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    if (controller.bookmarks.isEmpty) {
      return const _EmptyPanel(
        title: '还没有书签记录',
        body: '用户创建书签后，这里会显示全局列表与当前状态。',
      );
    }

    return Column(
      children: controller.bookmarks
          .map(
            (bookmark) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _PanelCard(
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
                                bookmark.bookTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${bookmark.username} · ${_formatDate(bookmark.updatedAt)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: palette.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        _StatusChip(
                          label: bookmark.deleted ? '已隐藏' : '显示中',
                          highlighted: !bookmark.deleted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      bookmark.label?.trim().isNotEmpty == true
                          ? bookmark.label!
                          : '未命名书签',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bookmark.location,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: controller.isWorking
                            ? null
                            : () => ref
                                  .read(adminCenterControllerProvider)
                                  .updateBookmarkDeleted(
                                    bookmark,
                                    !bookmark.deleted,
                                  ),
                        icon: Icon(
                          bookmark.deleted
                              ? Icons.restore_from_trash_outlined
                              : Icons.delete_outline,
                        ),
                        label: Text(bookmark.deleted ? '恢复' : '隐藏'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class CreateUserDialog extends StatefulWidget {
  const CreateUserDialog({super.key, required this.onSubmit});

  final Future<void> Function(String username, String password, String role)
  onSubmit;

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = adminRoles.first;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建后台用户'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: '用户名'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '请输入用户名' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: '初始密码'),
              obscureText: true,
              validator: (value) => (value == null || value.trim().length < 6)
                  ? '密码至少 6 位'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              items: adminRoles
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(adminRoleLabel(role)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _role = value;
                  });
                }
              },
              decoration: const InputDecoration(labelText: '角色'),
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
          child: Text(_submitting ? '创建中...' : '创建'),
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
    await widget.onSubmit(
      _usernameController.text.trim(),
      _passwordController.text,
      _role,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
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

class _BannerMessage extends StatelessWidget {
  const _BannerMessage({
    required this.icon,
    required this.message,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.onClose,
  });

  final IconData icon;
  final String message;
  final Color foregroundColor;
  final Color backgroundColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foregroundColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: foregroundColor,
                  height: 1.45,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: Icon(Icons.close, color: foregroundColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return _PanelCard(
      child: Column(
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
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.value});

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.highlighted});

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: highlighted ? palette.accent : palette.inkSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _sectionLabel(AdminSection section) {
  switch (section) {
    case AdminSection.users:
      return '用户管理';
    case AdminSection.roles:
      return '角色管理';
    case AdminSection.books:
      return '书籍管理';
    case AdminSection.annotations:
      return '批注管理';
    case AdminSection.bookmarks:
      return '书签管理';
  }
}

String _formatDate(String value) {
  return value.split('T').first;
}
