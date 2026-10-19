import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Supplemental link navigation. Ordinary primary activation stays with the
/// nested Native control.
enum DLinkActivation { shiftedPrimary, middle, shiftedMiddle }

/// Adds modified link navigation to a Native control without another focus or
/// semantic target. The first actionable Item, Button, or Badge consumes the
/// Shift-primary action; its nested controls retain their own actions.
///
/// Middle-click uses the child's existing hit region and cancels on a drag.
/// Navigation destinations and whether Shift selects another panel stay with
/// the caller. No target padding, visual surface, or hover state is added.
class DLinkInteraction extends StatelessWidget {
  const DLinkInteraction({
    super.key,
    required this.onActivate,
    required this.child,
    this.shiftPrimaryEnabled = true,
  });

  final ValueChanged<DLinkActivation> onActivate;
  final bool shiftPrimaryEnabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => _LinkInteractionScope(
    onActivate: onActivate,
    shiftPrimaryEnabled: shiftPrimaryEnabled,
    child: GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      excludeFromSemantics: true,
      onTertiaryTapUp: (_) => onActivate(
        HardwareKeyboard.instance.isShiftPressed
            ? DLinkActivation.shiftedMiddle
            : DLinkActivation.middle,
      ),
      child: child,
    ),
  );
}

/// Kit-internal integration for an existing Native activation owner.
/// It preserves null callbacks and blocks the consumed scope below that owner.
final class DLinkInteractionBinding {
  const DLinkInteractionBinding._(this.onPressed, this._consumed);

  factory DLinkInteractionBinding.capture(
    BuildContext context,
    VoidCallback? onPressed,
  ) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_LinkInteractionScope>();
    if (onPressed == null || scope == null || scope.onActivate == null) {
      return DLinkInteractionBinding._(onPressed, false);
    }
    return DLinkInteractionBinding._(() {
      if (scope.shiftPrimaryEnabled &&
          HardwareKeyboard.instance.isShiftPressed) {
        scope.onActivate!(DLinkActivation.shiftedPrimary);
      } else {
        onPressed();
      }
    }, true);
  }

  final VoidCallback? onPressed;
  final bool _consumed;

  Widget wrap(Widget child) => _consumed
      ? _LinkInteractionScope(
          onActivate: null,
          shiftPrimaryEnabled: false,
          child: child,
        )
      : child;
}

class _LinkInteractionScope extends InheritedWidget {
  const _LinkInteractionScope({
    required this.onActivate,
    required this.shiftPrimaryEnabled,
    required super.child,
  });

  final ValueChanged<DLinkActivation>? onActivate;
  final bool shiftPrimaryEnabled;

  @override
  bool updateShouldNotify(_LinkInteractionScope oldWidget) =>
      oldWidget.onActivate != onActivate ||
      oldWidget.shiftPrimaryEnabled != shiftPrimaryEnabled;
}
