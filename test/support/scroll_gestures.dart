import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds one touch drag on [scrollable] through [updates] scroll updates.
///
/// Each move reverses the one before it by [travel], so the drag changes
/// direction without being lifted and ends where it began. A nonzero [reach]
/// is one further move made first, to carry the drag to an edge. [afterUpdate]
/// runs after each pumped move, for settling a request the move started.
Future<void> dragOnceThroughUpdates(
  WidgetTester tester,
  Finder scrollable, {
  required double travel,
  double reach = 0,
  int updates = 20,
  void Function()? afterUpdate,
}) async {
  Future<void> move(WidgetTester tester, TestGesture drag, double by) async {
    await drag.moveBy(Offset(0, by));
    await tester.pump();
    afterUpdate?.call();
    await tester.pump();
  }

  final drag = await tester.startGesture(tester.getCenter(scrollable));
  // Crossing the slop only begins the drag; this move scrolls nothing.
  await drag.moveBy(const Offset(0, kTouchSlop + 1));
  await tester.pump();
  if (reach != 0) await move(tester, drag, reach);
  for (var update = 0; update < updates; update++) {
    await move(tester, drag, update.isEven ? travel : -travel);
  }
  await drag.up();
  await tester.pumpAndSettle();
}
