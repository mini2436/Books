import 'package:flutter/widgets.dart';

class Responsive {
  Responsive._();

  static const double tabletBreakpoint = 768;
  static const double readerMaxWidth = 680;
  static const double sidePanelWidth = 320;
  static const double settingsPanelWidth = 380;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  static int bookshelfColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1024) {
      return 5;
    }
    if (width >= tabletBreakpoint) {
      return 4;
    }
    return 3;
  }
}
