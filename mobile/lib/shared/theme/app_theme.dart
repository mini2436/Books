import 'package:flutter/material.dart';

import '../../features/settings/reader_preferences_controller.dart';
import 'glass_theme.dart';
import 'reader_theme_extension.dart';

class AppTheme {
  AppTheme._();

  static const _uiFontFamily = 'MiSans';
  static const _uiFontFallback = <String>[
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static ThemeData build(ReaderPreferences preferences) {
    final palette = AppReaderPalette.resolve(preferences.themeMode);
    final brightness = preferences.themeMode == ReaderThemeMode.night
        ? Brightness.dark
        : Brightness.light;
    final textTheme = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: palette.accent,
          brightness: brightness,
        ).copyWith(
          primary: palette.accent,
          secondary: palette.accent,
          surface: palette.background,
          onSurface: palette.ink,
          surfaceContainer: palette.panel.withValues(alpha: 0.62),
          surfaceContainerHigh: palette.panel.withValues(alpha: 0.72),
          surfaceContainerHighest: palette.panel.withValues(alpha: 0.82),
        );
    final glassBorder = BorderSide(
      color: brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.1)
          : palette.ink.withValues(alpha: 0.08),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: _uiFontFamily,
      fontFamilyFallback: _uiFontFallback,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      textTheme: textTheme.apply(
        fontFamily: _uiFontFamily,
        fontFamilyFallback: _uiFontFallback,
        bodyColor: palette.ink,
        displayColor: palette.ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.panel,
        foregroundColor: palette.ink,
        centerTitle: true,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: palette.line,
      cardColor: palette.panel,
      canvasColor: palette.background,
      extensions: [
        palette,
        GlassMaterialTheme(mode: preferences.glassMaterialMode),
      ],
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.panel,
        indicatorColor: palette.accent.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.panel,
        selectedIconTheme: IconThemeData(color: palette.accent),
        selectedLabelTextStyle: TextStyle(
          color: palette.accent,
          fontWeight: FontWeight.w600,
        ),
        unselectedIconTheme: IconThemeData(color: palette.inkSecondary),
        unselectedLabelTextStyle: TextStyle(color: palette.inkSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.panel.withValues(
          alpha: brightness == Brightness.dark ? 0.5 : 0.42,
        ),
        labelStyle: TextStyle(color: palette.inkSecondary),
        hintStyle: TextStyle(color: palette.inkTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: glassBorder,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: glassBorder,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.inkSecondary,
          minimumSize: const Size(64, 44),
          side: BorderSide(color: palette.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.panel.withValues(alpha: 0.68),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: glassBorder,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.panel.withValues(alpha: 0.48),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: glassBorder,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.panel.withValues(alpha: 0.76),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: glassBorder,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            palette.panel.withValues(alpha: 0.76),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(glassBorder),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            palette.panel.withValues(alpha: 0.78),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(glassBorder),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: palette.accent.withValues(alpha: 0.18),
        backgroundColor: palette.backgroundSoft,
        labelStyle: TextStyle(color: palette.ink),
        side: BorderSide(color: palette.line),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.accent.withValues(alpha: 0.18);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStatePropertyAll(palette.ink),
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),
    );
  }
}
