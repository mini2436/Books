import 'package:flutter_test/flutter_test.dart';
import 'package:private_reader_mobile/shared/utils/image_decode_size.dart';

void main() {
  group('quantizedImageDecodeWidth', () {
    test('根据逻辑宽度和 DPR 向上归并到缓存档位', () {
      expect(
        quantizedImageDecodeWidth(logicalWidth: 100, devicePixelRatio: 2),
        256,
      );
      expect(
        quantizedImageDecodeWidth(logicalWidth: 120, devicePixelRatio: 3),
        384,
      );
    });

    test('限制超大封面的解码宽度', () {
      expect(
        quantizedImageDecodeWidth(logicalWidth: 800, devicePixelRatio: 2),
        768,
      );
      expect(
        quantizedImageDecodeWidth(
          logicalWidth: 800,
          devicePixelRatio: 2,
          maximumWidth: 512,
        ),
        512,
      );
    });

    test('无效约束不指定解码宽度', () {
      expect(
        quantizedImageDecodeWidth(
          logicalWidth: double.infinity,
          devicePixelRatio: 2,
        ),
        isNull,
      );
      expect(
        quantizedImageDecodeWidth(logicalWidth: 0, devicePixelRatio: 2),
        isNull,
      );
    });
  });
}
