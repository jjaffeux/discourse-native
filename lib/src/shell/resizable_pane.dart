import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/frame_safe_notifier.dart';
import '../theme/app_theme.dart';

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
    required this.maximumWidth,
    this.readWidth,
    this.writeWidth,
  }) : assert(minimumWidth.isFinite),
       assert(maximumWidth.isFinite),
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
enum ResizablePaneEdge {
  leading,
  trailing;

  double widthDeltaForDrag(double horizontalDelta, TextDirection direction) {
    final logicalDelta = direction == TextDirection.ltr
        ? horizontalDelta
        : -horizontalDelta;
    return this == ResizablePaneEdge.trailing ? logicalDelta : -logicalDelta;
  }
}

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
    this.handleWidth = 16,
    this.keyboardStep = 16,
    this.dividerWidth = 0,
    this.focusedDividerWidth = 3,
  }) : assert(!maximumWidth.isNaN),
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
  final double handleWidth;
  final double keyboardStep;
  final double dividerWidth;
  final double focusedDividerWidth;

  @override
  State<ResizablePane> createState() => _ResizablePaneState();
}

class _ResizablePaneState extends State<ResizablePane> {
  late final FocusNode _focus = FocusNode(
    debugLabel: '${widget.resizeKey} resize',
  );
  bool _focused = false;
  bool _keyboardResizePending = false;
  double? _renderedWidth;

  @override
  void didUpdateWidget(ResizablePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      unawaited(oldWidget.controller.flush());
      _keyboardResizePending = false;
    }
  }

  @override
  void dispose() {
    unawaited(widget.controller.flush());
    _focus.dispose();
    super.dispose();
  }

  void _resizeBy(double widthDelta) {
    widget.controller.resizeBy(widthDelta, maximum: widget.maximumWidth);
  }

  void _startDrag(DragStartDetails _) {
    _focus.requestFocus();
  }

  void _updateDrag(DragUpdateDetails details) {
    final renderedWidth = _renderedWidth;
    if (renderedWidth == null) return;
    final widthDelta = widget.edge.widthDeltaForDrag(
      details.delta.dx,
      Directionality.of(context),
    );
    // Multiple pointer updates can arrive before a frame. Anchoring each one
    // to rendered geometry keeps undisplayed threshold movement from becoming
    // part of the pane's persisted width.
    final targetWidth = renderedWidth + widthDelta;
    final currentWidth = widget.controller.effectiveWidth(
      maximum: widget.maximumWidth,
    );
    _resizeBy(targetWidth - currentWidth);
  }

  void _endDrag() {
    unawaited(widget.controller.flush());
    _focus.unfocus();
  }

  void _resizeOnce(double widthDelta) {
    _resizeBy(widthDelta);
    unawaited(widget.controller.flush());
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    final horizontalDelta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -widget.keyboardStep,
      LogicalKeyboardKey.arrowRight => widget.keyboardStep,
      _ => null,
    };
    if (horizontalDelta == null) return KeyEventResult.ignored;

    final isPress = event is KeyDownEvent || event is KeyRepeatEvent;
    final keyboard = HardwareKeyboard.instance;
    if (isPress &&
        (keyboard.isAltPressed ||
            keyboard.isControlPressed ||
            keyboard.isMetaPressed ||
            keyboard.isShiftPressed)) {
      _focus.unfocus();
      return KeyEventResult.ignored;
    }

    if (isPress) {
      final widthDelta = widget.edge.widthDeltaForDrag(
        horizontalDelta,
        Directionality.of(context),
      );
      _resizeBy(widthDelta);
      _keyboardResizePending = true;
    } else if (event is KeyUpEvent && _keyboardResizePending) {
      _keyboardResizePending = false;
      unawaited(widget.controller.flush());
    }
    return KeyEventResult.handled;
  }

  void _focusChanged(bool focused) {
    if (_focused == focused) return;
    if (!focused && _keyboardResizePending) {
      _keyboardResizePending = false;
      unawaited(widget.controller.flush());
    }
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.controller,
      child: widget.child,
      builder: (context, _, child) {
        final width = widget.controller.effectiveWidth(
          maximum: widget.maximumWidth,
        );
        _renderedWidth = width;
        final increasedWidth = widget.controller.resizedWidth(
          widget.keyboardStep,
          maximum: widget.maximumWidth,
        );
        final decreasedWidth = widget.controller.resizedWidth(
          -widget.keyboardStep,
          maximum: widget.maximumWidth,
        );
        final canIncrease = increasedWidth != width;
        final canDecrease = decreasedWidth != width;

        return SizedBox(
          width: width,
          child: Stack(
            children: [
              Positioned.fill(child: child!),
              PositionedDirectional(
                start: widget.edge == ResizablePaneEdge.leading ? 0 : null,
                end: widget.edge == ResizablePaneEdge.trailing ? 0 : null,
                top: 0,
                bottom: 0,
                width: widget.handleWidth,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Focus(
                    key: ValueKey('${widget.resizeKey}-resize-focus'),
                    focusNode: _focus,
                    onFocusChange: _focusChanged,
                    onKeyEvent: _handleKey,
                    child: Semantics(
                      key: ValueKey('${widget.resizeKey}-resize-semantics'),
                      container: true,
                      focusable: true,
                      focused: _focused,
                      slider: true,
                      label: widget.semanticsLabel,
                      value: '${width.round()} pixels wide',
                      increasedValue: canIncrease
                          ? '${increasedWidth.round()} pixels wide'
                          : null,
                      decreasedValue: canDecrease
                          ? '${decreasedWidth.round()} pixels wide'
                          : null,
                      onIncrease: canIncrease
                          ? () => _resizeOnce(widget.keyboardStep)
                          : null,
                      onDecrease: canDecrease
                          ? () => _resizeOnce(-widget.keyboardStep)
                          : null,
                      child: GestureDetector(
                        key: ValueKey('${widget.resizeKey}-resize-handle'),
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: _startDrag,
                        onHorizontalDragUpdate: _updateDrag,
                        onHorizontalDragEnd: (_) => _endDrag(),
                        onHorizontalDragCancel: _endDrag,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (widget.dividerWidth > 0)
                              Align(
                                alignment:
                                    widget.edge == ResizablePaneEdge.leading
                                    ? AlignmentDirectional.centerStart
                                    : AlignmentDirectional.centerEnd,
                                child: ColoredBox(
                                  color: _focused
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).shell.divider,
                                  child: SizedBox(
                                    width: _focused
                                        ? widget.focusedDividerWidth
                                        : widget.dividerWidth,
                                    height: double.infinity,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
