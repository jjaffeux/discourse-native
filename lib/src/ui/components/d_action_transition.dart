import 'package:flutter/widgets.dart';

import '../foundation/material_theme.dart';

/// Animates a contextual action around the button's center.
/// Standard appearance fades and scales; glass scales without isolating its
/// live backdrop in an opacity layer.
///
/// Pass `null` to remove the action. Give different actions different keys;
/// updates to the same widget type and key preserve its state without replaying
/// the entrance. The initial action appears immediately. Reduced motion also
/// makes subsequent changes immediate.
///
/// Outgoing actions cannot receive input, focus, or accessibility actions.
/// Standard actions leave in 160 milliseconds. Glass actions leave in the first
/// 96 milliseconds before their replacement grows, avoiding stacked lenses.
/// Incoming actions settle in 240 milliseconds. Layout reserves the largest
/// child's size during a transition;
/// the caller can constrain the slot to keep adjacent controls stationary.
class DActionTransition extends StatelessWidget {
  const DActionTransition({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child ?? const SizedBox.shrink();
    }
    final glass = DMaterialTheme.glassOf(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: Duration(milliseconds: glass ? 96 : 160),
      // Let the old glass leave before the new lens reads the same slot.
      switchInCurve: glass
          ? const Interval(.4, 1, curve: Curves.easeOutCubic)
          : Curves.easeOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: glass ? _glassTransition : _transition,
      layoutBuilder: _layout,
      child: child,
    );
  }

  static Widget _glassTransition(Widget child, Animation<double> animation) =>
      _transition(child, animation, glass: true);

  static Widget _transition(
    Widget child,
    Animation<double> animation, {
    bool glass = false,
  }) {
    final scaled = ScaleTransition(
      alignment: Alignment.center,
      scale: Tween<double>(begin: glass ? 0 : .72, end: 1).animate(animation),
      child: child,
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, visual) => IgnorePointer(
        ignoring: animation.value == 0,
        child: ExcludeFocus(
          excluding: animation.value == 0,
          // Skip a zero-size lens entirely; fractional opacity would make
          // it read an empty layer instead of the dock behind the button.
          child: glass
              ? Opacity(opacity: animation.value > 0 ? 1 : 0, child: visual!)
              : visual!,
        ),
      ),
      child: glass ? scaled : FadeTransition(opacity: animation, child: scaled),
    );
  }

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
