import 'dart:io';

String? bundledFontAssetDirectoryPath() {
  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  return '$executableDirectory${Platform.pathSeparator}data'
      '${Platform.pathSeparator}flutter_assets'
      '${Platform.pathSeparator}assets'
      '${Platform.pathSeparator}fonts';
}
