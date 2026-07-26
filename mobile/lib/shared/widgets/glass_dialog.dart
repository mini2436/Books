import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import '../theme/reader_theme_extension.dart';
import '../utils/responsive.dart';
import 'glass_surface.dart';

class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
    this.insetPadding,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 14, 24, 8),
    this.actionsPadding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;
  final EdgeInsets? insetPadding;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry actionsPadding;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final platform = GlassPlatformStyle.of(context);
    final phone = Responsive.platformLayout(context) == AppPlatformLayout.phone;
    final effectiveInset =
        insetPadding ??
        EdgeInsets.symmetric(horizontal: phone ? 18 : 40, vertical: 24);
    final titleWidget = title == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w700,
              ),
              child: title!,
            ),
          );
    Widget? contentWidget = content;
    if (contentWidget != null) {
      contentWidget = Padding(padding: contentPadding, child: contentWidget);
    }
    if (scrollable) {
      contentWidget = Flexible(
        child: SingleChildScrollView(child: contentWidget),
      );
    }

    return Dialog(
      insetPadding: effectiveInset,
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: phone ? 520 : 600,
          maxHeight:
              MediaQuery.sizeOf(context).height - effectiveInset.vertical,
        ),
        child: GlassSurface(
          level: GlassSurfaceLevel.elevated,
          borderRadius: BorderRadius.circular(platform.dialogRadius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleWidget ?? const SizedBox.shrink(),
              contentWidget ?? const SizedBox.shrink(),
              if (actions case final actionWidgets?
                  when actionWidgets.isNotEmpty)
                Padding(
                  padding: actionsPadding,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actionWidgets,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
