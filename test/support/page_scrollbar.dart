import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the real viewport and scrollbar in the empty page margin.
Future<void> expectPageEdgeScrolling(
  WidgetTester tester, {
  required Finder viewport,
  required double right,
}) async {
  final bounds = tester.getRect(viewport);
  expect(bounds.right, closeTo(right, 0.001));
  final state = tester.state<ScrollableState>(
    find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
  );
  final position = state.position;
  expect(position.maxScrollExtent, greaterThan(0));
  position.jumpTo(0);
  await tester.pump();

  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: Offset(right - 20, bounds.top + 80),
      scrollDelta: const Offset(0, 40),
    ),
  );
  await tester.pump();
  expect(position.pixels, greaterThan(0));

  position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.dragFrom(
    Offset(right - 3, bounds.top + 8),
    const Offset(0, 120),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
  expect(position.pixels, greaterThan(0));
  expect(tester.takeException(), isNull);
}
