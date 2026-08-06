import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import '../theme/reader_theme_extension.dart';
import 'glass_surface.dart';

class GlassSegmentedControl<T> extends StatelessWidget {
  const GlassSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.showSelectedIcon = false,
    this.multiSelectionEnabled = false,
    this.emptySelectionAllowed = false,
    this.style,
    this.expandedInsets,
    this.blur = true,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool showSelectedIcon;
  final bool multiSelectionEnabled;
  final bool emptySelectionAllowed;
  final ButtonStyle? style;
  final EdgeInsets? expandedInsets;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final platform = GlassPlatformStyle.of(context);
    final radius = BorderRadius.circular(999);
    return GlassSurface(
      level: GlassSurfaceLevel.subtle,
      borderRadius: radius,
      padding: const EdgeInsets.all(4),
      blur: blur,
      child: SegmentedButton<T>(
        segments: segments,
        selected: selected,
        onSelectionChanged: onSelectionChanged,
        showSelectedIcon: showSelectedIcon,
        multiSelectionEnabled: multiSelectionEnabled,
        emptySelectionAllowed: emptySelectionAllowed,
        expandedInsets: expandedInsets,
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: const WidgetStatePropertyAll(BorderSide.none),
          elevation: const WidgetStatePropertyAll(0),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: WidgetStatePropertyAll(Size(0, platform.controlHeight)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? palette.accent
                : palette.inkSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? palette.accent.withValues(alpha: 0.18)
                : Colors.transparent;
          }),
        ).merge(style),
      ),
    );
  }
}
