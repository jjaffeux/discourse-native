import 'package:flutter/foundation.dart' show immutable;

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
