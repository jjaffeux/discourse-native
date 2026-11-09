import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How far a control gives under a press, by what it is drawn as.
enum DPressDepth {
  /// A control that stays put.
  still(1),

  /// A wide settings row, which a smaller scale would move too far.
  row(.985),

  /// A control with a fill of its own.
  filled(.95),

  /// A control sitting in a well.
  inset(.94),

  /// An icon or a choice with no fill of its own.
  bare(.92);

  const DPressDepth(this.scale);

  final double scale;
}

/// Gives [child] a little while [states] holds [WidgetState.pressed], and
/// springs it back on release.
///
/// Controls mount by the dozen in scrolling rows and most are never pressed,
/// so this costs one render object at rest: its ticker is created by the first
/// press, and each frame of the motion repaints without a rebuild. The scale
/// is only painted, so layout and hit testing keep the control's resting
/// bounds, and a press that lands while it is springing back still counts.
class DPressScale extends SingleChildRenderObjectWidget {
  const DPressScale({
    super.key,
    required this.states,
    required this.depth,
    required super.child,
  });

  final ValueListenable<Set<WidgetState>> states;
  final DPressDepth depth;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderDPressScale(
    states,
    depth,
    reduceMotion: MediaQuery.disableAnimationsOf(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDPressScale renderObject,
  ) {
    renderObject
      ..states = states
      ..pressDepth = depth
      ..reduceMotion = MediaQuery.disableAnimationsOf(context);
  }
}

const _pressIn = Duration(milliseconds: 80);
const _release = Duration(milliseconds: 400);
const _spring = Cubic(.34, 1.56, .64, 1);

class RenderDPressScale extends RenderProxyBox {
  RenderDPressScale(
    this._states,
    this.pressDepth, {
    required this.reduceMotion,
  });

  ValueListenable<Set<WidgetState>> _states;
  DPressDepth pressDepth;
  bool reduceMotion;

  bool _pressed = false;
  double _scale = 1;
  Ticker? _ticker;

  /// The motion in flight, or null while the control rests or is held down.
  ({double from, double to, Duration duration})? _leg;

  set states(ValueListenable<Set<WidgetState>> value) {
    if (identical(_states, value)) return;
    if (attached) {
      _states.removeListener(_follow);
      value.addListener(_follow);
    }
    _states = value;
  }

  // Listening rather than reading a build: under a scrollable a tap's down and
  // up arrive together, and a build would only ever see it already released.
  void _follow() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed == _pressed) return;
    _pressed = pressed;
    if (pressed) {
      _run(pressDepth.scale, _pressIn);
    } else if (_leg?.duration != _pressIn) {
      _run(1, _release);
    }
  }

  void _run(double to, Duration duration) {
    if (reduceMotion) {
      _ticker?.stop();
      _leg = null;
      _show(to);
      return;
    }
    if (_leg == null && _scale == to) return;
    final ticker = _ticker ??= Ticker(_tick, debugLabel: 'DPressScale');
    _leg = (from: _scale, to: to, duration: duration);
    ticker
      ..stop()
      ..start();
  }

  void _tick(Duration elapsed) {
    final leg = _leg!;
    final t = math.min(
      1.0,
      elapsed.inMicroseconds / leg.duration.inMicroseconds,
    );
    _show(lerpDouble(leg.from, leg.to, _spring.transform(t))!);
    if (t < 1) return;
    _ticker!.stop();
    _leg = null;
    if (!_pressed) _run(1, _release);
  }

  void _show(double scale) {
    if (_scale == scale) return;
    _scale = scale;
    markNeedsPaint();
  }

  Matrix4 get _transform {
    final centre = size.center(Offset.zero);
    return Matrix4.translationValues(centre.dx, centre.dy, 0)
      ..scaleByDouble(_scale, _scale, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _states.addListener(_follow);
  }

  @override
  void detach() {
    _states.removeListener(_follow);
    _ticker?.dispose();
    _ticker = null;
    _leg = null;
    _pressed = false;
    _scale = 1;
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_scale == 1) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer as TransformLayer?,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_scale != 1) transform.multiply(_transform);
  }
}
