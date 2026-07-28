import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_locale.dart';
import '../localization/app_localizations.dart';
import '../localization/localized_text.dart';
import 'glass_dialog.dart';

class LanguageIconButton extends ConsumerWidget {
  const LanguageIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: context.tr('切换语言'),
      onPressed: () => showLanguagePicker(context, ref),
      icon: const Icon(Icons.language_rounded),
    );
  }
}

Future<void> showLanguagePicker(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(appLocaleControllerProvider);
  final selected = await showDialog<AppLanguage>(
    context: context,
    builder: (dialogContext) {
      final current = controller.effectiveLanguage(dialogContext);
      return GlassAlertDialog(
        title: const Text('选择界面语言'),
        content: RadioGroup<AppLanguage>(
          groupValue: current,
          onChanged: (value) => Navigator.of(dialogContext).pop(value),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<AppLanguage>(
                value: AppLanguage.chinese,
                title: Text('中文'),
                subtitle: Text('简体中文'),
              ),
              RadioListTile<AppLanguage>(
                value: AppLanguage.english,
                title: Text('English'),
                subtitle: Text('English'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
  if (selected != null) {
    await controller.setLanguage(selected);
  }
}
