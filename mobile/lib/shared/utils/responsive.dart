import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class Responsive {
  Responsive._();

  static const double tabletBreakpoint = 768;
  static const double readerMaxWidth = 680;
  static const double desktopContentMaxWidth = 1180;
  static const double sidePanelWidth = 320;
  static const double settingsPanelWidth = 380;

  static bool isDesktopPlatform() =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      isDesktopPlatform() && MediaQuery.sizeOf(context).width >= 640;

  static bool usesWideLayout(BuildContext context) =>
      isTablet(context) || isDesktop(context);

  static int bookshelfColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (isDesktop(context) && width >= 1280) {
      return 6;
    }
    if (width >= 1024) {
      return 5;
    }
    if (width >= tabletBreakpoint) {
      return 4;
    }
    return 3;
  }
}
