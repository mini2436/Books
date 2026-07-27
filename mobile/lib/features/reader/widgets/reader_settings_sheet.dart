import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/reader_preferences_controller.dart';
import '../../../shared/theme/reader_theme_extension.dart';
import '../../../shared/widgets/glass_segmented_control.dart';
import '../../../shared/widgets/glass_bottom_sheet.dart';

class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: GlassBottomSheet(
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
  const ReaderSettingsPanelContent({
    super.key,
    this.showDoneAction = false,
    this.showHeader = true,
    this.compact = false,
  });

  final bool showDoneAction;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(readerPreferencesControllerProvider);
    final preferences = controller.value;
    final palette = AppReaderPalette.of(context);
    final sectionGap = compact ? 14.0 : 18.0;
    final titleGap = compact ? 12.0 : 16.0;
    final themeSpacing = compact ? 10.0 : 12.0;
    final themeSwatchSize = compact ? 44.0 : 52.0;
    final segmentedStyle = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );

    Widget settingsBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: '字号', bottomSpacing: compact ? 8 : 12),
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
        SizedBox(height: sectionGap),
        _SectionTitle(title: '字体', bottomSpacing: compact ? 8 : 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: GlassSegmentedControl<ReaderFontFamilyPreference>(
            style: segmentedStyle,
            showSelectedIcon: false,
            segments: ReaderFontFamilyPreference.values
                .map(
                  (family) => ButtonSegment<ReaderFontFamilyPreference>(
                    value: family,
                    label: Text(family.label),
                  ),
                )
                .toList(),
            selected: {preferences.fontFamily},
            onSelectionChanged: (selection) =>
                controller.setFontFamily(selection.first),
          ),
        ),
        if (preferences.fontFamily.licenseNotice != null) ...[
          SizedBox(height: compact ? 6 : 8),
          Text(
            preferences.fontFamily.licenseNotice!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.inkTertiary,
              height: 1.35,
            ),
          ),
        ],
        SizedBox(height: sectionGap),
        _SectionTitle(title: '行高', bottomSpacing: compact ? 8 : 12),
        GlassSegmentedControl<double>(
          style: segmentedStyle,
          segments: const [
            ButtonSegment(value: 1.6, label: Text('紧凑')),
            ButtonSegment(value: 1.8, label: Text('标准')),
            ButtonSegment(value: 2.0, label: Text('宽松')),
          ],
          selected: {preferences.lineHeight},
          onSelectionChanged: (selection) =>
              controller.setLineHeight(selection.first),
        ),
        SizedBox(height: sectionGap),
        _SectionTitle(title: '主题', bottomSpacing: compact ? 8 : 12),
        Wrap(
          spacing: themeSpacing,
          runSpacing: themeSpacing,
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
                    width: themeSwatchSize,
                    height: themeSwatchSize,
                    decoration: BoxDecoration(
                      color: modePalette.background,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected ? modePalette.accent : modePalette.line,
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 6 : 8),
                  Text(
                    switch (mode) {
                      ReaderThemeMode.paper => '默认白',
                      ReaderThemeMode.kraft => '牛皮纸',
                      ReaderThemeMode.eyeCare => '护眼',
                      ReaderThemeMode.night => '夜间',
                    },
                    style: compact
                        ? Theme.of(context).textTheme.bodySmall
                        : null,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );

    if (compact) {
      settingsBody = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 292),
        child: settingsBody,
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (showHeader) ...[
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
          SizedBox(height: titleGap),
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
          SizedBox(height: titleGap),
        ],
        Align(alignment: Alignment.topLeft, child: settingsBody),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.bottomSpacing = 12});

  final String title;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
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
