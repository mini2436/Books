import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/reader_theme_extension.dart';
import '../auth/auth_controller.dart';
import '../bookshelf/bookshelf_controller.dart';
import '../reader/widgets/reader_settings_sheet.dart';
import '../settings/reader_preferences_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: palette.accent.withValues(alpha: 0.14),
                  foregroundColor: palette.accent,
                  child: Text(
                    user?.initials ?? 'PR',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.username ?? '未登录',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user?.role ?? 'READER',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.inkSecondary,
                        ),
                      ),
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
                ref.read(readerPreferencesControllerProvider).setThemeMode(
                  isNightMode ? ReaderThemeMode.paper : ReaderThemeMode.night,
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
            _ActionTile(
              icon: Icons.desktop_windows_outlined,
              title: '桌面端阅读',
              subtitle: '桌面端继续使用 Web 浏览器阅读 PDF 与完整后台能力',
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
