import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';

/// Drags visible content after a touch hold, or immediately with a mouse or pen.
/// Quick touch swipes remain available to an enclosing scroll view. The child
/// supplies its semantics; provide an accessible action alongside dragging.
class DContentDrag<T extends Object> extends StatelessWidget {
  const DContentDrag({
    super.key,
    required this.data,
    required this.feedback,
    required this.child,
    this.enabled = true,
    this.onDragStarted,
    this.onDragEnd,
  });

  final T data;
  final Widget feedback;
  final Widget child;
  final bool enabled;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) => _ContentDraggable<T>(
    data: data,
    maxSimultaneousDrags: enabled ? 1 : 0,
    dragAnchorStrategy: pointerDragAnchorStrategy,
    onDragStarted: onDragStarted,
    // These callbacks also run when a successful drop unmounts the source.
    onDragCompleted: onDragEnd,
    onDraggableCanceled: (_, _) => onDragEnd?.call(),
    feedback: ExcludeSemantics(
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        child: Opacity(opacity: 0.9, child: feedback),
      ),
    ),
    childWhenDragging: MouseRegion(
      cursor: SystemMouseCursors.grabbing,
      child: Opacity(opacity: 0.35, child: child),
    ),
    child: MouseRegion(
      cursor: enabled ? SystemMouseCursors.grab : MouseCursor.defer,
      child: child,
    ),
  );
}

class _ContentDraggable<T extends Object> extends Draggable<T> {
  const _ContentDraggable({
    required super.data,
    required super.feedback,
    required super.child,
    required super.childWhenDragging,
    required super.maxSimultaneousDrags,
    required super.dragAnchorStrategy,
    required super.onDragStarted,
    required super.onDragCompleted,
    required super.onDraggableCanceled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _ContentDragRecognizer()..onStart = onStart;
}

// Choose per pointer, so touch scrolling also works on desktop and a mouse
// connected to a phone does not need to wait for the touch hold timeout.
class _ContentDragRecognizer extends DelayedMultiDragGestureRecognizer {
  _ContentDragRecognizer()
    : super(allowedButtonsFilter: (buttons) => buttons == kPrimaryButton);

  final _immediate = ImmediateMultiDragGestureRecognizer();

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return super.createNewPointerState(event);
    }
    _immediate.gestureSettings = gestureSettings;
    return _immediate.createNewPointerState(event);
  }

  @override
  void dispose() {
    _immediate.dispose();
    super.dispose();
  }
}

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
      semanticLabel: context.l10n.dragToMoveOrActivateForActions(
        (widget.label).toString(),
      ),
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

/// Long-press movement over content whose items are resolved by global position.
///
/// Returns a snapshot from [dataAt] on touch-down, or null to leave the gesture
/// to the child. Accepted long presses take priority over child text selection;
/// taps and scrolling before the long-press timeout retain their normal behavior.
/// The owner supplies source/destination feedback and validates the snapshot
/// before committing [onDrop]. All positions are global. Provide separate
/// accessible actions when adopting this gesture on otherwise passive content.
class DLongPressDragRegion<T extends Object> extends StatefulWidget {
  const DLongPressDragRegion({
    super.key,
    required this.dataAt,
    required this.onStart,
    required this.onMove,
    required this.onDrop,
    required this.onEnd,
    required this.child,
    this.enabled = true,
  });

  final T? Function(Offset position) dataAt;
  final bool Function(T data) onStart;
  final void Function(T data, Offset position) onMove;
  final void Function(T data, Offset position) onDrop;
  final VoidCallback onEnd;
  final Widget child;
  final bool enabled;

  @override
  State<DLongPressDragRegion<T>> createState() =>
      _DLongPressDragRegionState<T>();
}

class _DLongPressDragRegionState<T extends Object>
    extends State<DLongPressDragRegion<T>> {
  late final LongPressGestureRecognizer _recognizer;
  T? _data;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _recognizer = LongPressGestureRecognizer(debugOwner: this)
      ..onLongPressStart = (details) {
        final data = _data;
        if (!widget.enabled || data == null || !widget.onStart(data)) return;
        _active = true;
        unawaited(Feedback.forLongPress(context));
        widget.onMove(data, details.globalPosition);
      }
      ..onLongPressMoveUpdate = (details) {
        final data = _data;
        if (_active && widget.enabled && data != null) {
          widget.onMove(data, details.globalPosition);
        }
      }
      ..onLongPressEnd = (details) {
        final data = _data;
        if (_active && widget.enabled && data != null) {
          widget.onDrop(data, details.globalPosition);
        }
        _finish();
      }
      ..onLongPressCancel = _finish;
  }

  void _finish() {
    final active = _active;
    _active = false;
    _data = null;
    if (active) widget.onEnd();
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled ||
        _data != null ||
        event.kind != PointerDeviceKind.touch) {
      return;
    }
    final data = widget.dataAt(event.position);
    if (data == null) return;
    _data = data;
    _recognizer.addPointer(event);
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LongPressListener(onPointerDown: _down, child: widget.child);
}

// Register the block recognizer before descendant text-selection recognizers.
// Both use the platform long-press timeout; hit-test order gives block movement
// priority without shortening that timeout or intercepting taps/scroll drags.
class _LongPressListener extends SingleChildRenderObjectWidget {
  const _LongPressListener({required this.onPointerDown, required super.child});
  final PointerDownEventListener onPointerDown;

  @override
  RenderPointerListener createRenderObject(BuildContext context) =>
      _RenderLongPressListener(onPointerDown);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPointerListener renderObject,
  ) {
    renderObject.onPointerDown = onPointerDown;
  }
}

class _RenderLongPressListener extends RenderPointerListener {
  _RenderLongPressListener(PointerDownEventListener onDown)
    : super(onPointerDown: onDown);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    hitTestChildren(result, position: position);
    return true;
  }
}
