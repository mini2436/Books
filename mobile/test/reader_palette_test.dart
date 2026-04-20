import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/shared/theme/reader_theme_extension.dart';

void main() {
  test('night palette keeps the warm accent for reading', () {
    final palette = AppReaderPalette.resolve(ReaderThemeMode.night);

    expect(palette.accent.toARGB32(), const Color(0xFFC3924A).toARGB32());
    expect(palette.background.toARGB32(), const Color(0xFF17171A).toARGB32());
  });
}
