import 'package:flutter/material.dart';

import '../utils/responsive.dart';

enum GlassSurfaceLevel { subtle, standard, elevated, floating }

enum GlassMaterialMode { lightweight, liquid }

extension GlassMaterialModeX on GlassMaterialMode {
  String get storageValue => name;

  static GlassMaterialMode fromStorage(String? value) {
    return GlassMaterialMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => GlassMaterialMode.lightweight,
    );
  }
}

@immutable
class GlassMaterialTheme extends ThemeExtension<GlassMaterialTheme> {
  const GlassMaterialTheme({required this.mode});

  final GlassMaterialMode mode;

  static GlassMaterialTheme of(BuildContext context) =>
      Theme.of(context).extension<GlassMaterialTheme>() ??
      const GlassMaterialTheme(mode: GlassMaterialMode.lightweight);

  @override
  GlassMaterialTheme copyWith({GlassMaterialMode? mode}) {
    return GlassMaterialTheme(mode: mode ?? this.mode);
  }

  @override
  GlassMaterialTheme lerp(
    covariant ThemeExtension<GlassMaterialTheme>? other,
    double t,
  ) {
    if (other is! GlassMaterialTheme) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

@immutable
class GlassPlatformStyle {
  const GlassPlatformStyle({
    required this.layout,
    required this.blurSigma,
    required this.surfaceOpacity,
    required this.elevatedOpacity,
    required this.floatingOpacity,
    required this.borderOpacity,
    required this.shadowOpacity,
    required this.cardRadius,
    required this.dialogRadius,
    required this.controlHeight,
  });

  final AppPlatformLayout layout;
  final double blurSigma;
  final double surfaceOpacity;
  final double elevatedOpacity;
  final double floatingOpacity;
  final double borderOpacity;
  final double shadowOpacity;
  final double cardRadius;
  final double dialogRadius;
  final double controlHeight;

  bool get isPhone => layout == AppPlatformLayout.phone;

  static GlassPlatformStyle of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (Responsive.platformLayout(context)) {
      AppPlatformLayout.phone => GlassPlatformStyle(
        layout: AppPlatformLayout.phone,
        blurSigma: 12,
        surfaceOpacity: dark ? 0.48 : 0.34,
        elevatedOpacity: dark ? 0.62 : 0.48,
        floatingOpacity: dark ? 0.42 : 0.2,
        borderOpacity: dark ? 0.1 : 0.09,
        shadowOpacity: dark ? 0.28 : 0.12,
        cardRadius: 20,
        dialogRadius: 26,
        controlHeight: 50,
      ),
      AppPlatformLayout.tablet => GlassPlatformStyle(
        layout: AppPlatformLayout.tablet,
        blurSigma: 17,
        surfaceOpacity: dark ? 0.58 : 0.46,
        elevatedOpacity: dark ? 0.7 : 0.58,
        floatingOpacity: dark ? 0.72 : 0.58,
        borderOpacity: dark ? 0.11 : 0.08,
        shadowOpacity: dark ? 0.28 : 0.11,
        cardRadius: 22,
        dialogRadius: 28,
        controlHeight: 46,
      ),
      AppPlatformLayout.web => GlassPlatformStyle(
        layout: AppPlatformLayout.web,
        blurSigma: 20,
        surfaceOpacity: dark ? 0.62 : 0.5,
        elevatedOpacity: dark ? 0.74 : 0.62,
        floatingOpacity: dark ? 0.76 : 0.62,
        borderOpacity: dark ? 0.12 : 0.08,
        shadowOpacity: dark ? 0.3 : 0.1,
        cardRadius: 22,
        dialogRadius: 28,
        controlHeight: 44,
      ),
      AppPlatformLayout.desktop => GlassPlatformStyle(
        layout: AppPlatformLayout.desktop,
        blurSigma: 22,
        surfaceOpacity: dark ? 0.56 : 0.36,
        elevatedOpacity: dark ? 0.66 : 0.46,
        floatingOpacity: dark ? 0.7 : 0.4,
        borderOpacity: dark ? 0.14 : 0.1,
        shadowOpacity: dark ? 0.28 : 0.12,
        cardRadius: 22,
        dialogRadius: 28,
        controlHeight: 44,
      ),
    };
  }

  double opacityFor(GlassSurfaceLevel level) => switch (level) {
    GlassSurfaceLevel.subtle => surfaceOpacity * 0.7,
    GlassSurfaceLevel.standard => surfaceOpacity,
    GlassSurfaceLevel.elevated => elevatedOpacity,
    GlassSurfaceLevel.floating => floatingOpacity,
  };
}
