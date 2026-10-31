import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import 'composer/presentation.dart';
import 'platform.dart';
import 'shell_scope.dart';

/// Places reader controls in the trailing corner above the shell's dock.
class TopicCornerControls extends StatelessWidget {
  const TopicCornerControls({
    super.key,
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  static double heightOf(BuildContext context) => DControlStyle.scaledHeight(
    context.isTouch ? DButtonSize.floating : DButtonSize.chip,
    context.isTouch
        ? DReferenceTextScale.scalerOf(context)
        : MediaQuery.textScalerOf(context),
    context: context,
  );

  static double bottomClearanceOf(BuildContext context, double height) =>
      (ShellScope.read(context).mobileNavigationEnabled
          ? math.max(
              DScrollChrome.bottomInsetOf(context),
              DMobileDockGeometry.of(context).footerExtent +
                  ComposerDock.parkedDraftRoomOf(context),
            )
          : 0) +
      height +
      DSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final mobile = ShellScope.read(context).mobileNavigationEnabled;
    return ValueListenableBuilder<double>(
      valueListenable: mobile
          ? DScrollChrome.maybeOf(context) ??
                const AlwaysStoppedAnimation<double>(0)
          : const AlwaysStoppedAnimation<double>(0),
      builder: (context, hiddenFraction, child) {
        final geometry = DMobileDockGeometry.of(context);
        final dock = mobile
            ? geometry.footerExtent + ComposerDock.parkedDraftRoomOf(context)
            : 0.0;
        final folded = dock > 0 && hiddenFraction >= .5;
        final corner = geometry.cornerAt(height);
        final foldedBottom =
            geometry.cornerAt(geometry.circle) + (geometry.circle - height) / 2;
        return AnimatedPositionedDirectional(
          start: folded ? 2 * DSpacing.sm - corner : DSpacing.sm,
          end: folded ? corner : DSpacing.sm,
          bottom: folded ? foldedBottom : DSpacing.sm + dock,
          duration: DMotion.duration(
            context,
            const Duration(milliseconds: 420),
          ),
          curve: const Cubic(.32, .72, 0, 1),
          child: Align(alignment: AlignmentDirectional.bottomEnd, child: child),
        );
      },
      child: child,
    );
  }
}
