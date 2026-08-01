import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/features/reader/reader_screen.dart';
import 'package:private_reader_mobile/features/settings/reader_preferences_controller.dart';

void main() {
  test('manual reading uses horizontal pagination on phones', () {
    expect(
      readerUsesPagedMode(wideReader: false, autoScrollEnabled: false),
      isTrue,
    );
  });

  test('phone auto reading switches to continuous scrolling', () {
    expect(
      readerUsesPagedMode(wideReader: false, autoScrollEnabled: true),
      isFalse,
    );
  });

  test('wide readers remain paged while auto scrolling is requested', () {
    expect(
      readerUsesPagedMode(wideReader: true, autoScrollEnabled: true),
      isTrue,
    );
  });

  test('initialization overlay remains visible until loading completes', () {
    expect(readerShowsInitializationOverlay(isLoading: true), isTrue);
    expect(readerShowsInitializationOverlay(isLoading: false), isFalse);
  });

  test('reader column preference only enables two columns on wide screens', () {
    expect(
      readerUsesDualColumn(
        wideReader: true,
        columnLayout: ReaderColumnLayout.double,
      ),
      isTrue,
    );
    expect(
      readerUsesDualColumn(
        wideReader: true,
        columnLayout: ReaderColumnLayout.single,
      ),
      isFalse,
    );
    expect(
      readerUsesDualColumn(
        wideReader: false,
        columnLayout: ReaderColumnLayout.double,
      ),
      isFalse,
    );
  });
}
