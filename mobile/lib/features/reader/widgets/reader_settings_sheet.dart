import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/reader_preferences_controller.dart';
import '../../../shared/theme/reader_theme_extension.dart';

class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 20,
        ),
        child: const ReaderSettingsPanelContent(showDoneAction: true),
      ),
    );
  }
}

class ReaderSettingsPanelContent extends ConsumerWidget {
  const ReaderSettingsPanelContent({super.key, this.showDoneAction = false});

  final bool showDoneAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(readerPreferencesControllerProvider);
    final preferences = controller.value;
    final palette = AppReaderPalette.of(context);

    return ListView(
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: palette.line,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              '阅读设置',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (showDoneAction)
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('完成'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionTitle(title: '字号'),
        Slider(
          value: preferences.fontScale,
          min: 0.9,
          max: 1.5,
          divisions: 30,
          onChanged: (value) => controller.setFontScale(value),
        ),
        Text(
          '${(preferences.fontScale * 100).round()}%',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.inkSecondary),
        ),
        const SizedBox(height: 18),
        _SectionTitle(title: '字体'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: ReaderFontFamilyPreference.values.map((family) {
            final selected = preferences.fontFamily == family;
            return ChoiceChip(
              label: Text(family.label),
              selected: selected,
              onSelected: (_) => controller.setFontFamily(family),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        _SectionTitle(title: '行高'),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 1.6, label: Text('紧凑')),
            ButtonSegment(value: 1.8, label: Text('标准')),
            ButtonSegment(value: 2.0, label: Text('宽松')),
          ],
          selected: {preferences.lineHeight},
          onSelectionChanged: (selection) =>
              controller.setLineHeight(selection.first),
        ),
        const SizedBox(height: 18),
        _SectionTitle(title: '主题'),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: ReaderThemeMode.values.map((mode) {
            final modePalette = AppReaderPalette.resolve(mode);
            final selected = preferences.themeMode == mode;
            return InkWell(
              onTap: () => controller.setThemeMode(mode),
              borderRadius: BorderRadius.circular(999),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: modePalette.background,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected ? modePalette.accent : modePalette.line,
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(switch (mode) {
                    ReaderThemeMode.paper => '默认白',
                    ReaderThemeMode.kraft => '牛皮纸',
                    ReaderThemeMode.eyeCare => '护眼',
                    ReaderThemeMode.night => '夜间',
                  }),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: palette.inkTertiary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
