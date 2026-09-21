import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';

/// A draggable action with the same focus and touch targets as Native buttons.
///
/// Only the handle starts a drag; its surrounding content remains selectable
/// and scrollable. Supply a tap action for an accessible, non-drag alternative.
/// Use [DDropIndicator] at the destination for feedback during the drag.
/// Data should be an immutable snapshot validated again by the drop recipient.
class DDragHandle<T extends Object> extends StatelessWidget {
  const DDragHandle({
    super.key,
    required this.data,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.focusNode,
    this.expanded = false,
    this.onDragStarted,
    this.onDragEnd,
  });

  final T data;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final FocusNode? focusNode;
  final bool expanded;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final button = DButton.iconOnly(
      tooltip: label,
      semanticLabel: '$label. Drag to move or activate for actions.',
      variant: DButtonVariant.transparentBackground,
      focusNode: focusNode,
      hasPopup: onPressed != null,
      expanded: expanded,
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.drag_indicator),
    );
    return Draggable<T>(
      data: data,
      maxSimultaneousDrags: enabled ? 1 : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: const SizedBox.shrink(),
      onDragStarted: onDragStarted,
      // These callbacks also run when a scrolling source handle unmounts.
      onDragCompleted: onDragEnd,
      onDraggableCanceled: (_, _) => onDragEnd?.call(),
      child: button,
    );
  }
}

/// Receives typed drags without intercepting ordinary text or scroll gestures.
/// Positions are global, allowing a caller to use its own document geometry.
class DDragRegion<T extends Object> extends StatelessWidget {
  const DDragRegion({
    super.key,
    required this.child,
    required this.accepts,
    required this.onMove,
    required this.onDrop,
    required this.onLeave,
  });

  final Widget child;
  final bool Function(T data) accepts;
  final void Function(T data, Offset position) onMove;
  final void Function(T data, Offset position) onDrop;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => DragTarget<T>(
    onWillAcceptWithDetails: (details) => accepts(details.data),
    onMove: (details) => onMove(details.data, details.offset),
    onAcceptWithDetails: (details) => onDrop(details.data, details.offset),
    onLeave: (_) => onLeave(),
    builder: (context, candidates, rejected) => child,
  );
}

/// A non-interactive insertion boundary. Pair with a button for tap-to-place.
class DDropIndicator extends StatelessWidget {
  const DDropIndicator({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: SizedBox(
        height: 2,
        child: ColoredBox(color: DTokens.of(context).primary),
      ),
    ),
  );
}
