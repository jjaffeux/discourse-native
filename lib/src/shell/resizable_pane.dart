import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart' show DResizableHandle;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../foundation/frame_safe_notifier.dart';

typedef PanelWidthReader = Future<double?> Function();
typedef PanelWidthWriter = Future<void> Function(double width);

/// Owns a pane's preferred width independently from the widget that renders it.
///
/// A temporary layout maximum only clamps [effectiveWidth]. It does not replace
/// [value], so a preferred width returns when the window has room for it again.
final class PanelWidthController extends FrameSafeNotifier
    implements ValueListenable<double> {
  PanelWidthController({
    required double initialWidth,
    required this.minimumWidth,
    this.maximumWidth = double.infinity,
    this.readWidth,
    this.writeWidth,
  }) : assert(minimumWidth.isFinite),
       assert(!maximumWidth.isNaN),
       assert(initialWidth.isFinite),
       assert(minimumWidth <= maximumWidth),
       _value = initialWidth.clamp(minimumWidth, maximumWidth).toDouble() {
    restored = _restore();
  }

  final double minimumWidth;
  final double maximumWidth;
  final PanelWidthReader? readWidth;
  final PanelWidthWriter? writeWidth;

  late final Future<void> restored;
  double _value;
  bool _dirty = false;
  int _interactionGeneration = 0;

  @override
  double get value => _value;

  double effectiveWidth({double maximum = double.infinity}) =>
      _value.clamp(minimumWidth, _effectiveMaximum(maximum)).toDouble();

  double resizedWidth(double delta, {double maximum = double.infinity}) {
    final current = effectiveWidth(maximum: maximum);
    return (current + delta)
        .clamp(minimumWidth, _effectiveMaximum(maximum))
        .toDouble();
  }

  /// Applies a visible width change and returns whether the pane changed size.
  ///
  /// An outward drag against a temporary constraint is a no-op and therefore
  /// cannot silently replace a wider saved preference.
  bool resizeBy(double delta, {double maximum = double.infinity}) {
    if (isDisposed || !delta.isFinite || maximum.isNaN) return false;
    _interactionGeneration++;
    final current = effectiveWidth(maximum: maximum);
    final next = resizedWidth(delta, maximum: maximum);
    if (next == current) return false;

    _value = next;
    _dirty = true;
    notifySafely();
    return true;
  }

  Future<void> flush() async {
    final writer = writeWidth;
    if (!_dirty || writer == null) return;
    _dirty = false;
    await writer(_value);
  }

  Future<void> _restore() async {
    final reader = readWidth;
    if (reader == null) return;
    final generation = _interactionGeneration;
    final stored = await reader();
    if (isDisposed ||
        generation != _interactionGeneration ||
        stored == null ||
        !stored.isFinite) {
      return;
    }

    final next = stored.clamp(minimumWidth, maximumWidth).toDouble();
    if (next == _value) return;
    _value = next;
    notifySafely();
  }

  double _effectiveMaximum(double maximum) =>
      math.max(minimumWidth, math.min(maximumWidth, maximum));

  @override
  void dispose() {
    unawaited(flush());
    super.dispose();
  }
}

/// The logical edge of the pane that owns its resize handle.
enum ResizablePaneEdge { leading, trailing }

/// A width-listening pane with one logical-edge resize handle.
class ResizablePane extends StatefulWidget {
  ResizablePane({
    super.key,
    required this.controller,
    required this.edge,
    required this.resizeKey,
    required this.semanticsLabel,
    required this.child,
    this.maximumWidth = double.infinity,
    this.widthOverride,
    this.resizeEnabled = true,
    this.handleWidth = 2,
    this.keyboardStep = 16,
    this.dividerWidth = 0,
    this.gap = 0,
    this.focusedDividerWidth = 3,
  }) : assert(!maximumWidth.isNaN),
       assert(gap.isFinite && gap >= 0),
       assert(handleWidth.isFinite && handleWidth > 0),
       assert(keyboardStep.isFinite && keyboardStep > 0),
       assert(dividerWidth.isFinite && dividerWidth >= 0),
       assert(focusedDividerWidth.isFinite && focusedDividerWidth >= 0);

  final PanelWidthController controller;
  final ResizablePaneEdge edge;
  final String resizeKey;
  final String semanticsLabel;
  final Widget child;
  final double maximumWidth;

  /// A temporary layout width that leaves the controller's preference intact.
  final double? widthOverride;
  final bool resizeEnabled;

  final double handleWidth;
  final double keyboardStep;
  final double dividerWidth;

  /// Workspace space reserved inside the resizing edge.
  final double gap;
  final double focusedDividerWidth;

  @override
  State<ResizablePane> createState() => _ResizablePaneState();
}

class _ResizablePaneState extends State<ResizablePane> {
  @override
  void didUpdateWidget(ResizablePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      unawaited(oldWidget.controller.flush());
    }
  }

  @override
  void dispose() {
    unawaited(widget.controller.flush());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: widget.controller,
    child: widget.child,
    builder: (context, _, child) {
      final width =
          widget.widthOverride ??
          widget.controller.effectiveWidth(maximum: widget.maximumWidth);
      final handleExtent = widget.resizeEnabled
          ? DResizableHandle.resolveHitExtent(context, widget.handleWidth)
          : 0.0;
      return SizedBox(
        width: width,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start:
                      widget.resizeEnabled &&
                          widget.edge == ResizablePaneEdge.leading
                      ? widget.gap
                      : 0,
                  end:
                      widget.resizeEnabled &&
                          widget.edge == ResizablePaneEdge.trailing
                      ? widget.gap
                      : 0,
                ),
                child: child!,
              ),
            ),
            // The kit owns pointer, keyboard, focus and handle painting.
            if (widget.resizeEnabled)
              PositionedDirectional(
                start: widget.edge == ResizablePaneEdge.leading
                    ? (widget.gap > 0 ? (widget.gap - handleExtent) / 2 : 0)
                    : null,
                end: widget.edge == ResizablePaneEdge.trailing
                    ? (widget.gap > 0 ? (widget.gap - handleExtent) / 2 : 0)
                    : null,
                top: 0,
                bottom: 0,
                width: handleExtent,
                child: DResizableHandle.standalone(
                  // Keep every pointer delta when input outruns rendering.
                  trackUnrenderedChanges: true,
                  focusKey: ValueKey('${widget.resizeKey}-resize-focus'),
                  semanticsKey: ValueKey(
                    '${widget.resizeKey}-resize-semantics',
                  ),
                  gestureKey: ValueKey('${widget.resizeKey}-resize-handle'),
                  semanticLabel: widget.semanticsLabel,
                  value: width,
                  min: widget.controller.minimumWidth,
                  max: math.max(
                    widget.controller.minimumWidth,
                    math.min(
                      widget.controller.maximumWidth,
                      widget.maximumWidth,
                    ),
                  ),
                  reverse: widget.edge == ResizablePaneEdge.leading,
                  keyboardStep: widget.keyboardStep,
                  withHandle: widget.gap > 0,
                  dividerThickness: widget.gap > 0 ? 0 : widget.dividerWidth,
                  focusedDividerThickness: widget.focusedDividerWidth,
                  dividerAlignment: widget.gap > 0
                      ? Alignment.center
                      : widget.edge == ResizablePaneEdge.leading
                      ? AlignmentDirectional.centerStart
                      : AlignmentDirectional.centerEnd,
                  valueFormatter: (value) => '${value.round()} pixels wide',
                  onChangeStart: () {
                    // An outer-window resize may be displaying a temporary
                    // width that differs from the saved preference. Start a
                    // seam drag at the width under the pointer, including
                    // when its first update lands on the old preference.
                    final visible = widget.widthOverride;
                    if (visible == null) return;
                    final preferred = widget.controller.effectiveWidth(
                      maximum: widget.maximumWidth,
                    );
                    widget.controller.resizeBy(
                      visible - preferred,
                      maximum: widget.maximumWidth,
                    );
                  },
                  onChanged: (next) => widget.controller.resizeBy(
                    next -
                        widget.controller.effectiveWidth(
                          maximum: widget.maximumWidth,
                        ),
                    maximum: widget.maximumWidth,
                  ),
                  onChangeEnd: () => unawaited(widget.controller.flush()),
                ),
              ),
          ],
        ),
      );
    },
  );
}
