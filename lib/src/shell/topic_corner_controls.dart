import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import 'composer/presentation_scope.dart';
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
                  ComposerParkedDraftScope.roomOf(context),
            )
          : 0) +
      height +
      DSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final mobile = ShellScope.read(context).mobileNavigationEnabled;
    final chrome = mobile ? DScrollChrome.maybeOf(context) : null;
    final lifted = DMobileDockPeek.liftedOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([chrome, lifted]),
      builder: (context, child) {
        final hiddenFraction = chrome?.value ?? 0;
        final geometry = DMobileDockGeometry.of(context);
        final dock = mobile
            ? geometry.footerExtent + ComposerParkedDraftScope.roomOf(context)
            : 0.0;
        final folded = dock > 0 && hiddenFraction >= .5;
        // While the bar is lifted, as far as it lifts, so it does not cover
        // what floats just over it.
        final lift = dock > 0 && lifted.value ? geometry.peek : 0.0;
        final corner = geometry.cornerAt(height);
        final foldedBottom =
            geometry.cornerAt(geometry.circle) + (geometry.circle - height) / 2;
        return AnimatedPositionedDirectional(
          start: folded ? 2 * DSpacing.sm - corner : DSpacing.sm,
          end: folded ? corner : DSpacing.sm,
          bottom: folded ? foldedBottom : DSpacing.sm + dock + lift,
          duration: DMotion.duration(
            context,
            const Duration(milliseconds: 420),
          ),
          curve: const Cubic(.32, .72, 0, 1),
          // The controls are [height] tall at least, centred on it, so a
          // shorter row still settles on the corner it was measured for.
          child: Align(
            alignment: AlignmentDirectional.bottomEnd,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Align(widthFactor: 1, heightFactor: 1, child: child),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
