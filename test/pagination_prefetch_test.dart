import 'package:discourse_native/src/utils/pagination.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefetch distance accommodates both small and tall viewports', () {
    double distance(double height) => paginationPrefetchDistance(
      FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10000,
        pixels: 0,
        viewportDimension: height,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      ),
    );
    expect(distance(400), 1600);
    expect(distance(1200), 2400);
  });

  test('flings fetch ahead with bounded, directional headroom', () {
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 10000,
      pixels: 4000,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    expect(paginationPrefetchDistance(metrics, velocity: 4000), 3000);
    expect(paginationPrefetchDistance(metrics, velocity: 10000), 4800);
    expect(paginationPrefetchDistance(metrics, velocity: -10000), 1600);
    expect(paginationPrefetchDistance(metrics, velocity: double.nan), 1600);
  });
}
