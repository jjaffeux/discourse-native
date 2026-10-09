import 'package:flutter/widgets.dart';

import 'app_settings_controller.dart';

/// Applies the saved choice to the navigator, overlays and Native components.
class AppMotionRegion extends StatelessWidget {
  const AppMotionRegion({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppSettingsController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    child: child,
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
          disableAnimations: controller.reduceMotion ?? media.disableAnimations,
        ),
        child: child!,
      );
    },
  );
}
