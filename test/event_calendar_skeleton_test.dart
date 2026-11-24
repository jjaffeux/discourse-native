import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_calendar_skeleton.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/skeleton_expectations.dart';

void main() {
  testWidgets('wide month skeleton shows five equal calendar weeks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1300, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EventCalendarSkeleton(
            view: EventCalendarView.month,
            dayCount: 35,
            month: EventMonthMetrics(
              layout: EventMonthLayout.grid,
              dayHeaderHeight: 28,
              laneHeight: 20,
            ),
          ),
        ),
      ),
    );
    final region = tester.getRect(find.byType(DSkeletonRegion));
    expect(region.bottom, 900);
    final lastWeekTop = region.top + 32 + 4 * (28 + 4 * 20);
    final shapes = find.byType(DSkeleton).evaluate().map((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    });
    expect(shapes.any((rect) => rect.top >= lastWeekTop), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('schedule skeleton fills resized viewports at $scale scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final size in [
        const Size(390, 844),
        const Size(390, 1200),
        const Size(1280, 1440),
        const Size(390, 844),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: scale == 2
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: child!,
              ),
            ),
            home: const Scaffold(
              body: EventCalendarSkeleton(
                view: EventCalendarView.schedule,
                dayCount: 30,
                month: EventMonthMetrics(
                  layout: EventMonthLayout.compact,
                  dayHeaderHeight: 28,
                  laneHeight: 20,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expectSkeletonFillsViewport(
          tester,
          label: 'Loading events',
          bottom: size.height,
        );
      }
    });
  }
}
