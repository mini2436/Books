import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/features/reader/reader_controller.dart';

void main() {
  test(
    'initialization pool respects its limit and preserves result order',
    () async {
      var active = 0;
      var maximumActive = 0;
      final progress = <int>[];
      final items = List<int>.generate(14, (index) => index);

      final results = await runReaderInitializationPool(
        items: items,
        maxConcurrency: readerInitializationResourceConcurrency,
        operation: (item) async {
          active += 1;
          if (active > maximumActive) maximumActive = active;
          try {
            await Future<void>.delayed(Duration(milliseconds: 2 + (item % 3)));
            return item * 2;
          } finally {
            active -= 1;
          }
        },
        onProgress: (completed, _) => progress.add(completed),
      );

      expect(maximumActive, readerInitializationResourceConcurrency);
      expect(results, items.map((item) => item * 2));
      expect(progress, List<int>.generate(items.length, (index) => index + 1));
    },
  );

  test(
    'initialization pool drains in-flight work before reporting failure',
    () async {
      final release = Completer<void>();
      final failureTriggered = Completer<void>();
      final started = <int>[];
      var settled = 0;

      final result = runReaderInitializationPool(
        items: List<int>.generate(10, (index) => index),
        maxConcurrency: 3,
        operation: (item) async {
          started.add(item);
          try {
            if (item == 0) {
              await Future<void>.delayed(Duration.zero);
              failureTriggered.complete();
              throw StateError('download failed');
            }
            await release.future;
            return item;
          } finally {
            settled += 1;
          }
        },
      );

      while (started.length < 3) {
        await Future<void>.delayed(Duration.zero);
      }
      await failureTriggered.future;
      await Future<void>.delayed(Duration.zero);
      release.complete();

      await expectLater(result, throwsStateError);
      expect(started, [0, 1, 2]);
      expect(settled, 3);
    },
  );
}
