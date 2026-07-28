import 'package:flutter/material.dart' hide Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:private_reader_mobile/shared/localization/localized_text.dart';

import '../../shared/theme/reader_theme_extension.dart';
import '../../shared/widgets/glass_dialog.dart';
import 'admin_center_controller.dart';

class AdminBookImportProgressDialog extends ConsumerWidget {
  const AdminBookImportProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      adminCenterControllerProvider.select(
        (controller) => controller.bookImportProgress,
      ),
    );
    final palette = AppReaderPalette.of(context);
    final isTerminal = progress?.isTerminal ?? false;

    return PopScope(
      canPop: isTerminal,
      child: GlassAlertDialog(
        title: const Text('导入图书'),
        content: progress == null
            ? const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    progress.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Semantics(
                    label: _phaseLabel(progress.phase),
                    value: progress.uploadPercentage == null
                        ? null
                        : '${progress.uploadPercentage}%',
                    child: progress.phase == AdminBookImportPhase.failed
                        ? const SizedBox.shrink()
                        : LinearProgressIndicator(
                            value: _indicatorValue(progress),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(999),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _phaseIcon(progress.phase),
                        size: 21,
                        color: progress.phase == AdminBookImportPhase.failed
                            ? Theme.of(context).colorScheme.error
                            : palette.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: Column(
                            key: ValueKey(progress.phase),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _phaseLabel(progress.phase),
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (_detailText(progress) case final detail?) ...[
                                const SizedBox(height: 4),
                                Text(
                                  detail,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: palette.inkSecondary),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        actions: !isTerminal
            ? null
            : [
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ref
                        .read(adminCenterControllerProvider)
                        .dismissBookImportProgress();
                  },
                  child: Text(
                    progress?.phase == AdminBookImportPhase.completed
                        ? '完成'
                        : '关闭',
                  ),
                ),
              ],
      ),
    );
  }

  double? _indicatorValue(AdminBookImportProgress progress) {
    return switch (progress.phase) {
      AdminBookImportPhase.uploading => progress.uploadFraction,
      AdminBookImportPhase.completed => 1,
      AdminBookImportPhase.processing ||
      AdminBookImportPhase.refreshing => null,
      AdminBookImportPhase.failed => null,
    };
  }

  String _phaseLabel(AdminBookImportPhase phase) => switch (phase) {
    AdminBookImportPhase.uploading => '正在上传',
    AdminBookImportPhase.processing => '服务器正在解析图书',
    AdminBookImportPhase.refreshing => '正在更新书库',
    AdminBookImportPhase.completed => '导入完成',
    AdminBookImportPhase.failed => '导入失败',
  };

  IconData _phaseIcon(AdminBookImportPhase phase) => switch (phase) {
    AdminBookImportPhase.uploading => Icons.cloud_upload_outlined,
    AdminBookImportPhase.processing => Icons.auto_stories_outlined,
    AdminBookImportPhase.refreshing => Icons.sync,
    AdminBookImportPhase.completed => Icons.check_circle_outline,
    AdminBookImportPhase.failed => Icons.error_outline,
  };

  String? _detailText(AdminBookImportProgress progress) {
    return switch (progress.phase) {
      AdminBookImportPhase.uploading => _uploadDetail(progress),
      AdminBookImportPhase.processing => '上传已完成，正在提取书名、封面和正文内容。',
      AdminBookImportPhase.refreshing => '导入成功，正在刷新管理后台中的书籍列表。',
      AdminBookImportPhase.completed =>
        progress.importedTitle == null
            ? '图书已经加入书库。'
            : '《${progress.importedTitle}》已经加入书库。',
      AdminBookImportPhase.failed => progress.errorMessage,
    };
  }

  String _uploadDetail(AdminBookImportProgress progress) {
    final percentage = progress.uploadPercentage;
    if (progress.totalBytes <= 0) {
      return percentage == null ? '正在向服务器传输文件。' : '$percentage%';
    }
    return '${percentage ?? 0}% · ${_formatBytes(progress.bytesSent)} / ${_formatBytes(progress.totalBytes)}';
  }

  String _formatBytes(int bytes) {
    const megabyte = 1024 * 1024;
    if (bytes >= megabyte) {
      return '${(bytes / megabyte).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}
