import 'dart:math' as math;

/// 将控件的逻辑宽度换算成图片解码宽度，并归并到少量缓存档位。
///
/// 档位化可以避免同一张图片因为布局中几像素的差异生成多份内存缓存。
int? quantizedImageDecodeWidth({
  required double logicalWidth,
  required double devicePixelRatio,
  int maximumWidth = 768,
}) {
  if (!logicalWidth.isFinite ||
      logicalWidth <= 0 ||
      !devicePixelRatio.isFinite ||
      devicePixelRatio <= 0 ||
      maximumWidth <= 0) {
    return null;
  }

  final requiredWidth = math.min(
    (logicalWidth * devicePixelRatio).ceil(),
    maximumWidth,
  );
  const buckets = [128, 256, 384, 512, 768];
  for (final bucket in buckets) {
    if (bucket >= requiredWidth) {
      return math.min(bucket, maximumWidth);
    }
  }
  return maximumWidth;
}
