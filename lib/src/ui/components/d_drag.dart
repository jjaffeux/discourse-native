import 'package:flutter/gestures.dart' show PointerDeviceKind;
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
    this.density = DButtonDensity.standard,
    this.focusNode,
    this.expanded = false,
    this.onDragStarted,
    this.onDragEnd,
  });

  final T data;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final DButtonDensity density;
  final FocusNode? focusNode;
  final bool expanded;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  @override
  State<DDragHandle<T>> createState() => _DDragHandleState<T>();
}

class _DDragHandleState<T extends Object> extends State<DDragHandle<T>> {
  int? _pressedPointer;
  bool _pointerHasCursor = false;
  bool _dragging = false;
  OverlayEntry? _cursorOverlay;

  void _startDrag() {
    if (_pointerHasCursor) {
      // A moving feedback region trails pointer events until the next frame.
      // Cover the window so its cursor stays stable between frames, while
      // non-opaque hit testing still reaches every drop target underneath.
      _cursorOverlay = OverlayEntry(
        builder: (_) => const Positioned.fill(
          child: ExcludeSemantics(
            child: MouseRegion(
              cursor: SystemMouseCursors.grabbing,
              opaque: false,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(_cursorOverlay!);
    }
    setState(() => _dragging = true);
    widget.onDragStarted?.call();
  }

  void _release() {
    if (mounted && _pressedPointer != null) {
      setState(() => _pressedPointer = null);
    }
  }

  void _finishDrag() {
    // A source may scroll out of view before its drag avatar is released.
    // Draggable calls this even after the handle unmounts, so keep the cursor
    // overlay alive until that gesture ends rather than removing it in dispose.
    _cursorOverlay?.remove();
    _cursorOverlay?.dispose();
    _cursorOverlay = null;
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
      density: widget.density,
      semanticLabel: '${widget.label}. Drag to move or activate for actions.',
      variant: DButtonVariant.transparentBackground,
      // The source highlight owns the shared backdrop, including on hover.
      backgroundColor: Colors.transparent,
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
          _pointerHasCursor =
              event.kind == PointerDeviceKind.mouse ||
              event.kind == PointerDeviceKind.stylus;
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
        feedback: const SizedBox.shrink(),
        onDragStarted: _startDrag,
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
