import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_list_scroll_fixture.dart';
import 'support/topic_scroll_capture.dart';

void main() {
  testWidgets('fast scrolling only builds the visible topic rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await topicListScrollController();
    final capture = topicScrollCaptureWithoutVm();
    final diagnostics = DiagnosticsController.start(
      persistence: MemoryDiagnosticsPersistence(),
      topicScrollCapture: capture,
    );
    addTearDown(controller.dispose);
    addTearDown(diagnostics.close);
    try {
      await tester.pumpWidget(
        TopicListScrollFixture(
          controller: controller,
          diagnostics: diagnostics,
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable);
      final position = tester.state<ScrollableState>(scrollable).position;
      final viewport = tester.getRect(scrollable);
      final rebuiltTitles = <Element>[];
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (builtOnce && element.widget is TopicTitle) {
          rebuiltTitles.add(element);
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      // Ordinary scrolling keeps existing rows and does not arm diagnostics.
      for (var step = 0; step < 180; step++) {
        position.pointerScroll(40);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(capture.events, isEmpty);
      expect(rebuiltTitles, isEmpty);

      for (final delta in [1200.0, -1200.0]) {
        capture.start();
        for (var step = 0; step < 20; step++) {
          final before = capture.events.length;
          position.pointerScroll(delta);
          final requested = position.pixels;
          await tester.pump(const Duration(milliseconds: 16));

          final visibleTitles = find.byType(TopicTitle).evaluate().where((
            element,
          ) {
            final rect = tester.getRect(
              find.byElementPredicate((candidate) => candidate == element),
            );
            return rect.overlaps(viewport);
          }).length;
          final builtRows = capture.events
              .skip(before)
              .where((event) => event.name == 'topicList.row.built');
          // Up to two edge rows may have visible metadata but clipped titles.
          expect(builtRows.length, lessThanOrEqualTo(visibleTitles + 2));
          expect(position.pixels, closeTo(requested, 0.01));
        }
        capture.stop();
        expect(
          capture.events.where(
            (event) => event.name == 'topicList.capture.context',
          ),
          hasLength(1),
        );
        expect(
          capture.events.where((event) => event.name == 'topicList.view.built'),
          isEmpty,
        );
        expect(
          capture.events.where(
            (event) => event.name == 'topicList.scroll.notification',
          ),
          isNotEmpty,
        );
      }
      expect(rebuiltTitles, isEmpty);
      expect(position.pixels, 7200);
      expect(tester.takeException(), isNull);
    } finally {
      capture.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await diagnostics.close();
    }
  });
}
