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
    this.shadow = true,
    this.enableLiquidGlass = true,
    this.clipBehavior = Clip.antiAlias,
    this.repaintBoundary = true,
  });

  final Widget child;
  final GlassSurfaceLevel level;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? tint;
  final BoxBorder? border;
  final bool blur;
  final bool shadow;
  final bool enableLiquidGlass;
  final Clip clipBehavior;
  final bool repaintBoundary;

  @override
  Widget build(BuildContext context) {
    final palette = AppReaderPalette.of(context);
    final style = GlassPlatformStyle.of(context);
    final material = GlassMaterialTheme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final useLiquidGlass =
        enableLiquidGlass && material.mode == GlassMaterialMode.liquid;
    final radius = borderRadius ?? BorderRadius.circular(style.cardRadius);
    final surfaceColor = (tint ?? palette.panel).withValues(
      alpha: style.opacityFor(level),
    );
    final borderColor = dark
        ? Colors.white.withValues(alpha: style.borderOpacity)
        : palette.ink.withValues(alpha: style.borderOpacity);
    final shadowStrength = level == GlassSurfaceLevel.subtle ? 0.45 : 1.0;
    final topTint = Color.alphaBlend(
      Colors.white.withValues(alpha: dark ? 0.05 : 0.12),
      surfaceColor,
    );
    final bottomTint = Color.alphaBlend(
      palette.accent.withValues(alpha: dark ? 0.04 : 0.025),
      surfaceColor,
    );

    final paddedChild = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    Widget content = useLiquidGlass
        ? _LiquidGlassLayer(
            surfaceColor: surfaceColor,
            borderColor: borderColor,
            border: border,
            accent: palette.accent,
            radius: radius,
            dark: dark,
            child: paddedChild,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [topTint, surfaceColor, bottomTint],
                stops: const [0, 0.48, 1],
              ),
              borderRadius: radius,
              border: border ?? Border.all(color: borderColor),
            ),
            child: paddedChild,
          );
    if (blur) {
      content = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: style.blurSigma * (useLiquidGlass ? 1.16 : 1),
          sigmaY: style.blurSigma * (useLiquidGlass ? 1.16 : 1),
        ),
        child: content,
      );
    }

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: palette.ink.withValues(
                    alpha:
                        style.shadowOpacity *
                        shadowStrength *
                        (useLiquidGlass ? 0.55 : 1),
                  ),
                  blurRadius: useLiquidGlass
                      ? 8
                      : level == GlassSurfaceLevel.floating
                      ? 30
                      : 22,
                  offset: Offset(
                    0,
                    useLiquidGlass
                        ? 3
                        : level == GlassSurfaceLevel.floating
                        ? 12
                        : 8,
                  ),
                ),
              ]
            : const [],
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: content,
      ),
    );
    return repaintBoundary ? RepaintBoundary(child: surface) : surface;
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
    this.enableLiquidGlass = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final GlassSurfaceLevel level;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final bool blur;
  final bool enableLiquidGlass;

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
      enableLiquidGlass: enableLiquidGlass,
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

class _LiquidGlassLayer extends StatefulWidget {
  const _LiquidGlassLayer({
    required this.surfaceColor,
    required this.borderColor,
    required this.border,
    required this.accent,
    required this.radius,
    required this.dark,
    required this.child,
  });

  final Color surfaceColor;
  final Color borderColor;
  final BoxBorder? border;
  final Color accent;
  final BorderRadius radius;
  final bool dark;
  final Widget child;

  @override
  State<_LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<_LiquidGlassLayer> {
  static const _restingHighlight = Alignment(-0.62, -0.78);

  Alignment _highlight = _restingHighlight;

  void _updateHighlight(PointerEvent event) {
    final size = context.size;
    if (size == null || size.isEmpty) {
      return;
    }
    final x = ((event.localPosition.dx / size.width) * 2 - 1).clamp(
      -0.86,
      0.86,
    );
    final y = ((event.localPosition.dy / size.height) * 2 - 1).clamp(
      -0.86,
      0.86,
    );
    final next = Alignment(x, y);
    if (next == _highlight) {
      return;
    }
    setState(() => _highlight = next);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final topTint = Color.alphaBlend(
      Colors.white.withValues(alpha: widget.dark ? 0.025 : 0.24),
      widget.surfaceColor,
    );
    final bottomTint = Color.alphaBlend(
      widget.accent.withValues(alpha: widget.dark ? 0.035 : 0.065),
      widget.surfaceColor,
    );
    final highlightColor = Colors.white.withValues(
      alpha: widget.dark ? 0.018 : 0.34,
    );

    return MouseRegion(
      onHover: _updateHighlight,
      onExit: (_) {
        if (_highlight != _restingHighlight) {
          setState(() => _highlight = _restingHighlight);
        }
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [topTint, widget.surfaceColor, bottomTint],
            stops: const [0, 0.52, 1],
          ),
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                key: const ValueKey('liquid-glass-highlight'),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: widget.radius,
                  gradient: RadialGradient(
                    center: _highlight,
                    radius: 0.92,
                    colors: [
                      highlightColor,
                      highlightColor.withValues(alpha: 0.035),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.46, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LiquidGlassEdgePainter(
                    radius: widget.radius,
                    highlight: _highlight,
                    accent: widget.accent,
                    borderColor: widget.borderColor,
                    dark: widget.dark,
                  ),
                ),
              ),
            ),
            if (widget.border case final customBorder?)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: widget.radius,
                      border: customBorder,
                    ),
                  ),
                ),
              ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _LiquidGlassEdgePainter extends CustomPainter {
  const _LiquidGlassEdgePainter({
    required this.radius,
    required this.highlight,
    required this.accent,
    required this.borderColor,
    required this.dark,
  });

  final BorderRadius radius;
  final Alignment highlight;
  final Color accent;
  final Color borderColor;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.75);
    final opposite = Alignment(-highlight.x, -highlight.y);
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..shader = LinearGradient(
        begin: highlight,
        end: opposite,
        colors: [
          Colors.white.withValues(alpha: dark ? 0.42 : 0.72),
          borderColor.withValues(alpha: 0.34),
          accent.withValues(alpha: dark ? 0.2 : 0.13),
        ],
        stops: const [0, 0.52, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, edgePaint);

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = dark
          ? Colors.white.withValues(alpha: 0.035)
          : Colors.black.withValues(alpha: 0.035);
    canvas.drawRRect(rrect.deflate(1.7), innerPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassEdgePainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.highlight != highlight ||
        oldDelegate.accent != accent ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.dark != dark;
  }
}
