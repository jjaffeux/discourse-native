import 'package:flutter/widgets.dart';

/// Reveals a contextual action with a short upward movement and scale.
///
/// Pass `null` to remove the action. Give different actions different keys;
/// updates to the same widget type and key preserve its state without replaying
/// the entrance. The initial action appears immediately. Reduced motion also
/// makes subsequent changes immediate.
///
/// Outgoing actions remain visible for 160 milliseconds, but cannot receive
/// input, focus, or accessibility actions. Incoming actions settle in 240
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
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
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
            // Grow upward within the slot so all painted bounds remain
            // available to hit testing throughout the movement.
            alignment: Alignment.bottomCenter,
            scale: Tween<double>(begin: .72, end: 1).animate(animation),
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
