import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import 'glass_surface.dart';

class GlassBottomSheet extends StatelessWidget {
  const GlassBottomSheet({
    super.key,
    required this.child,
    this.padding,
    this.level = GlassSurfaceLevel.elevated,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final GlassSurfaceLevel level;

  @override
  Widget build(BuildContext context) {
    final platform = GlassPlatformStyle.of(context);
    return GlassSurface(
      level: level,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(platform.dialogRadius),
      ),
      padding: padding,
      child: child,
    );
  }
}
