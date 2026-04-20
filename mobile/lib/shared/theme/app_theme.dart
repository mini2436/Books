import 'package:flutter/material.dart';

import '../../features/settings/reader_preferences_controller.dart';
import 'reader_theme_extension.dart';

class AppTheme {
  AppTheme._();

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
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.background,
      textTheme: textTheme.apply(
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
      extensions: [palette],
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
        fillColor: palette.backgroundSoft,
        labelStyle: TextStyle(color: palette.inkSecondary),
        hintStyle: TextStyle(color: palette.inkTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.line),
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
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.inkSecondary,
          minimumSize: const Size.fromHeight(44),
          side: BorderSide(color: palette.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.panel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return palette.accent.withValues(alpha: 0.18);
            }
            return palette.backgroundSoft;
          }),
          foregroundColor: WidgetStatePropertyAll(palette.ink),
          side: WidgetStatePropertyAll(BorderSide(color: palette.line)),
        ),
      ),
    );
  }
}
