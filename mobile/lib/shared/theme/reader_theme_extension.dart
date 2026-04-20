import 'package:flutter/material.dart';

enum ReaderThemeMode { paper, kraft, eyeCare, night }

class AppReaderPalette extends ThemeExtension<AppReaderPalette> {
  const AppReaderPalette({
    required this.background,
    required this.backgroundSoft,
    required this.panel,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.accent,
    required this.line,
    required this.highlight,
    required this.mask,
    required this.selection,
  });

  final Color background;
  final Color backgroundSoft;
  final Color panel;
  final Color ink;
  final Color inkSecondary;
  final Color inkTertiary;
  final Color accent;
  final Color line;
  final Color highlight;
  final Color mask;
  final Color selection;

  static const Map<ReaderThemeMode, AppReaderPalette> all = {
    ReaderThemeMode.paper: AppReaderPalette(
      background: Color(0xFFFFFFFF),
      backgroundSoft: Color(0xFFF7F7F7),
      panel: Color(0xF2FFFFFF),
      ink: Color(0xFF1A1A1A),
      inkSecondary: Color(0xFF666666),
      inkTertiary: Color(0xFF999999),
      accent: Color(0xFF7A4A24),
      line: Color(0x14000000),
      highlight: Color(0xFFFFF3CD),
      mask: Color(0x73000000),
      selection: Color(0x407A4A24),
    ),
    ReaderThemeMode.kraft: AppReaderPalette(
      background: Color(0xFFF5F0E6),
      backgroundSoft: Color(0xFFEDE8DC),
      panel: Color(0xF2F5F0E6),
      ink: Color(0xFF2C241B),
      inkSecondary: Color(0xFF5E5043),
      inkTertiary: Color(0xFF8C7D6E),
      accent: Color(0xFF7A4A24),
      line: Color(0x1A3C2814),
      highlight: Color(0xFFE8D5B5),
      mask: Color(0x73000000),
      selection: Color(0x407A4A24),
    ),
    ReaderThemeMode.eyeCare: AppReaderPalette(
      background: Color(0xFFE3EBDE),
      backgroundSoft: Color(0xFFD9E3D4),
      panel: Color(0xF2E3EBDE),
      ink: Color(0xFF233222),
      inkSecondary: Color(0xFF4A5E43),
      inkTertiary: Color(0xFF7A8F72),
      accent: Color(0xFF4A6B3F),
      line: Color(0x1A283C1E),
      highlight: Color(0xFFC8D9C0),
      mask: Color(0x73000000),
      selection: Color(0x474A6B3F),
    ),
    ReaderThemeMode.night: AppReaderPalette(
      background: Color(0xFF17171A),
      backgroundSoft: Color(0xFF1E1E22),
      panel: Color(0xF21E1E22),
      ink: Color(0xFFC8C8C8),
      inkSecondary: Color(0xFF888888),
      inkTertiary: Color(0xFF666666),
      accent: Color(0xFFC3924A),
      line: Color(0x14FFFFFF),
      highlight: Color(0xFF4A3B20),
      mask: Color(0x99000000),
      selection: Color(0x59C3924A),
    ),
  };

  static AppReaderPalette resolve(ReaderThemeMode mode) => all[mode]!;

  static AppReaderPalette of(BuildContext context) =>
      Theme.of(context).extension<AppReaderPalette>()!;

  @override
  AppReaderPalette copyWith({
    Color? background,
    Color? backgroundSoft,
    Color? panel,
    Color? ink,
    Color? inkSecondary,
    Color? inkTertiary,
    Color? accent,
    Color? line,
    Color? highlight,
    Color? mask,
    Color? selection,
  }) {
    return AppReaderPalette(
      background: background ?? this.background,
      backgroundSoft: backgroundSoft ?? this.backgroundSoft,
      panel: panel ?? this.panel,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkTertiary: inkTertiary ?? this.inkTertiary,
      accent: accent ?? this.accent,
      line: line ?? this.line,
      highlight: highlight ?? this.highlight,
      mask: mask ?? this.mask,
      selection: selection ?? this.selection,
    );
  }

  @override
  ThemeExtension<AppReaderPalette> lerp(
    covariant ThemeExtension<AppReaderPalette>? other,
    double t,
  ) {
    if (other is! AppReaderPalette) {
      return this;
    }

    return AppReaderPalette(
      background: Color.lerp(background, other.background, t)!,
      backgroundSoft: Color.lerp(backgroundSoft, other.backgroundSoft, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkTertiary: Color.lerp(inkTertiary, other.inkTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      line: Color.lerp(line, other.line, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      mask: Color.lerp(mask, other.mask, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
    );
  }
}
