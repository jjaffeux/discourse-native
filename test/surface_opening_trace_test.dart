import 'package:discourse_native/src/diagnostics/surface_opening_trace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => SurfaceOpeningTrace.observer = null);

  testWidgets('disabled tracing does not schedule a frame callback', (
    tester,
  ) async {
    var checked = false;
    expect(SurfaceOpeningTrace.enabled, isFalse);
    SurfaceOpeningTrace.afterFrame(
      'unused',
      isCurrent: () {
        checked = true;
        return true;
      },
    );
    await tester.pump();
    expect(checked, isFalse);
  });

  testWidgets('frame milestones follow paint and reject retired owners', (
    tester,
  ) async {
    final events = <String>[];
    final timestamps = <int>[];
    SurfaceOpeningTrace.observer = (name, timestamp) {
      events.add(name);
      timestamps.add(timestamp);
    };
    var current = true;
    SurfaceOpeningTrace.mark('request');
    SurfaceOpeningTrace.afterFrame('retired', isCurrent: () => current);
    current = false;
    SurfaceOpeningTrace.afterFrame('visible', isCurrent: () => true);
    expect(events, ['request']);
    await tester.pumpWidget(const SizedBox());
    expect(events, ['request', 'visible']);
    expect(timestamps.last, greaterThanOrEqualTo(timestamps.first));
  });

  testWidgets('a queued milestone cannot leak into a later capture', (
    tester,
  ) async {
    final first = <String>[];
    final second = <String>[];
    SurfaceOpeningTrace.observer = (name, _) => first.add(name);
    SurfaceOpeningTrace.afterFrame('old', isCurrent: () => true);
    SurfaceOpeningTrace.observer = (name, _) => second.add(name);
    await tester.pump();
    expect(first, isEmpty);
    expect(second, isEmpty);
  });
}
