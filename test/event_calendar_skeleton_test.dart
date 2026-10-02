import 'package:discourse_native/src/plugins/discourse_events/event_calendar_skeleton.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/skeleton_expectations.dart';

void main() {
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
