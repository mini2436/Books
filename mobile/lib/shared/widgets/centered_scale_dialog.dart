import 'dart:ui';

import 'package:flutter/material.dart';

Future<T?> showCenteredScaleDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, _, _) => builder(dialogContext),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return AnimatedBuilder(
        animation: curved,
        child: child,
        builder: (context, dialog) => Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 6 * curved.value,
                sigmaY: 6 * curved.value,
              ),
              child: const SizedBox.expand(),
            ),
            FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
                alignment: Alignment.center,
                child: dialog,
              ),
            ),
          ],
        ),
      );
    },
  );
}
