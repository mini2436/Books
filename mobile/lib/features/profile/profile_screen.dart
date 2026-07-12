import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user_role.dart';
import '../../shared/theme/reader_theme_extension.dart';
import '../auth/auth_controller.dart';
import '../bookshelf/bookshelf_controller.dart';
import '../reader/widgets/reader_settings_sheet.dart';
import '../settings/reader_preferences_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final shelf = ref.watch(bookshelfControllerProvider);
    final preferences = ref.watch(readerPreferencesControllerProvider);
    final palette = AppReaderPalette.of(context);
    final user = auth.user;
    final isNightMode = preferences.themeMode == ReaderThemeMode.night;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Material(
                          color: palette.accent.withValues(alpha: 0.14),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: auth.isWorking ? null : _pickAvatar,
                            child:
                                user?.hasAvatar == true &&
                                    auth.accessToken != null
                                ? Image.network(
                                    ref
                                        .read(apiClientProvider)
                                        .buildUrl('/api/me/profile/avatar'),
                                    key: ValueKey(user?.avatarVersion),
                                    headers: ref
                                        .read(apiClientProvider)
                                        .coverHeaders(auth.accessToken!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => _AvatarInitials(
                                      initials: user?.initials ?? 'PR',
                                    ),
                                  )
                                : _AvatarInitials(
                                    initials: user?.initials ?? 'PR',
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.background,
                              width: 3,
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user?.displayLabel ?? '未登录',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: auth.isWorking || user == null
                                ? null
                                : _editDisplayName,
                            visualDensity: VisualDensity.compact,
                            tooltip: '编辑个人名称',
                            icon: const Icon(Icons.edit_rounded, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user == null
                            ? UserRole.reader.value
                            : '@${user.username} · ${user.role}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.inkSecondary,
                        ),
                      ),
                      if (auth.isWorking) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _ProfileStat(
                    label: '可读书籍',
                    value: '${shelf.books.length}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProfileStat(
                    label: '待同步',
                    value: '${shelf.pendingCount}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _ActionTile(
              icon: Icons.tune,
              title: '阅读设置',
              subtitle: '主题、字号、字体与行高',
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => const ReaderSettingsSheet(),
              ),
            ),
            _ActionTile(
              icon: Icons.dark_mode_outlined,
              title: '夜间模式',
              subtitle: 'APP 与阅读界面同步切换深色主题',
              trailing: Switch(
                value: isNightMode,
                onChanged: (value) {
                  ref
                      .read(readerPreferencesControllerProvider)
                      .setThemeMode(
                        value ? ReaderThemeMode.night : ReaderThemeMode.paper,
                      );
                },
              ),
              onTap: () {
                ref
                    .read(readerPreferencesControllerProvider)
                    .setThemeMode(
                      isNightMode
                          ? ReaderThemeMode.paper
                          : ReaderThemeMode.night,
                    );
              },
            ),
            _ActionTile(
              icon: Icons.sync,
              title: '同步状态',
              subtitle: '离线操作将在网络恢复后自动补偿',
              trailing: Text(
                '${shelf.pendingCount}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: auth.isWorking ? null : auth.signOut,
              child: const Text(
                '退出登录',
                style: TextStyle(color: Color(0xFFD93025)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || !mounted) {
      return;
    }
    final file = result.files.single;
    final filePath = file.path;
    final fileBytes = file.bytes;
    if ((filePath == null || filePath.trim().isEmpty) && fileBytes == null) {
      _showError('无法读取所选图片，请重新选择');
      return;
    }
    try {
      await ref
          .read(authControllerProvider)
          .uploadAvatar(
            filePath: filePath,
            fileBytes: fileBytes,
            fileName: file.name,
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('头像已更新')));
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editDisplayName() async {
    final auth = ref.read(authControllerProvider);
    final textController = TextEditingController(
      text: auth.user?.displayName ?? auth.user?.username ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑个人名称'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '个人名称',
            hintText: '留空将恢复显示登录账号',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (value == null || !mounted) {
      return;
    }
    try {
      await ref.read(authControllerProvider).updateDisplayName(value);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('个人名称已更新')));
      }
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
  }
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: palette.accent,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              label,
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: palette.backgroundSoft,
        foregroundColor: palette.inkSecondary,
        child: Icon(icon),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
