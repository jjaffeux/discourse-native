import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

enum DHeaderSettle { direction, halfway, stay }

/// Scroll header tuning. Values match the final native mockup.
@immutable
class DHeaderTuning {
  const DHeaderTuning({
    this.settle = DHeaderSettle.direction,
    this.point = .5,
    this.pause = 120,
    this.slack = 40,
    this.hold = 400,
    this.smoothing = 40,
  });

  final DHeaderSettle settle;
  final double point;
  final int pause;
  final double slack;
  final int hold;
  final int smoothing;

  DHeaderTuning copyWith({
    DHeaderSettle? settle,
    double? point,
    int? pause,
    double? slack,
    int? hold,
    int? smoothing,
  }) => DHeaderTuning(
    settle: settle ?? this.settle,
    point: point ?? this.point,
    pause: pause ?? this.pause,
    slack: slack ?? this.slack,
    hold: hold ?? this.hold,
    smoothing: smoothing ?? this.smoothing,
  );

  Map<String, Object> toJson() => {
    'settle': settle.name,
    'point': point,
    'pause': pause,
    'slack': slack,
    'hold': hold,
    'smoothing': smoothing,
  };

  factory DHeaderTuning.fromJson(Map<String, dynamic> json) {
    T pick<T>(String key, List<T> options, T fallback) =>
        options.where((value) => value == json[key]).firstOrNull ?? fallback;
    return DHeaderTuning(
      settle:
          DHeaderSettle.values
              .where((v) => v.name == json['settle'])
              .firstOrNull ??
          DHeaderSettle.direction,
      point: pick('point', [.3, .4, .5, .6, .7], .5),
      pause: pick('pause', [80, 120, 180, 250], 120),
      slack: pick('slack', [0.0, 24.0, 40.0, 64.0], 40.0),
      hold: pick('hold', [0, 250, 400, 600, 800], 400),
      smoothing: pick('smoothing', [0, 25, 40, 60, 90], 40),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DHeaderTuning &&
      other.settle == settle &&
      other.point == point &&
      other.pause == pause &&
      other.slack == slack &&
      other.hold == hold &&
      other.smoothing == smoothing;
  @override
  int get hashCode => Object.hash(settle, point, pause, slack, hold, smoothing);
}

class DHeaderMotionSettings extends InheritedWidget {
  const DHeaderMotionSettings({
    super.key,
    required this.tuning,
    required super.child,
  });
  final DHeaderTuning tuning;
  static DHeaderTuning of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DHeaderMotionSettings>()
          ?.tuning ??
      const DHeaderTuning();
  @override
  bool updateShouldNotify(DHeaderMotionSettings oldWidget) =>
      tuning != oldWidget.tuning;
}

/// One frame loop and continuous progress for all of a panel's chrome.
/// Scroll packets only move the target; a reversal never starts an animation.
class HeaderMotion extends ChangeNotifier implements ValueListenable<double> {
  HeaderMotion(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }
  late final Ticker _ticker;
  DHeaderTuning tuning = const DHeaderTuning();
  bool reducedMotion = false;
  double _value = 0;
  @override
  double get value => _value;
  double target = 0;
  int _direction = 0;
  int _way = 0;
  double _slack = 0;
  Timer? _settleTimer;
  Timer? _holdTimer;
  bool _held = false;
  Duration? _last;

  void reset() {
    _ticker.stop();
    target = 0;
    _direction = 0;
    _way = 0;
    _slack = 0;
    _settleTimer?.cancel();
    _settleTimer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _held = false;
    _last = null;
    _show(0, hold: false);
  }

  void reveal({bool fresh = false}) {
    target = 0;
    if (fresh) {
      _direction = 0;
      _slack = 0;
      _way = 0;
    }
    _settleTimer?.cancel();
    _settleTimer = null;
    _wake();
  }

  void configure(DHeaderTuning value, {required bool disableAnimations}) {
    tuning = value;
    reducedMotion = disableAnimations;
    if (reducedMotion) _show(target);
  }

  void scroll(double delta, {required double span}) {
    if (delta == 0 || !delta.isFinite || span <= 0) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(
      Duration(milliseconds: tuning.pause, microseconds: 1),
      () {
        _settleTimer = null;
        _settle();
      },
    );
    final dir = delta > 0 ? 1 : -1;
    if (dir != _direction) {
      _slack = _direction == 0 ? 0 : tuning.slack;
      _direction = dir;
    }
    if (_held && ((target == 1 && dir < 0) || (target == 0 && dir > 0))) {
      _slack = tuning.slack;
      _wake();
      return;
    }
    var use = delta.abs();
    final eat = math.min(_slack, use);
    _slack -= eat;
    use -= eat;
    if (use > 0) {
      _way = dir;
      target = (target + dir * use / span).clamp(0.0, 1.0);
    }
    _wake();
  }

  void _wake() {
    if (reducedMotion || tuning.smoothing == 0) _show(target);
    if (value == target && _settleTimer == null) return;
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  void _settle() {
    if (target > 0 && target < 1) {
      target = switch (tuning.settle) {
        DHeaderSettle.stay => target,
        DHeaderSettle.halfway => target >= tuning.point ? 1 : 0,
        DHeaderSettle.direction =>
          _way > 0 ? (target > .1 ? 1 : 0) : (target < .9 ? 0 : 1),
      };
    }
    _wake();
  }

  void _tick(Duration elapsed) {
    final dt = math.min(
      64.0,
      (elapsed - (_last ?? elapsed)).inMicroseconds / 1000,
    );
    _last = elapsed;
    if (value != target) {
      var next = reducedMotion || tuning.smoothing == 0
          ? target
          : target + (value - target) * math.exp(-dt / tuning.smoothing);
      if ((next - target).abs() < .002) next = target;
      _show(next);
    }
    if (_settleTimer == null && value == target) {
      _ticker.stop();
      _last = null;
    }
  }

  void _show(double next, {bool hold = true}) {
    if (_value == next) return;
    _value = next;
    if (hold && (next == 0 || next == 1)) {
      _holdTimer?.cancel();
      _held = tuning.hold > 0;
      if (_held) {
        _holdTimer = Timer(
          Duration(milliseconds: tuning.hold),
          () => _held = false,
        );
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _holdTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }
}
