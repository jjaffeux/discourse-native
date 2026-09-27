import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void expectSkeletonFillsViewport(
  WidgetTester tester, {
  required String label,
  required double bottom,
}) {
  final region = find.byType(DSkeletonRegion);
  expect(region, findsOneWidget);
  expect(tester.widget<DSkeletonRegion>(region).semanticsLabel, label);
  final bounds = tester.getRect(region);
  expect(bounds.bottom, closeTo(bottom, 1));

  // Check the actual shapes near the bottom, not just the region's bounds:
  // stretching a fixed six-row placeholder would still leave a blank page.
  final shapes = find.descendant(of: region, matching: find.byType(DSkeleton));
  final visibleShapes = shapes
      .evaluate()
      .map((element) {
        return tester.getRect(
          find.byElementPredicate((other) => other == element),
        );
      })
      .where((rect) => rect.overlaps(bounds));
  expect(visibleShapes, isNotEmpty);
  expect(
    visibleShapes.any((rect) => rect.bottom >= bottom - 100),
    isTrue,
    reason: 'Skeleton shapes should reach the bottom of the viewport.',
  );
  expect(tester.takeException(), isNull);
}
