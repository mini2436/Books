import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/admin_models.dart';
import '../../data/models/user_role.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/utils/responsive.dart';
import '../../shared/widgets/centered_scale_dialog.dart';
import '../../shared/widgets/change_password_dialog.dart';
import '../../shared/widgets/glass_action_button.dart';
import '../../shared/widgets/glass_segmented_control.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_dialog.dart';
import '../auth/auth_controller.dart';
import 'admin_library_sources_section.dart';
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
        controller.librarySources.isEmpty &&
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
                            label: '扫描源',
                            value: '${controller.librarySourceCount}',
                          ),
                          if (controller.canManageUsers)
                            _SummaryChip(
                              label: '启用用户',
                              value: '${controller.activeUserCount}',
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: GlassSegmentedControl<AdminSection>(
                            style: tablet
                                ? null
                                : const ButtonStyle(
                                    minimumSize: WidgetStatePropertyAll(
                                      Size(0, 52),
                                    ),
                                    padding: WidgetStatePropertyAll(
                                      EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                    ),
                                    visualDensity: VisualDensity.standard,
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                  ),
                            showSelectedIcon: false,
                            segments: controller.availableSections
                                .map(
                                  (section) => ButtonSegment<AdminSection>(
                                    value: section,
                                    icon: Icon(_sectionIcon(section), size: 17),
                                    label: Text(_sectionLabel(section)),
                                  ),
                                )
                                .toList(),
                            selected: {controller.selectedSection},
                            onSelectionChanged: (selection) => ref
                                .read(adminCenterControllerProvider)
                                .setSection(selection.first),
                          ),
                        ),
                      ),
                      if (controller.notice != null) ...[
                        const SizedBox(height: 16),
                        _BannerMessage(
                          icon: Icons.check_circle_outline,
                          message: controller.notice!,
                          foregroundColor: palette.accent,
                          backgroundColor: palette.accent.withValues(
                            alpha: 0.12,
                          ),
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
                    24 + Responsive.shellBottomClearance(context),
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _ContentSwapTransition(
                      transitionKey: controller.selectedSection,
                      child: _SectionBody(
                        section: controller.selectedSection,
                        controller: controller,
                      ),
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

class _ContentSwapTransition extends StatelessWidget {
  const _ContentSwapTransition({
    required this.transitionKey,
    required this.child,
  });

  final Object transitionKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return TweenAnimationBuilder<double>(
      key: ValueKey(transitionKey),
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: 0.35 + value * 0.65,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({required this.section, required this.controller});

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
      case AdminSection.librarySources:
        return AdminLibrarySourcesSection(controller: controller);
    }
  }
}

class _UserManagementSection extends ConsumerWidget {
  const _UserManagementSection({required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    final compactActions = MediaQuery.sizeOf(context).width < 620;

    Future<void> promptPasswordReset(AdminUserView user) async {
      final values = await showCenteredScaleDialog<PasswordChangeValues>(
        context,
        builder: (context) => ChangePasswordDialog(
          title: '修改 ${user.username} 的密码',
          description: '设置新的登录密码。超级管理员账号不能在这里修改。',
        ),
      );
      if (values == null) {
        return;
      }
      await ref
          .read(adminCenterControllerProvider)
          .resetUserPassword(user, values.newPassword);
    }

    Future<void> promptCreateUser() => showCenteredScaleDialog<void>(
      context,
      builder: (context) => CreateUserDialog(
        onSubmit: (username, password, role) => ref
            .read(adminCenterControllerProvider)
            .createUser(username: username, password: password, role: role),
      ),
    );

    if (!controller.canManageUsers) {
      return _EmptyPanel(
        title: '仅超级管理员可管理用户',
        body: '当前角色可以继续管理图书、批注与扫描任务，但不能新增或停用用户。',
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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.inkSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (controller.users.isEmpty)
          const _EmptyPanel(title: '暂无用户数据', body: '刷新后台后，这里会显示可管理的账号列表。')
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
                            user.username
                                .substring(0, user.username.length >= 2 ? 2 : 1)
                                .toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.username,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID ${user.id} · ${adminRoleLabel(user.role)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: _userToggleTooltip(controller, user),
                          child: Switch(
                            value: user.enabled,
                            onChanged:
                                controller.isWorking ||
                                    !_canToggleUser(controller, user)
                                ? null
                                : (value) => ref
                                      .read(adminCenterControllerProvider)
                                      .updateUserEnabled(user, value),
                          ),
                        ),
                        if (UserRole.fromValue(user.role) !=
                            UserRole.superAdmin) ...[
                          const SizedBox(width: 8),
                          if (compactActions)
                            IconButton(
                              tooltip: '修改密码',
                              onPressed: controller.isWorking
                                  ? null
                                  : () => promptPasswordReset(user),
                              icon: const Icon(Icons.lock_reset_rounded),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: controller.isWorking
                                  ? null
                                  : () => promptPasswordReset(user),
                              icon: const Icon(
                                Icons.lock_reset_rounded,
                                size: 18,
                              ),
                              label: const Text('修改密码'),
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 18),
          child: Center(
            child: GlassActionButton(
              label: '添加用户',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: controller.isWorking ? null : promptCreateUser,
            ),
          ),
        ),
      ],
    );
  }

  bool _canToggleUser(AdminCenterController controller, AdminUserView user) {
    if (!user.enabled || UserRole.fromValue(user.role) != UserRole.superAdmin) {
      return true;
    }
    return controller.isCurrentUser(user) &&
        controller.enabledSuperAdminCount > 1;
  }

  String _userToggleTooltip(
    AdminCenterController controller,
    AdminUserView user,
  ) {
    if (!user.enabled) {
      return '启用用户';
    }
    if (UserRole.fromValue(user.role) != UserRole.superAdmin) {
      return '停用用户';
    }
    if (!controller.isCurrentUser(user)) {
      return '管理员只能停用自己的账号';
    }
    if (controller.enabledSuperAdminCount <= 1) {
      return '必须保留至少一个启用的管理员';
    }
    return '停用自己的管理员账号';
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          role.description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.inkSecondary,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${role.userCount} 人',
                          style: Theme.of(context).textTheme.headlineSmall
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
        ...controller.users.map((user) {
          final isCurrentUser = controller.isCurrentUser(user);
          return Padding(
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isCurrentUser
                              ? '当前账号 · 角色已锁定'
                              : user.enabled
                              ? '当前启用'
                              : '当前停用',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (isCurrentUser)
                    GlassSurface(
                      borderRadius: BorderRadius.circular(14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 17,
                            color: palette.inkSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            adminRoleLabel(user.role),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    )
                  else
                    GlassSurface(
                      borderRadius: BorderRadius.circular(14),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: user.role,
                          borderRadius: BorderRadius.circular(16),
                          items: adminRoles
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role.value,
                                  child: Text(role.label),
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
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _BookManagementSection extends ConsumerWidget {
  const _BookManagementSection({required this.controller});

  final AdminCenterController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    final auth = ref.watch(authControllerProvider);
    final filteredBooks = controller.filteredBooks;
    final isTablet = Responsive.isTablet(context);
    final isDesktop = Responsive.isDesktop(context);
    final bookTileMaxWidth = isDesktop ? 176.0 : (isTablet ? 168.0 : 156.0);
    final double? bookTileHeight = isDesktop
        ? 266
        : isTablet
        ? 256
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final summary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '书籍管理',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SummaryChip(
                        label: '图书总数',
                        value: '${controller.bookCount}',
                      ),
                      _SummaryChip(
                        label: '当前分组',
                        value: '${controller.availableBookGroups.length - 1}',
                      ),
                      _SummaryChip(
                        label: '已勾选',
                        value: '${controller.selectedBookCount}',
                      ),
                    ],
                  ),
                ],
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 18),
                    _UploadBookButton(controller: controller),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _UploadBookButton(controller: controller),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                onChanged: controller.setBookSearchQuery,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '查找书名、作者或分组',
                  labelText: '书籍查找',
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: GlassSegmentedControl<String>(
                    showSelectedIcon: false,
                    segments: controller.availableBookGroups
                        .map(
                          (group) => ButtonSegment<String>(
                            value: group,
                            icon: Icon(
                              group == AdminCenterController.allBookGroupsLabel
                                  ? Icons.apps_rounded
                                  : Icons.folder_outlined,
                              size: 17,
                            ),
                            label: Text(group),
                          ),
                        )
                        .toList(),
                    selected: {controller.selectedBookGroup},
                    onSelectionChanged: (selection) =>
                        controller.setBookGroupFilter(selection.first),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: filteredBooks.isEmpty
                        ? null
                        : controller.toggleSelectAllVisibleBooks,
                    icon: Icon(
                      controller.areAllVisibleBooksSelected
                          ? Icons.deselect
                          : Icons.select_all,
                    ),
                    label: Text(
                      controller.areAllVisibleBooksSelected ? '取消全选' : '全选当前结果',
                    ),
                  ),
                  if (controller.hasBookSelection)
                    FilledButton.tonalIcon(
                      onPressed: controller.isWorking
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => GlassAlertDialog(
                                  title: const Text('批量删除图书'),
                                  content: Text(
                                    '确定删除已勾选的 ${controller.selectedBookCount} 本图书吗？这会同时清理图书授权、批注、书签和阅读进度记录。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('确认删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && context.mounted) {
                                await controller.deleteSelectedBooks();
                              }
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        controller.isWorking
                            ? '删除中...'
                            : '批量删除 ${controller.selectedBookCount} 本',
                      ),
                    ),
                  Text(
                    '当前显示 ${filteredBooks.length} 本',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.inkSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ContentSwapTransition(
          transitionKey: controller.selectedBookGroup,
          child: controller.books.isEmpty
              ? const _EmptyPanel(
                  title: '还没有可管理的书籍',
                  body: '先导入一本图书，这里会自动切到封面管理视图。',
                )
              : filteredBooks.isEmpty
              ? const _EmptyPanel(
                  title: '没有找到匹配图书',
                  body: '试试更换搜索词，或切换到其他分组查看。',
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredBooks.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: bookTileMaxWidth,
                    mainAxisExtent: bookTileHeight,
                    childAspectRatio: isTablet || isDesktop ? 1 : 0.55,
                    mainAxisSpacing: isTablet ? 16 : 12,
                    crossAxisSpacing: isTablet ? 16 : 12,
                  ),
                  itemBuilder: (context, index) {
                    final book = filteredBooks[index];
                    return _AdminBookTile(
                      book: book,
                      selected: controller.selectedBookIds.contains(book.id),
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
                      onTap: () => context.push('/admin/books/${book.id}'),
                      onSelectionToggle: () =>
                          controller.toggleBookSelection(book.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AdminBookTile extends StatelessWidget {
  const _AdminBookTile({
    required this.book,
    required this.selected,
    required this.onTap,
    required this.onSelectionToggle,
    this.imageUrl,
    this.headers,
  });

  final AdminBookSummary book;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSelectionToggle;
  final String? imageUrl;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final titleStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    final titleFontSize = titleStyle?.fontSize ?? 12;
    final titleLineHeight =
        MediaQuery.textScalerOf(context).scale(titleFontSize) *
        (titleStyle?.height ?? 1.3);

    return GlassCard(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: selected ? palette.accent : palette.line,
        width: selected ? 1.6 : 1,
      ),
      padding: const EdgeInsets.all(9),
      blur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: HeroMode(
                    enabled: !MediaQuery.of(context).disableAnimations,
                    child: Hero(
                      tag: 'admin-book-cover-${book.id}',
                      transitionOnUserGestures: true,
                      child: Material(
                        color: Colors.transparent,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF5D3A22), Color(0xFF93633A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: imageUrl == null
                              ? _AdminBookFallback(title: book.title)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: Image.network(
                                    imageUrl!,
                                    headers: headers,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _AdminBookFallback(
                                              title: book.title,
                                            ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onSelectionToggle,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                if ((book.groupName ?? '').trim().isNotEmpty)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.56),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          book.groupName!,
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
          const SizedBox(height: 9),
          SizedBox(
            height: titleLineHeight * 2,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminBookFallback extends StatelessWidget {
  const _AdminBookFallback({required this.title});

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
            maxLines: 4,
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
      allowedExtensions: const ['txt', 'epub', 'pdf', 'cbz', 'fb2', 'mobi'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    final filePath = file.path;
    final fileBytes = file.bytes;
    if ((filePath == null || filePath.trim().isEmpty) && fileBytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法读取所选文件，请重新选择')));
      }
      return;
    }

    if (!context.mounted) {
      return;
    }

    await ref
        .read(adminCenterControllerProvider)
        .uploadBook(
          filePath: filePath,
          fileBytes: fileBytes,
          fileName: file.name,
        );
  }
}

class _AdminAnnotationBookGroup {
  const _AdminAnnotationBookGroup({
    required this.bookId,
    required this.bookTitle,
    required this.book,
    required this.annotations,
  });

  final int bookId;
  final String bookTitle;
  final AdminBookSummary? book;
  final List<AdminAnnotationView> annotations;

  int get annotationCount => annotations.length;
  int get visibleCount => annotations.where((item) => !item.deleted).length;
  String get latestUpdatedAt =>
      annotations.isEmpty ? '' : annotations.first.updatedAt;
}

class _AnnotationManagementSection extends ConsumerStatefulWidget {
  const _AnnotationManagementSection({required this.controller});

  final AdminCenterController controller;

  @override
  ConsumerState<_AnnotationManagementSection> createState() =>
      _AnnotationManagementSectionState();
}

class _AnnotationManagementSectionState
    extends ConsumerState<_AnnotationManagementSection> {
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
    final controller = widget.controller;
    final groups = _buildGroups(controller);
    final filteredGroups = _filterGroups(groups, _query);

    if (controller.annotations.isEmpty) {
      return const _EmptyPanel(
        title: '还没有批注记录',
        body: '用户产生高亮与批注后，这里会出现按书聚合的后台列表。',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '批注管理',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索书名、作者、分组或格式',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (filteredGroups.isEmpty)
          const _EmptyPanel(title: '没有找到匹配书籍', body: '试试换个书名、作者或分组关键词。')
        else
          ...filteredGroups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _AdminAnnotationBookCard(
                group: group,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _AdminAnnotationBookDetailScreen(
                        bookId: group.bookId,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  List<_AdminAnnotationBookGroup> _buildGroups(
    AdminCenterController controller,
  ) {
    final booksById = <int, AdminBookSummary>{
      for (final book in controller.books) book.id: book,
    };
    final grouped = <int, List<AdminAnnotationView>>{};
    for (final annotation in controller.annotations) {
      grouped
          .putIfAbsent(annotation.bookId, () => <AdminAnnotationView>[])
          .add(annotation);
    }

    return grouped.entries.map((entry) {
      final items = List<AdminAnnotationView>.from(entry.value)
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      final book = booksById[entry.key];
      return _AdminAnnotationBookGroup(
        bookId: entry.key,
        bookTitle: book?.title ?? items.first.bookTitle,
        book: book,
        annotations: items,
      );
    }).toList()..sort(
      (left, right) => right.latestUpdatedAt.compareTo(left.latestUpdatedAt),
    );
  }

  List<_AdminAnnotationBookGroup> _filterGroups(
    List<_AdminAnnotationBookGroup> groups,
    String query,
  ) {
    if (query.isEmpty) {
      return groups;
    }
    final normalized = query.toLowerCase();
    return groups.where((group) {
      final title = group.bookTitle.toLowerCase();
      final author = (group.book?.author ?? '').toLowerCase();
      final format = (group.book?.format ?? '').toLowerCase();
      final groupName = (group.book?.groupName ?? '').toLowerCase();
      return title.contains(normalized) ||
          author.contains(normalized) ||
          format.contains(normalized) ||
          groupName.contains(normalized);
    }).toList();
  }
}

class _AdminAnnotationBookDetailScreen extends ConsumerStatefulWidget {
  const _AdminAnnotationBookDetailScreen({required this.bookId});

  final int bookId;

  @override
  ConsumerState<_AdminAnnotationBookDetailScreen> createState() =>
      _AdminAnnotationBookDetailScreenState();
}

class _AdminAnnotationBookDetailScreenState
    extends ConsumerState<_AdminAnnotationBookDetailScreen> {
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
    final controller = ref.watch(adminCenterControllerProvider);
    final palette = AppReaderPalette.of(context);
    final booksById = <int, AdminBookSummary>{
      for (final book in controller.books) book.id: book,
    };
    final book = booksById[widget.bookId];
    final annotations =
        controller.annotations
            .where((item) => item.bookId == widget.bookId)
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final filteredAnnotations = _filterAnnotations(annotations, _query);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          book?.title ?? '书籍批注',
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
                        _AdminMiniBookCover(book: book, bookId: widget.bookId),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book?.title ?? '未命名书籍',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (((book?.author ?? '').trim()).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    book!.author!,
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
                                    value: annotations.length.toString(),
                                  ),
                                  if (book != null)
                                    _SummaryChip(
                                      label: '格式',
                                      value: book.format,
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
                        hintText: '搜索用户、摘录、笔记或日期',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: _searchController.clear,
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (annotations.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('这本书暂时还没有批注。')),
              )
            else if (filteredAnnotations.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('没有找到匹配的批注。')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList.separated(
                  itemBuilder: (context, index) {
                    final annotation = filteredAnnotations[index];
                    return _AdminAnnotationCard(annotation: annotation);
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemCount: filteredAnnotations.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<AdminAnnotationView> _filterAnnotations(
    List<AdminAnnotationView> annotations,
    String query,
  ) {
    if (query.isEmpty) {
      return annotations;
    }
    final normalized = query.toLowerCase();
    return annotations.where((annotation) {
      final username = annotation.username.toLowerCase();
      final quote = (annotation.quoteText ?? '').toLowerCase();
      final note = (annotation.noteText ?? '').toLowerCase();
      final date = annotation.updatedAt.toLowerCase();
      return username.contains(normalized) ||
          quote.contains(normalized) ||
          note.contains(normalized) ||
          date.contains(normalized);
    }).toList();
  }
}

class _AdminAnnotationBookCard extends ConsumerWidget {
  const _AdminAnnotationBookCard({required this.group, required this.onTap});

  final _AdminAnnotationBookGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppReaderPalette.of(context);
    final latest = group.annotations.first;

    return _PanelCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Row(
          children: [
            _AdminMiniBookCover(book: group.book, bookId: group.bookId),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.bookTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (((group.book?.author ?? '').trim()).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        group.book!.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.inkSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    latest.quoteText?.trim().isNotEmpty == true
                        ? latest.quoteText!
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
                    children: [
                      _StatusChip(
                        label: '${group.annotationCount} 条批注',
                        highlighted: true,
                      ),
                      _StatusChip(
                        label: '显示 ${group.visibleCount} 条',
                        highlighted: group.visibleCount > 0,
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
    );
  }
}

class _AdminMiniBookCover extends ConsumerWidget {
  const _AdminMiniBookCover({required this.book, required this.bookId});

  final AdminBookSummary? book;
  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final imageUrl = auth.accessToken == null
        ? null
        : ref.read(apiClientProvider).buildUrl('/api/me/books/$bookId/cover');
    final headers = auth.accessToken == null
        ? null
        : ref.read(apiClientProvider).coverHeaders(auth.accessToken!);

    return SizedBox(
      width: 68,
      height: 96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF5D3A22), Color(0xFF93633A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: imageUrl == null
            ? _AdminBookFallback(title: book?.title ?? '未命名书籍')
            : ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  imageUrl,
                  headers: headers,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _AdminBookFallback(title: book?.title ?? '未命名书籍'),
                ),
              ),
      ),
    );
  }
}

class _AdminAnnotationCard extends ConsumerWidget {
  const _AdminAnnotationCard({required this.annotation});

  final AdminAnnotationView annotation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(adminCenterControllerProvider);
    final palette = AppReaderPalette.of(context);

    return _PanelCard(
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
                      annotation.username,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(annotation.updatedAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.inkSecondary,
                      ),
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
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.inkTertiary),
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
    );
  }
}

// ignore: unused_element
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
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${bookmark.username} · ${_formatDate(bookmark.updatedAt)}',
                                style: Theme.of(context).textTheme.bodySmall
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
  String _role = adminRoles.first.value;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassAlertDialog(
      scrollable: true,
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
              borderRadius: BorderRadius.circular(16),
              items: adminRoles
                  .map(
                    (role) => DropdownMenuItem(
                      value: role.value,
                      child: Text(role.label),
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
              decoration: const InputDecoration(
                labelText: '角色',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
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
    return GlassCard(child: child);
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
    case AdminSection.librarySources:
      return '资源扫描';
  }
}

IconData _sectionIcon(AdminSection section) {
  switch (section) {
    case AdminSection.users:
      return Icons.people_outline_rounded;
    case AdminSection.roles:
      return Icons.admin_panel_settings_outlined;
    case AdminSection.books:
      return Icons.menu_book_outlined;
    case AdminSection.annotations:
      return Icons.format_quote_rounded;
    case AdminSection.librarySources:
      return Icons.cloud_sync_outlined;
  }
}

String _formatDate(String value) {
  return value.split('T').first;
}
