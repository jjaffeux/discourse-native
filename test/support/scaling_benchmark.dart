import 'package:flutter_test/flutter_test.dart';

/// Compares warmed, synchronous work at two input sizes, excluding setup.
///
/// Each callback returns a value derived from its result so the timed work stays
/// observable. Callers choose their own input sizes and growth bound.
/// Returns the best microseconds per iteration for each size.
({double small, double large}) measureScaling(
  int Function() small,
  int Function() large,
) {
  final measurements = [_BatchedMeasurement(small), _BatchedMeasurement(large)];

  // Calibration can include compilation. Discard it, and warm both sizes before
  // retaining samples so the larger input is not measured cold against hot code.
  for (var warmup = 0; warmup < 2; warmup += 1) {
    for (final measurement in measurements) {
      measurement.sample();
    }
  }

  final best = [double.infinity, double.infinity];
  for (var round = 0; round < 7; round += 1) {
    // Alternate order to share changes in machine load between the input sizes.
    for (final index in round.isEven ? [0, 1] : [1, 0]) {
      final cost = measurements[index].sample();
      if (cost < best[index]) best[index] = cost;
    }
  }

  final microsPerTick = Duration.microsecondsPerSecond / Stopwatch().frequency;
  final costs = (
    small: best[0] * microsPerTick,
    large: best[1] * microsPerTick,
  );
  printOnFailure(
    'Microseconds per iteration: $costs; growth: ${costs.large / costs.small}; '
    'batch sizes: ${measurements.map((m) => m.iterations).toList()}; '
    'checksums: ${measurements.map((m) => m.checksum).toList()}',
  );
  return costs;
}

class _BatchedMeasurement {
  _BatchedMeasurement(this.run);

  final int Function() run;
  int iterations = 1;
  int checksum = 0;

  double sample() {
    // Keep every retained batch above timer resolution and ordinary scheduling
    // interruptions. Recalibrate after JIT speedups, with no iteration cap that
    // could allow a zero or microsecond-scale baseline through.
    final minimumTicks = (Stopwatch().frequency / 40).ceil(); // 25 ms.
    while (true) {
      var result = 0;
      final elapsed = Stopwatch()..start();
      for (var iteration = 0; iteration < iterations; iteration += 1) {
        result += run();
      }
      elapsed.stop();
      checksum += result;
      if (elapsed.elapsedTicks >= minimumTicks) {
        return elapsed.elapsedTicks / iterations;
      }
      iterations *= 2;
    }
  }
}
