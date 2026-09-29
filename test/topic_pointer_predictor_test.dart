import 'dart:ui';

import 'package:discourse_native/src/shell/topic_pointer_predictor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rows = {1: Rect.fromLTRB(200, 100, 600, 164)};
  late TopicPointerPredictor<int> predictor;
  setUp(() => predictor = TopicPointerPredictor<int>());
  int? sample(double x, double y, int ms, [Map<int, Rect> targets = rows]) =>
      predictor.sample(Offset(x, y), Duration(milliseconds: ms), targets);

  test('requires the same unique approach on two sampled frames', () {
    expect(sample(100, 130, 0), isNull);
    expect(sample(120, 130, 16), isNull);
    expect(sample(140, 130, 32), 1);
  });

  test('does not extrapolate beyond the 80 ms horizon', () {
    sample(0, 130, 0);
    sample(10, 130, 16);
    expect(sample(20, 130, 32), isNull);
  });

  test('rejects a vertical sweep crossing several rows', () {
    const stacked = {
      1: Rect.fromLTRB(0, 100, 600, 164),
      2: Rect.fromLTRB(0, 165, 600, 229),
      3: Rect.fromLTRB(0, 230, 600, 294),
    };
    sample(300, 0, 0, stacked);
    sample(300, 30, 16, stacked);
    expect(sample(300, 60, 32, stacked), isNull);
  });

  test('rejects overlapping targets instead of using registration order', () {
    const overlapping = {
      1: Rect.fromLTRB(200, 100, 600, 164),
      2: Rect.fromLTRB(200, 100, 600, 164),
    };
    sample(100, 130, 0, overlapping);
    sample(120, 130, 16, overlapping);
    expect(sample(140, 130, 32, overlapping), isNull);
  });

  test('actual hover is left to the existing dwell', () {
    sample(100, 130, 0);
    sample(150, 130, 16);
    expect(sample(220, 130, 32), isNull);
  });

  test('reversal discards the previous direction and confirmation', () {
    sample(100, 130, 0);
    sample(120, 130, 16);
    expect(sample(110, 130, 32), isNull);
    expect(sample(100, 130, 48), isNull);
  });

  test('pause discards old velocity and requires fresh confirmation', () {
    sample(100, 130, 0);
    sample(120, 130, 16);
    expect(sample(140, 130, 200), isNull);
    expect(sample(150, 130, 216), isNull);
    expect(sample(160, 130, 232), 1);
  });

  test('stationary or duplicate timestamps cannot predict', () {
    sample(100, 130, 0);
    sample(100, 130, 16);
    expect(sample(100, 130, 32), isNull);
    sample(120, 130, 32);
    expect(sample(140, 130, 32), isNull);
  });

  test(
    'moving away, parallel misses, and invisible targets do not predict',
    () {
      sample(180, 80, 0);
      sample(160, 80, 16);
      expect(sample(140, 80, 32), isNull);
      predictor.reset();
      sample(100, 80, 0);
      sample(120, 80, 16);
      expect(sample(140, 80, 32), isNull);
      expect(sample(160, 130, 48, {}), isNull);
    },
  );

  test('reset prevents an old confirmation surviving a scroll or resize', () {
    sample(100, 130, 0);
    sample(120, 130, 16);
    predictor.reset();
    expect(sample(140, 130, 32), isNull);
    expect(sample(150, 130, 48), isNull);
    expect(sample(160, 130, 64), 1);
  });

  test('approaches from the right and diagonally are supported', () {
    sample(700, 130, 0);
    sample(680, 130, 16);
    expect(sample(660, 130, 32), 1);
    predictor.reset();
    sample(100, 50, 0);
    sample(120, 66, 16);
    expect(sample(140, 82, 32), 1);
  });
}
