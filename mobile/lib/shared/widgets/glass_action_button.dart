import 'package:flutter/material.dart' hide Text;
import 'package:private_reader_mobile/shared/localization/localized_text.dart';

import '../theme/glass_theme.dart';
import '../theme/reader_theme_extension.dart';
import 'glass_surface.dart';

class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
    this.accentColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final accent = accentColor ?? palette.accent;
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(16);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tint = Color.lerp(palette.panel, accent, 0.12) ?? palette.panel;

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? (loadingLabel ?? label) : label,
      child: AnimatedOpacity(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        opacity: enabled || loading ? 1 : 0.52,
        child: GlassSurface(
          level: GlassSurfaceLevel.elevated,
          tint: tint,
          borderRadius: radius,
          border: Border.all(
            color: accent.withValues(alpha: enabled || loading ? 0.28 : 0.12),
          ),
          shadow: false,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: radius,
              mouseCursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (loading)
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      else
                        Icon(icon, size: 19, color: accent),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          loading ? (loadingLabel ?? label) : label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: palette.ink,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
