import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum AppPlatformLayout { phone, tablet, web, desktop }

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

  /// Centralized platform classification for visual systems that need
  /// independent tuning without scattering platform checks across screens.
  static AppPlatformLayout platformLayout(BuildContext context) {
    if (kIsWeb) {
      return AppPlatformLayout.web;
    }
    if (isDesktopPlatform()) {
      return AppPlatformLayout.desktop;
    }
    if (isTablet(context)) {
      return AppPlatformLayout.tablet;
    }
    return AppPlatformLayout.phone;
  }

  static int bookshelfColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1600) {
      return 10;
    }
    if (width >= 1280) {
      return 8;
    }
    if (width >= 1024) {
      return 7;
    }
    if (width >= tabletBreakpoint) {
      return 4;
    }
    return 3;
  }
}
