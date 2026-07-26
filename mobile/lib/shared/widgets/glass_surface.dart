import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import '../theme/reader_theme_extension.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.level = GlassSurfaceLevel.standard,
    this.padding,
    this.borderRadius,
    this.tint,
    this.border,
    this.blur = true,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final GlassSurfaceLevel level;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? tint;
  final BoxBorder? border;
  final bool blur;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final style = GlassPlatformStyle.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(style.cardRadius);
    final surfaceColor = (tint ?? palette.panel).withValues(
      alpha: style.opacityFor(level),
    );
    final borderColor = dark
        ? Colors.white.withValues(alpha: style.borderOpacity)
        : palette.ink.withValues(alpha: style.borderOpacity);
    final shadowStrength = level == GlassSurfaceLevel.subtle ? 0.45 : 1.0;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: radius,
        border: border ?? Border.all(color: borderColor),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (blur) {
      content = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: style.blurSigma,
          sigmaY: style.blurSigma,
        ),
        child: content,
      );
    }

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: palette.ink.withValues(
                alpha: style.shadowOpacity * shadowStrength,
              ),
              blurRadius: level == GlassSurfaceLevel.floating ? 30 : 22,
              offset: Offset(0, level == GlassSurfaceLevel.floating ? 12 : 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: clipBehavior,
          child: content,
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.level = GlassSurfaceLevel.standard,
    this.borderRadius,
    this.border,
    this.blur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final GlassSurfaceLevel level;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final radius =
        borderRadius ??
        BorderRadius.circular(GlassPlatformStyle.of(context).cardRadius);
    return GlassSurface(
      level: level,
      borderRadius: radius,
      border: border,
      blur: blur,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
