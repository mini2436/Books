import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/shared/theme/glass_theme.dart';
import 'package:private_reader_mobile/shared/theme/reader_theme_extension.dart';
import 'package:private_reader_mobile/shared/utils/responsive.dart';
import 'package:private_reader_mobile/shared/widgets/glass_surface.dart';

void main() {
  testWidgets('Windows floating glass remains translucent', (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      late GlassPlatformStyle style;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [AppReaderPalette.resolve(ReaderThemeMode.paper)],
          ),
          home: Builder(
            builder: (context) {
              style = GlassPlatformStyle.of(context);
              return const Scaffold(
                body: GlassSurface(
                  level: GlassSurfaceLevel.floating,
                  child: SizedBox(width: 240, height: 80),
                ),
              );
            },
          ),
        ),
      );

      expect(style.layout, AppPlatformLayout.desktop);
      expect(style.blurSigma, 22);
      expect(style.opacityFor(GlassSurfaceLevel.floating), 0.4);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).gradient != null,
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('liquid material affects surfaces unless explicitly disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppReaderPalette.resolve(ReaderThemeMode.paper),
            const GlassMaterialTheme(mode: GlassMaterialMode.liquid),
          ],
        ),
        home: const Scaffold(
          body: Column(
            children: [
              GlassSurface(
                enableLiquidGlass: false,
                child: SizedBox(width: 240, height: 80),
              ),
              GlassSurface(child: SizedBox(width: 240, height: 80)),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('liquid-glass-highlight')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsNWidgets(2));
  });

  testWidgets('opted-in surfaces keep lightweight fallback by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [AppReaderPalette.resolve(ReaderThemeMode.paper)],
        ),
        home: const Scaffold(
          body: GlassSurface(
            enableLiquidGlass: true,
            child: SizedBox(width: 240, height: 80),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('liquid-glass-highlight')), findsNothing);
  });

  testWidgets('liquid material preserves a custom semantic border', (
    tester,
  ) async {
    const semanticBorder = Color(0xFFB3261E);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppReaderPalette.resolve(ReaderThemeMode.paper),
            const GlassMaterialTheme(mode: GlassMaterialMode.liquid),
          ],
        ),
        home: Scaffold(
          body: GlassSurface(
            border: Border.all(color: semanticBorder, width: 1.5),
            child: const SizedBox(width: 240, height: 80),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate((widget) {
        if (widget case DecoratedBox(
          decoration: final BoxDecoration decoration,
        )) {
          return decoration.border is Border &&
              (decoration.border! as Border).top.color == semanticBorder;
        }
        return false;
      }),
      findsOneWidget,
    );
  });
}
