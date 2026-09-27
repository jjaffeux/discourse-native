import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';

/// Filled uses a capsule track and a bar thumb with the same interactions.
enum DSliderVariant { standard, filled, ramp }

enum DSliderRampPattern { none, checkerboard, wave }

/// A visual value ramp. The Slider owns its 26px capsule, ring, disabled and
/// focus states. Gradients run from minimum to maximum, including RTL/vertical.
@immutable
class DSliderRamp {
  const DSliderRamp({
    this.startColor,
    this.endColor,
    this.pattern = DSliderRampPattern.none,
  });
  final Color? startColor;
  final Color? endColor;
  final DSliderRampPattern pattern;
}

/// Pointer collision policy for ordered thumbs. Keyboard movement always stops
/// at neighbours to preserve each independently focused thumb's bounds.
enum DSliderThumbCollisionBehavior {
  push,
  swap,
  none;

  /// Compatibility spelling for [none].
  static const stop = none;
}

/// A controlled, single-value base-nova slider. A null callback disables input.
///
/// [step] is relative to [min]; null allows continuous pointer input with a
/// keyboard increment of one hundredth of the range. Values may be off-step
/// (for example a live playback position); user input snaps to the step grid.
/// The caller owns [focusNode]. Standard visuals use a 4px track and 12px thumb;
/// [DSliderVariant.filled] uses a 40px capsule.
/// [DSliderVariant.ramp] uses a 26px track. Interaction follows the visible
/// track and thumb extent on every platform.
class DSlider extends StatelessWidget {
  const DSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.largeStep,
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangeCancel,
    this.orientation = Axis.horizontal,
    this.variant = DSliderVariant.standard,
    this.ramp = const DSliderRamp(),
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticFormatterCallback,
    this.secondaryTrackValue,
  });

  final double value;
  final double min;
  final double max;
  final double? step;

  /// Absolute Page/Shift+arrow increment; defaults to 10 units.
  final double? largeStep;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;

  /// Called after the next parent frame with the accepted controlled value.
  /// Rejected proposals therefore commit the unchanged value. Configuration
  /// changes or removal cancel pending commits. This is a native interaction
  /// completion hook, unlike Base UI onValueCommitted (accepted changes only).
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onChangeCancel;
  final Axis orientation;
  final DSliderVariant variant;
  final DSliderRamp ramp;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final String Function(double)? semanticFormatterCallback;

  /// Optional buffered position, painted below the active range in muted primary.
  final double? secondaryTrackValue;

  @override
  Widget build(BuildContext context) => DMultiSlider(
    values: [value],
    min: min,
    max: max,
    step: step,
    largeStep: largeStep,
    onChanged: onChanged == null ? null : (values) => onChanged!(values.single),
    onChangeStart: onChangeStart == null
        ? null
        : (values) => onChangeStart!(values.single),
    onChangeEnd: onChangeEnd == null
        ? null
        : (values) => onChangeEnd!(values.single),
    onChangeCancel: onChangeCancel,
    orientation: orientation,
    variant: variant,
    ramp: ramp,
    focusNodes: focusNode == null ? null : [focusNode!],
    autofocus: autofocus,
    semanticLabels: [semanticLabel ?? 'Value'],
    semanticFormatter: semanticFormatterCallback == null
        ? null
        : (value, _) => semanticFormatterCallback!(value),
    secondaryTrackValue: secondaryTrackValue,
  );
}

/// A controlled slider with any positive number of ordered thumbs.
///
/// Pointer input pushes neighbours by default, matching Base UI. Set
/// [thumbCollisionBehavior] can instead swap or stop at neighbours. Labels and
/// focus nodes describe sorted slots. On an accepted swap, focus follows the
/// dragged value to its new slot; rejected proposals never move focus. Equal
/// values are allowed; a track press selects the nearest thumb, preferring the
/// last focused thumb on ties. At a shared position, drag direction selects the
/// outer thumb so both ends can be separated. Tab reaches each thumb separately.
/// Horizontal values increase toward the logical end; vertical values increase
/// upward. Borrowed [focusNodes] must be distinct and remain caller-owned.
class DMultiSlider extends StatefulWidget {
  DMultiSlider({
    super.key,
    required List<double> values,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.largeStep,
    this.minStepsBetweenValues = 0,
    this.thumbCollisionBehavior = DSliderThumbCollisionBehavior.push,
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangeCancel,
    this.orientation = Axis.horizontal,
    this.variant = DSliderVariant.standard,
    this.ramp = const DSliderRamp(),
    this.focusNodes,
    this.autofocus = false,
    this.semanticLabels,
    this.semanticFormatter,
    this.secondaryTrackValue,
  }) : values = List.unmodifiable(values) {
    if (!min.isFinite ||
        !max.isFinite ||
        min > max ||
        values.isEmpty ||
        (step != null && (!step!.isFinite || step! <= 0)) ||
        (largeStep != null && (!largeStep!.isFinite || largeStep! <= 0)) ||
        minStepsBetweenValues < 0 ||
        (step == null && minStepsBetweenValues != 0)) {
      throw ArgumentError('Invalid slider bounds, steps or empty values.');
    }
    for (var i = 0; i < values.length; i++) {
      if (!values[i].isFinite ||
          values[i] < min ||
          values[i] > max ||
          (i > 0 &&
              values[i] - values[i - 1] <
                  minStepsBetweenValues * (step ?? 0) - 1e-9)) {
        throw ArgumentError(
          'Slider values must be ordered, in bounds and spaced.',
        );
      }
    }
    if (focusNodes != null &&
        (focusNodes!.length != values.length ||
            focusNodes!.toSet().length != values.length)) {
      throw ArgumentError('Supply one distinct focus node per thumb.');
    }
    if (semanticLabels != null && semanticLabels!.length != values.length) {
      throw ArgumentError('Supply one semantic label per thumb.');
    }
    if (secondaryTrackValue != null && !secondaryTrackValue!.isFinite) {
      throw ArgumentError('The buffered position must be finite.');
    }
  }

  final List<double> values;
  final double min;
  final double max;
  final double? step;

  /// Absolute Page/Shift+arrow increment; defaults to 10 units.
  final double? largeStep;
  final int minStepsBetweenValues;
  final DSliderThumbCollisionBehavior thumbCollisionBehavior;
  final ValueChanged<List<double>>? onChanged;
  final ValueChanged<List<double>>? onChangeStart;

  /// Reports accepted parent values after its next frame, never a rejected
  /// proposal. A configuration change or removal cancels a pending commit.
  /// Unlike Base UI onValueCommitted, this also completes unchanged interactions.
  final ValueChanged<List<double>>? onChangeEnd;
  final VoidCallback? onChangeCancel;
  final Axis orientation;
  final DSliderVariant variant;
  final DSliderRamp ramp;
  final List<FocusNode>? focusNodes;
  final bool autofocus;
  final List<String>? semanticLabels;
  final String Function(double value, int thumbIndex)? semanticFormatter;
  final double? secondaryTrackValue;

  @override
  State<DMultiSlider> createState() => _DMultiSliderState();
}

class _DMultiSliderState extends State<DMultiSlider> {
  final List<FocusNode> _ownedNodes = [];
  int _lastThumb = 0;
  int? _active;
  int? _pointer;
  int _configuration = 0;
  ({List<double> before, int source, int target})? _pendingSwap;
  double? _pressValue;
  List<int> _overlapping = [];
  bool get _enabled => widget.onChanged != null && widget.max > widget.min;
  bool get _vertical => widget.orientation == Axis.vertical;
  bool get _reverse =>
      _vertical || Directionality.of(context) == TextDirection.rtl;
  List<double> get _values => widget.values;
  FocusNode _node(int i) => widget.focusNodes?[i] ?? _ownedNodes[i];
  double get _increment => widget.step ?? (widget.max - widget.min) / 100;

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  void _syncNodes() {
    while (_ownedNodes.length < widget.values.length) {
      _ownedNodes.add(
        FocusNode(debugLabel: 'Slider thumb ${_ownedNodes.length + 1}'),
      );
    }
  }

  @override
  void didUpdateWidget(DMultiSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNodes();
    if (!_enabled ||
        oldWidget.values.length != widget.values.length ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.step != widget.step ||
        oldWidget.minStepsBetweenValues != widget.minStepsBetweenValues ||
        oldWidget.thumbCollisionBehavior != widget.thumbCollisionBehavior ||
        !listEquals(oldWidget.focusNodes, widget.focusNodes) ||
        oldWidget.orientation != widget.orientation) {
      // Configuration changes invalidate capture without committing stale input.
      _pendingSwap = null;
      _configuration++;
      final wasActive = _active != null;
      _active = null;
      _pointer = null;
      if (wasActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onChangeCancel?.call();
        });
      }
    }
    _reconcileSwap();
    _lastThumb = _lastThumb.clamp(0, widget.values.length - 1);
  }

  @override
  void dispose() {
    _active = null;
    _pointer = null;
    for (final node in _ownedNodes) {
      node.dispose();
    }
    super.dispose();
  }

  double _fraction(double value) => widget.max == widget.min
      ? 0
      : (value - widget.min) / (widget.max - widget.min);
  double _position(double value, double extent) {
    final f = _fraction(value);
    if (widget.variant == DSliderVariant.ramp) {
      final inset = math.min(13.0, extent / 2);
      return ((_reverse ? 1 - f : f) * extent).clamp(inset, extent - inset);
    }
    return 6 + (_reverse ? 1 - f : f) * math.max(0, extent - 12);
  }

  double _valueAt(Offset point, double extent) {
    if (widget.variant == DSliderVariant.ramp) {
      final f = ((_vertical ? point.dy : point.dx) / math.max(1, extent)).clamp(
        0.0,
        1.0,
      );
      return widget.min + (_reverse ? 1 - f : f) * (widget.max - widget.min);
    }
    final f =
        (((_vertical ? point.dy : point.dx) - 6) / math.max(1, extent - 12))
            .clamp(0.0, 1.0);
    return widget.min + (_reverse ? 1 - f : f) * (widget.max - widget.min);
  }

  double _constrain(double value, int index) {
    final gap = widget.minStepsBetweenValues * (widget.step ?? 0);
    final low = index == 0 ? widget.min : _values[index - 1] + gap;
    final high = index == _values.length - 1
        ? widget.max
        : _values[index + 1] - gap;
    if (widget.step case final step?) {
      value = widget.min + ((value - widget.min) / step).round() * step;
      // Remove arithmetic noise from decimal steps before domain callbacks.
      value = double.parse(value.toStringAsPrecision(15));
    }
    return value.clamp(low, high);
  }

  void _change(int index, double value) {
    final next = List<double>.of(_values);
    if (widget.thumbCollisionBehavior == DSliderThumbCollisionBehavior.stop) {
      next[index] = _constrain(value, index);
    } else if (widget.thumbCollisionBehavior ==
        DSliderThumbCollisionBehavior.swap) {
      final proposal = _swapProposal(index, value);
      next.setAll(0, proposal.values);
      _pendingSwap = (before: _values, source: index, target: proposal.index);
    } else {
      final gap = widget.minStepsBetweenValues * (widget.step ?? 0);
      if (widget.step case final step?) {
        value = double.parse(
          (widget.min + ((value - widget.min) / step).round() * step)
              .toStringAsPrecision(15),
        );
      }
      next[index] = value.clamp(
        widget.min + index * gap,
        widget.max - (next.length - index - 1) * gap,
      );
      for (var i = index - 1; i >= 0; i--) {
        next[i] = math.min(next[i], next[i + 1] - gap);
      }
      for (var i = index + 1; i < next.length; i++) {
        next[i] = math.max(next[i], next[i - 1] + gap);
      }
    }
    if (listEquals(next, _values)) {
      _pendingSwap = null;
      return;
    }
    widget.onChanged?.call(List.unmodifiable(next));
  }

  ({List<double> values, int index}) _swapProposal(int index, double value) {
    final remaining = List<double>.of(_values)..removeAt(index);
    final gap = widget.minStepsBetweenValues * (widget.step ?? 0);
    if (widget.step case final step?) {
      value = double.parse(
        (widget.min + ((value - widget.min) / step).round() * step)
            .toStringAsPrecision(15),
      );
    }
    // Choose the nearest legal insertion interval. Unlike push, swapping never
    // changes the other thumbs, including when minimum spacing leaves a gap.
    var selected = index;
    var selectedValue = _values[index];
    var distance = double.infinity;
    for (var slot = 0; slot <= remaining.length; slot++) {
      final low = slot == 0 ? widget.min : remaining[slot - 1] + gap;
      final high = slot == remaining.length
          ? widget.max
          : remaining[slot] - gap;
      if (low > high) continue;
      final candidate = value.clamp(low, high);
      final difference = (candidate - value).abs();
      if (difference < distance || (difference == distance && slot == index)) {
        selected = slot;
        selectedValue = candidate;
        distance = difference;
      }
    }
    remaining.insert(selected, selectedValue);
    return (values: remaining, index: selected);
  }

  void _reconcileSwap() {
    final pending = _pendingSwap;
    _pendingSwap = null;
    if (pending == null || listEquals(pending.before, _values)) return;
    final untouched = List<double>.of(pending.before)..removeAt(pending.source);
    final candidates = <int>[];
    for (var i = 0; i < _values.length; i++) {
      final remaining = List<double>.of(_values)..removeAt(i);
      if (listEquals(remaining, untouched)) candidates.add(i);
    }
    // A parent changing several values at once supplies no thumb identity.
    // Keep the current sorted slot rather than guessing from proximity.
    if (candidates.isEmpty) return;
    final accepted = candidates.contains(pending.target)
        ? pending.target
        : candidates.first;
    final retainFocus = _node(pending.source).hasFocus;
    if (_active != null) _active = accepted;
    _lastThumb = accepted;
    if (retainFocus) _node(accepted).requestFocus();
  }

  void _start(Offset point, double extent) {
    if (!_enabled || _active != null) return;
    final value = _valueAt(point, extent);
    var nearest = _lastThumb;
    for (var i = 0; i < widget.values.length; i++) {
      if ((widget.values[i] - value).abs() <
          (widget.values[nearest] - value).abs()) {
        nearest = i;
      }
    }
    _overlapping = [
      for (var i = 0; i < widget.values.length; i++)
        if ((widget.values[i] - widget.values[nearest]).abs() < 1e-9) i,
    ];
    _pressValue = widget.values[nearest];
    setState(() {
      _active = nearest;
    });
    _lastThumb = nearest;
    _node(nearest).requestFocus();
    widget.onChangeStart?.call(List.unmodifiable(widget.values));
    if (mounted && _enabled) _move(point, extent);
  }

  void _move(Offset point, double extent) {
    if (!_enabled || _active == null) return;
    final value = _valueAt(point, extent);
    if (_overlapping.length > 1 &&
        (value - _pressValue!).abs() > _increment / 2) {
      _active = value > _pressValue! ? _overlapping.last : _overlapping.first;
      _lastThumb = _active!;
      _node(_active!).requestFocus();
      _overlapping = [];
    }
    _change(_active!, value);
  }

  void _finish({bool cancel = false}) {
    if (!mounted || _active == null) return;
    setState(() {
      _active = null;
      _pointer = null;
    });
    if (cancel) {
      _pendingSwap = null;
      widget.onChangeCancel?.call();
    } else {
      _commitAccepted();
    }
  }

  void _discrete(int index, double value) {
    widget.onChangeStart?.call(List.unmodifiable(widget.values));
    if (!mounted || !_enabled) return;
    final next = List<double>.of(widget.values);
    next[index] = _constrain(value, index);
    if (!listEquals(next, widget.values)) {
      widget.onChanged?.call(List.unmodifiable(next));
    }
    if (mounted) _commitAccepted();
  }

  // Wait for the controlled parent to accept, clamp or reject the proposal.
  void _commitAccepted() {
    final configuration = _configuration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _enabled && configuration == _configuration) {
        widget.onChangeEnd?.call(List.unmodifiable(widget.values));
      }
    });
    // A rejected proposal or an endpoint key may not rebuild the parent.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _key(int index, KeyEvent event) {
    if (!_enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final large = widget.largeStep ?? 10;
    final delta = HardwareKeyboard.instance.isShiftPressed ? large : _increment;
    double? value;
    if (key == LogicalKeyboardKey.home) value = widget.min;
    if (key == LogicalKeyboardKey.end) value = widget.max;
    if (key == LogicalKeyboardKey.pageUp) value = _values[index] + large;
    if (key == LogicalKeyboardKey.pageDown) value = _values[index] - large;
    if (key == LogicalKeyboardKey.arrowUp) value = _values[index] + delta;
    if (key == LogicalKeyboardKey.arrowDown) value = _values[index] - delta;
    if (key == LogicalKeyboardKey.arrowRight) {
      value = _values[index] + (!_vertical && _reverse ? -delta : delta);
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      value = _values[index] - (!_vertical && _reverse ? -delta : delta);
    }
    if (key == LogicalKeyboardKey.escape && _active != null) {
      _finish(cancel: true);
      return KeyEventResult.handled;
    }
    if (value == null) return KeyEventResult.ignored;
    _discrete(index, value);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final crossExtent = switch (widget.variant) {
      DSliderVariant.standard => 12.0,
      DSliderVariant.filled => 40.0,
      DSliderVariant.ramp => 26.0,
    };
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final extent = _vertical
                ? (constraints.hasBoundedHeight ? constraints.maxHeight : 160.0)
                : (constraints.hasBoundedWidth ? constraints.maxWidth : 200.0);
            final size = _vertical
                ? Size(crossExtent, extent)
                : Size(extent, crossExtent);
            String format(double value, int i) =>
                widget.semanticFormatter?.call(value, i) ??
                double.parse(value.toStringAsFixed(6)).toString();
            return SizedBox.fromSize(
              size: size,
              child: MouseRegion(
                cursor: _enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: RawGestureDetector(
                  gestures: _enabled
                      ? {
                          EagerGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                EagerGestureRecognizer
                              >(EagerGestureRecognizer.new, (_) {}),
                        }
                      : {},
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      if (!_enabled ||
                          _pointer != null ||
                          event.buttons != kPrimaryButton) {
                        return;
                      }
                      _pointer = event.pointer;
                      _start(event.localPosition, extent);
                    },
                    onPointerMove: (event) {
                      if (event.pointer == _pointer) {
                        _move(event.localPosition, extent);
                      }
                    },
                    onPointerUp: (event) {
                      if (event.pointer != _pointer) return;
                      _pointer = null;
                      _finish();
                    },
                    onPointerCancel: (event) {
                      if (event.pointer != _pointer) return;
                      _pointer = null;
                      _finish(cancel: true);
                    },
                    child: Opacity(
                      opacity: _enabled ? 1 : 0.5,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: widget.variant == DSliderVariant.ramp
                                  ? _RampTrack(
                                      ramp: widget.ramp,
                                      tokens: tokens,
                                      vertical: _vertical,
                                      reverse: _reverse,
                                      fraction: _fraction(_values.last),
                                    )
                                  : _SliderTrack(
                                      vertical: _vertical,
                                      filled:
                                          widget.variant ==
                                          DSliderVariant.filled,
                                      start: _values.length == 1
                                          ? (_reverse ? extent : 0)
                                          : _position(_values.first, extent),
                                      end: _position(_values.last, extent),
                                      buffered:
                                          widget.secondaryTrackValue == null
                                          ? null
                                          : _position(
                                              widget.secondaryTrackValue!.clamp(
                                                widget.min,
                                                widget.max,
                                              ),
                                              extent,
                                            ),
                                      origin: _reverse ? extent : 0,
                                      muted: tokens.muted,
                                      primary: tokens.primary,
                                    ),
                            ),
                          ),
                          for (var i = 0; i < _values.length; i++)
                            Positioned(
                              left: _vertical
                                  ? 0
                                  : (_position(_values[i], extent) -
                                            crossExtent / 2)
                                        .clamp(
                                          0,
                                          math.max(0, extent - crossExtent),
                                        ),
                              top: _vertical
                                  ? (_position(_values[i], extent) -
                                            crossExtent / 2)
                                        .clamp(
                                          0,
                                          math.max(0, extent - crossExtent),
                                        )
                                  : 0,
                              width: _vertical
                                  ? crossExtent
                                  : math.min(crossExtent, extent),
                              height: _vertical
                                  ? math.min(crossExtent, extent)
                                  : crossExtent,
                              child: Semantics(
                                container: true,
                                sortKey: OrdinalSortKey(i.toDouble()),
                                slider: true,
                                enabled: _enabled,
                                label:
                                    widget.semanticLabels?[i] ??
                                    'Value ${i + 1}',
                                value: format(_values[i], i),
                                increasedValue: format(
                                  _constrain(_values[i] + _increment, i),
                                  i,
                                ),
                                decreasedValue: format(
                                  _constrain(_values[i] - _increment, i),
                                  i,
                                ),
                                onIncrease: _enabled
                                    ? () =>
                                          _discrete(i, _values[i] + _increment)
                                    : null,
                                onDecrease: _enabled
                                    ? () =>
                                          _discrete(i, _values[i] - _increment)
                                    : null,
                                child: FocusTraversalOrder(
                                  order: NumericFocusOrder(i.toDouble()),
                                  child: Focus(
                                    focusNode: _node(i),
                                    autofocus: widget.autofocus && i == 0,
                                    canRequestFocus: _enabled,
                                    skipTraversal: !_enabled,
                                    onKeyEvent: (_, event) => _key(i, event),
                                    onFocusChange: (focused) {
                                      if (focused) _lastThumb = i;
                                    },
                                    child: _SliderThumb(
                                      crossExtent: crossExtent,
                                      node: _node(i),
                                      active: _active == i,
                                      enabled: _enabled,
                                      vertical: _vertical,
                                      filled:
                                          widget.variant ==
                                          DSliderVariant.filled,
                                      ramp:
                                          widget.variant == DSliderVariant.ramp,
                                      offset:
                                          _position(_values[i], extent) -
                                          (_position(_values[i], extent) -
                                                  crossExtent / 2)
                                              .clamp(
                                                0,
                                                math.max(
                                                  0,
                                                  extent - crossExtent,
                                                ),
                                              ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SliderThumb extends StatefulWidget {
  const _SliderThumb({
    required this.node,
    required this.crossExtent,
    required this.active,
    required this.enabled,
    required this.vertical,
    required this.offset,
    required this.filled,
    required this.ramp,
  });
  final FocusNode node;
  final double crossExtent;
  final bool active;
  final bool enabled;
  final bool vertical;
  final double offset;
  final bool filled;
  final bool ramp;
  @override
  State<_SliderThumb> createState() => _SliderThumbState();
}

class _SliderThumbState extends State<_SliderThumb> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final ring = DTokens.of(context).focusRing;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ListenableBuilder(
        listenable: widget.node,
        builder: (context, _) {
          final highlighted =
              widget.enabled &&
              (_hover ||
                  widget.active ||
                  (widget.node.hasFocus &&
                      FocusManager.instance.highlightMode ==
                          FocusHighlightMode.traditional));
          final width = widget.ramp
              ? 18.0
              : widget.filled
              ? (widget.vertical ? 24.0 : 6.0)
              : 12.0;
          final height = widget.ramp
              ? 18.0
              : widget.filled
              ? (widget.vertical ? 6.0 : 24.0)
              : 12.0;
          final offset = widget.filled
              ? widget.offset.clamp(5.0, widget.crossExtent - 5)
              : widget.offset;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: widget.vertical
                    ? (widget.crossExtent - width) / 2
                    : offset - width / 2,
                top: widget.vertical
                    ? offset - height / 2
                    : (widget.crossExtent - height) / 2,
                child: AnimatedContainer(
                  duration: DMotion.duration(
                    context,
                    const Duration(milliseconds: 150),
                  ),
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    // base-nova explicitly uses bg-white in both color modes.
                    color: widget.ramp ? Colors.transparent : Colors.white,
                    border: Border.all(
                      color: widget.ramp
                          ? DTokens.of(context).foreground
                          : ring,
                      width: widget.ramp ? 2 : 1,
                    ),
                    boxShadow: highlighted
                        ? [
                            BoxShadow(
                              color: ring.withValues(alpha: 0.5),
                              spreadRadius: 3,
                            ),
                          ]
                        : [],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RampTrack extends CustomPainter {
  const _RampTrack({
    required this.ramp,
    required this.tokens,
    required this.vertical,
    required this.reverse,
    required this.fraction,
  });
  final DSliderRamp ramp;
  final DTokens tokens;
  final bool vertical, reverse;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = vertical
        ? Rect.fromLTWH((size.width - 26) / 2, 0, 26, size.height)
        : Rect.fromLTWH(0, (size.height - 26) / 2, size.width, 26);
    final shape = RRect.fromRectAndRadius(
      rect.deflate(.5),
      const Radius.circular(999),
    );
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(rect, Paint()..color = tokens.background);
    if (ramp.pattern == DSliderRampPattern.checkerboard) {
      final paint = Paint()..color = tokens.foreground.withValues(alpha: .16);
      for (var x = 0.0; x < rect.width; x += 4) {
        for (var y = 0.0; y < rect.height; y += 4) {
          if (((x / 4).floor() + (y / 4).floor()).isEven) {
            canvas.drawRect(
              Rect.fromLTWH(rect.left + x, rect.top + y, 4, 4),
              paint,
            );
          }
        }
      }
    }
    var begin = vertical ? Alignment.bottomCenter : Alignment.centerLeft;
    var end = vertical ? Alignment.topCenter : Alignment.centerRight;
    // Vertical sliders already increase upward. Only horizontal RTL reverses.
    if (!vertical && reverse) {
      final temp = begin;
      begin = end;
      end = temp;
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: [
            ramp.startColor ?? tokens.muted,
            ramp.endColor ?? ramp.startColor ?? tokens.muted,
          ],
        ).createShader(rect),
    );
    if (ramp.pattern == DSliderRampPattern.wave) {
      final path = Path();
      for (var i = 0; i <= 260; i++) {
        final t = i / 260;
        final phase = 2 * math.pi * (1.1 * t + 10.4 * t * t / 2);
        final wave = math.sin(phase) * (.7 + 8.3 * math.pow(t, 1.5));
        final pos = reverse ? 1 - t : t;
        final p = vertical
            ? Offset(rect.center.dx + wave, rect.top + pos * rect.height)
            : Offset(rect.left + pos * rect.width, rect.center.dy - wave);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Color.lerp(tokens.background, tokens.foreground, .4)!;
      canvas.drawPath(path, paint);
      final reached = vertical
          ? Rect.fromLTRB(
              rect.left,
              rect.bottom - fraction * rect.height,
              rect.right,
              rect.bottom,
            )
          : reverse
          ? Rect.fromLTRB(
              rect.right - fraction * rect.width,
              rect.top,
              rect.right,
              rect.bottom,
            )
          : Rect.fromLTRB(
              rect.left,
              rect.top,
              rect.left + fraction * rect.width,
              rect.bottom,
            );
      canvas.clipRect(reached);
      canvas.drawPath(path, paint..color = tokens.primary);
    }
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = tokens.border,
    );
  }

  @override
  bool shouldRepaint(_RampTrack oldDelegate) =>
      ramp != oldDelegate.ramp ||
      tokens != oldDelegate.tokens ||
      vertical != oldDelegate.vertical ||
      reverse != oldDelegate.reverse ||
      fraction != oldDelegate.fraction;
}

class _SliderTrack extends CustomPainter {
  _SliderTrack({
    required this.vertical,
    required this.start,
    required this.end,
    required this.origin,
    required this.buffered,
    required this.muted,
    required this.primary,
    required this.filled,
  });
  final bool filled;
  final bool vertical;
  final double start, end, origin;
  final double? buffered;
  final Color muted, primary;
  @override
  void paint(Canvas canvas, Size size) {
    final crossExtent = vertical ? size.width : size.height;
    final breadth = filled ? 40.0 : 4.0;
    final inset = (crossExtent - breadth) / 2;
    final rect = vertical
        ? Rect.fromLTWH(inset, 0, breadth, size.height)
        : Rect.fromLTWH(0, inset, size.width, breadth);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(999)));
    canvas.drawRect(rect, Paint()..color = muted);
    void segment(double a, double b, Color color) {
      canvas.drawRect(
        vertical
            ? Rect.fromLTRB(
                inset,
                math.min(a, b),
                crossExtent - inset,
                math.max(a, b),
              )
            : Rect.fromLTRB(
                math.min(a, b),
                inset,
                math.max(a, b),
                crossExtent - inset,
              ),
        Paint()..color = color,
      );
    }

    if (buffered case final buffer?) {
      segment(origin, buffer, primary.withValues(alpha: 0.35));
    }
    segment(start, end, primary);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SliderTrack oldDelegate) =>
      filled != oldDelegate.filled ||
      vertical != oldDelegate.vertical ||
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      origin != oldDelegate.origin ||
      buffered != oldDelegate.buffered ||
      muted != oldDelegate.muted ||
      primary != oldDelegate.primary;
}

/// Form-owned single value with ordinary validation, save and reset semantics.
/// Use [value] for external updates; omit it to let the field own its value.
/// Reset proposes the initialValue captured at mount through onChanged. A
/// controlled parent may accept or reject it; save/validation retain the
/// accepted value until the parent rebuilds. Re-key to change the reset baseline.
class DSliderField extends FormField<double> {
  DSliderField({
    super.key,
    double initialValue = 0,
    this.value,
    double min = 0,
    double max = 100,
    double? step = 1,
    double? largeStep,
    String? semanticLabel,
    this.onChanged,
    super.enabled,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
  }) : resetValue = initialValue,
       super(
         initialValue: value ?? initialValue,
         builder: (field) => Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           mainAxisSize: MainAxisSize.min,
           children: [
             DSlider(
               value: field.value!,
               min: min,
               max: max,
               step: step,
               largeStep: largeStep,
               semanticLabel: semanticLabel,
               onChanged: field.widget.enabled
                   ? (value) {
                       field.didChange(
                         (field.widget as DSliderField).value ?? value,
                       );
                       onChanged?.call(value);
                     }
                   : null,
             ),
             if (field.errorText case final error?)
               Semantics(
                 liveRegion: true,
                 child: Text(
                   error,
                   style: TextStyle(
                     color: DTokens.of(field.context).destructive,
                   ),
                 ),
               ),
           ],
         ),
       );
  final double? value;
  final double resetValue;
  final ValueChanged<double>? onChanged;
  @override
  FormFieldState<double> createState() => _DSliderFieldState();
}

class _DSliderFieldState extends FormFieldState<double> {
  late final double _resetValue;

  @override
  void initState() {
    super.initState();
    // Freeze the mounted reset baseline before subsequent parent rebuilds.
    _resetValue = (widget as DSliderField).resetValue;
  }

  @override
  void reset() {
    super.reset();
    final current = widget as DSliderField;
    if (current.value == null) setValue(_resetValue);
    current.onChanged?.call(_resetValue);
  }

  @override
  void didUpdateWidget(covariant DSliderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget as DSliderField;
    if (current.value != null && current.value != value) {
      setValue(current.value);
    }
  }
}

/// Form-owned ordered values for range and multiple-thumb input.
/// Reset proposes a frozen copy of the mounted initialValue through onChanged;
/// controlled values remain authoritative until the parent accepts the proposal.
class DMultiSliderField extends FormField<List<double>> {
  DMultiSliderField({
    super.key,
    required List<double> initialValue,
    this.values,
    double min = 0,
    double max = 100,
    double? step = 1,
    double? largeStep,
    DSliderThumbCollisionBehavior thumbCollisionBehavior =
        DSliderThumbCollisionBehavior.push,
    int minStepsBetweenValues = 0,
    List<String>? semanticLabels,
    this.onChanged,
    super.enabled,
    super.onSaved,
    super.validator,
    super.autovalidateMode,
  }) : resetValues = List.unmodifiable(initialValue),
       super(
         initialValue: List.unmodifiable(values ?? initialValue),
         builder: (field) => Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           mainAxisSize: MainAxisSize.min,
           children: [
             DMultiSlider(
               values: field.value!,
               min: min,
               max: max,
               step: step,
               largeStep: largeStep,
               thumbCollisionBehavior: thumbCollisionBehavior,
               minStepsBetweenValues: minStepsBetweenValues,
               semanticLabels: semanticLabels,
               onChanged: field.widget.enabled
                   ? (values) {
                       field.didChange(
                         (field.widget as DMultiSliderField).values ?? values,
                       );
                       onChanged?.call(values);
                     }
                   : null,
             ),
             if (field.errorText case final error?)
               Semantics(
                 liveRegion: true,
                 child: Text(
                   error,
                   style: TextStyle(
                     color: DTokens.of(field.context).destructive,
                   ),
                 ),
               ),
           ],
         ),
       );
  final List<double>? values;
  final List<double> resetValues;
  final ValueChanged<List<double>>? onChanged;
  @override
  FormFieldState<List<double>> createState() => _DMultiSliderFieldState();
}

class _DMultiSliderFieldState extends FormFieldState<List<double>> {
  late final List<double> _resetValues;

  @override
  void initState() {
    super.initState();
    _resetValues = (widget as DMultiSliderField).resetValues;
  }

  @override
  void reset() {
    super.reset();
    final current = widget as DMultiSliderField;
    if (current.values == null) setValue(_resetValues);
    current.onChanged?.call(_resetValues);
  }

  @override
  void didUpdateWidget(covariant DMultiSliderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget as DMultiSliderField;
    if (current.values != null && !listEquals(current.values, value)) {
      setValue(List.unmodifiable(current.values!));
    }
  }
}
