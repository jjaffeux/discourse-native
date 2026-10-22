import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_list_scroll_fixture.dart';

void main() {
  testWidgets(
    'rows reuse their construction until the width breakpoint changes',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = await topicListScrollController(count: 10);

      addTearDown(() async {
        controller.dispose();
        await controller.pluginTeardown;
        await controller.plugins.close();
      });
      {
        await tester.pumpWidget(
          TopicListScrollFixture(
            controller: controller,
            width: double.infinity,
          ),
        );
        Future<void> resize(double width) async {
          tester.view.physicalSize = Size(width, 700);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await resize(800);
        final row = find.byKey(const ValueKey('topic-card-1'));
        final title = tester.element(
          find.descendant(of: row, matching: find.byType(TopicTitle)),
        );
        final rebuilt = <Element>{};
        final previous = debugOnRebuildDirtyWidget;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          rebuilt.add(element);
          previous?.call(element, builtOnce);
        };
        addTearDown(() => debugOnRebuildDirtyWidget = previous);
        await resize(700);
        expect(rebuilt, isNot(contains(title)));
        final posters = find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('topic-card-posters-1')),
        );
        expect(posters, findsOneWidget);
        await resize(599);
        expect(posters, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text('1')),
          findsOneWidget,
        );
        await resize(600);
        expect(posters, findsOneWidget);
      }
    },
  );

  testWidgets('retracting header preserves scroll and viewport positions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await topicListScrollController();
    addTearDown(() async {
      controller.dispose();
      await controller.pluginTeardown;
      await controller.plugins.close();
    });

    try {
      await tester.pumpWidget(
        TopicListScrollFixture(
          controller: controller,

          header: const SizedBox(height: 104, child: Text('Topics')),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable);
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(1500);
      await tester.pumpAndSettle();
      final initialHeight = position.viewportDimension;
      final initialPixels = position.pixels;

      for (final delta in [160.0, -160.0, 160.0, -160.0]) {
        // Wait out the endpoint hold, then cross the reversal slack and move
        // the full header so every capture includes an actual transition.
        await tester.pump(const Duration(milliseconds: 450));

        position.pointerScroll(delta);
        await tester.pump(const Duration(milliseconds: 16));
        for (var frame = 0; frame < 16; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();

        expect(position.pixels, initialPixels + (delta > 0 ? 160 : 0));
        expect(
          position.viewportDimension,
          closeTo(initialHeight + (delta > 0 ? 104 : 0), 0.01),
        );
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  test('profile fixture appends bounded pages', () async {
    final controller = await topicListScrollController(count: 65, pageSize: 30);
    addTearDown(() async {
      controller.dispose();
      await controller.pluginTeardown;
      await controller.plugins.close();
    });
    expect(controller.currentFeed!.topicIds, hasLength(30));
    await controller.loadMoreFeed('latest');
    expect(controller.currentFeed!.topicIds, hasLength(60));
    await controller.loadMoreFeed('latest');
    expect(controller.currentFeed!.topicIds, hasLength(65));
    expect(controller.currentFeed!.hasMore, isFalse);
  });

  for (final (mode, events, assignments) in [
    (TopicListDisplayMode.card, false, false),
    (TopicListDisplayMode.compact, false, false),
    (TopicListDisplayMode.compact, true, false),
    (TopicListDisplayMode.compact, false, true),
    (TopicListDisplayMode.compact, true, true),
  ]) {
    testWidgets(
      '$mode events=$events assignments=$assignments scrolls without churn',
      (tester) async {
        tester.view.physicalSize = const Size(900, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = await topicListScrollController(
          mode: mode,
          events: events,
          assignments: assignments,
        );

        addTearDown(() async {
          controller.dispose();
          await controller.pluginTeardown;
          await controller.plugins.close();
        });

        try {
          await tester.pumpWidget(
            TopicListScrollFixture(controller: controller),
          );
          await tester.pumpAndSettle();
          if (mode == TopicListDisplayMode.compact) {
            // Fitting row tables must not mount a separate horizontal
            // scrollable for every topic entering the viewport.
            expect(find.byType(Scrollable), findsOneWidget);
          }
          expect(
            find.byKey(const ValueKey('event-calendar-stamp')),
            events ? findsWidgets : findsNothing,
          );
          expect(
            find.text('joffrey'),
            assignments ? findsWidgets : findsNothing,
          );
          final scrollable = find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          );
          final position = tester.state<ScrollableState>(scrollable).position;
          expect(position.maxScrollExtent, greaterThan(14400));
          final rebuiltTitles = <Element>[];
          final builtTitles = find.byType(TopicTitle).evaluate().toSet();
          final previous = debugOnRebuildDirtyWidget;
          debugOnRebuildDirtyWidget = (element, builtOnce) {
            previous?.call(element, builtOnce);
            if (element.widget is TopicTitle && !builtTitles.add(element)) {
              rebuiltTitles.add(element);
            }
          };
          addTearDown(() => debugOnRebuildDirtyWidget = previous);

          // Ordinary scrolling keeps existing rows and does not arm diagnostics.
          for (var step = 0; step < 180; step++) {
            final requested = position.pixels + 40;
            position.pointerScroll(40);
            await tester.pump(const Duration(milliseconds: 16));
            expect(position.pixels, closeTo(requested, 0.01));
          }
          expect(position.pixels, 7200);

          expect(rebuiltTitles, isEmpty);

          for (final delta in [1200.0, -1200.0]) {
            for (var step = 0; step < 6; step++) {
              final requested = position.pixels + delta;
              position.pointerScroll(delta);
              await tester.pump(const Duration(milliseconds: 16));

              expect(position.pixels, closeTo(requested, 0.01));
            }
          }
          expect(rebuiltTitles, isEmpty);
          expect(position.pixels, 7200);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}
