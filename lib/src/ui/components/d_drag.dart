import 'package:flutter/material.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';

/// A draggable action with the same focus and touch targets as Native buttons.
///
/// Only the handle starts a drag; its surrounding content remains selectable
/// and scrollable. Supply a tap action for an accessible, non-drag alternative.
/// Use [DDropIndicator] at the destination for feedback during the drag.
/// Data should be an immutable snapshot validated again by the drop recipient.
class DDragHandle<T extends Object> extends StatefulWidget {
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
  State<DDragHandle<T>> createState() => _DDragHandleState<T>();
}

class _DDragHandleState<T extends Object> extends State<DDragHandle<T>> {
  int? _pressedPointer;
  bool _dragging = false;

  void _release() {
    if (mounted && _pressedPointer != null) {
      setState(() => _pressedPointer = null);
    }
  }

  void _finishDrag() {
    // A source may scroll out of view before its drag avatar is released.
    if (mounted) {
      setState(() {
        _dragging = false;
        _pressedPointer = null;
      });
    }
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final button = DButton.iconOnly(
      tooltip: widget.label,
      semanticLabel: '${widget.label}. Drag to move or activate for actions.',
      variant: DButtonVariant.transparentBackground,
      focusNode: widget.focusNode,
      mouseCursor: _pressedPointer != null || _dragging
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab,
      hasPopup: widget.onPressed != null,
      expanded: widget.expanded,
      onPressed: widget.enabled ? widget.onPressed : null,
      icon: const Icon(Icons.drag_indicator),
    );
    return Listener(
      onPointerDown: (event) {
        if (widget.enabled && _pressedPointer == null) {
          setState(() => _pressedPointer = event.pointer);
        }
      },
      onPointerUp: (event) {
        if (event.pointer == _pressedPointer) _release();
      },
      onPointerCancel: (event) {
        if (event.pointer == _pressedPointer) _release();
      },
      child: Draggable<T>(
        data: widget.data,
        maxSimultaneousDrags: widget.enabled ? 1 : 0,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        // Keep the fist over text and outside the source, even if it unmounts.
        // The transparent region lets hit testing reach the drop target below.
        ignoringFeedbackPointer: false,
        feedback: const MouseRegion(
          cursor: SystemMouseCursors.grabbing,
          opaque: false,
          child: SizedBox(width: 1, height: 1),
        ),
        onDragStarted: () {
          setState(() => _dragging = true);
          widget.onDragStarted?.call();
        },
        onDragCompleted: _finishDrag,
        onDraggableCanceled: (_, _) => _finishDrag(),
        child: button,
      ),
    );
  }
}

/// A passive, themed tint over the original bounds of the content being moved.
/// It never intercepts editing, scrolling, or drop targets beneath it.
class DDragHighlight extends StatelessWidget {
  const DDragHighlight({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DTokens.of(context).foreground.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(DTokens.of(context).radius),
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
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
