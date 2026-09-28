import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';

/// Fades and gently scales a contextual action as it appears or changes.
///
/// Pass `null` to remove the action. Give different actions different keys;
/// updates to the same widget type and key preserve its state without replaying
/// the entrance. The initial action appears immediately. Reduced motion also
/// makes subsequent changes immediate.
///
/// Outgoing actions remain visible for 120 milliseconds, but cannot receive
/// input, focus, or accessibility actions. Incoming actions settle in 180
/// milliseconds. Layout reserves the largest child's size during a transition;
/// the caller can constrain the slot to keep adjacent controls stationary.
class DActionTransition extends StatelessWidget {
  const DActionTransition({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child ?? const SizedBox.shrink();
    }
    return AnimatedSwitcher(
      duration: DMotion.change,
      reverseDuration: const Duration(milliseconds: 120),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: _transition,
      layoutBuilder: _layout,
      child: child,
    );
  }

  static Widget _transition(Widget child, Animation<double> animation) =>
      AnimatedBuilder(
        animation: animation,
        builder: (context, visual) => IgnorePointer(
          ignoring: animation.value == 0,
          child: ExcludeFocus(excluding: animation.value == 0, child: visual!),
        ),
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .92, end: 1).animate(animation),
            child: child,
          ),
        ),
      );

  static Widget _layout(Widget? current, List<Widget> previous) =>
      current == null && previous.isEmpty
      ? const SizedBox.shrink()
      : Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            for (final entry in previous) _entry(entry, active: false),
            if (current != null) _entry(current, active: true),
          ],
        );

  static Widget _entry(Widget child, {required bool active}) => TickerMode(
    key: child.key,
    enabled: active,
    child: ExcludeSemantics(
      excluding: !active,
      child: ExcludeFocus(
        excluding: !active,
        child: IgnorePointer(ignoring: !active, child: child),
      ),
    ),
  );
}
