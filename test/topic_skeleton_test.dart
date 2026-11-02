import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_skeleton.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  for (final target in [1, 12]) {
    testWidgets('phone loading skeleton respects opening post $target', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            Topic(
              id: 7,
              title: 'Reading position',
              slug: 'reading-position',
              highestPostNumber: 30,
              lastReadPostNumber: target - 1,
            ),
          ],
        },
        topicGate: gate,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Reading position',
            posts: [
              for (var number = 1; number <= 30; number++)
                Post(
                  id: number,
                  postNumber: number,
                  username: 'reader',
                  cooked: '<p>Post $number</p>',
                ),
            ],
          ),
        },
      );
      await pumpShell(tester, phone, api: api);
      await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
      await tester.pumpAndSettle();
      await tester.tap(topicListTitle('Reading position'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final skeleton = find.byType(TopicLoadingSkeleton);
      final handle = find.byKey(const ValueKey('sheet-drag-handle')).last;
      final gap =
          tester.getTopLeft(skeleton).dy - tester.getBottomLeft(handle).dy;
      if (target > 1) {
        expect(gap, inInclusiveRange(-16, 16));
      } else {
        expect(gap, greaterThan(40));
      }
      expect(
        tester.getBottomLeft(skeleton).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(TopicView)).dy),
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(skeleton, findsNothing);
      expect(api.topicPostNumbersOpened, everyElement(target));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  testWidgets(
    'placeholders stay transparent and still through the grace period',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: TopicSkeletonReveal(
              child: DSkeletonRegion(
                semanticsLabel: 'Loading topic',
                child: DSkeleton(key: ValueKey('shape'), width: 80, height: 10),
              ),
            ),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      try {
        double opacity() => tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .opacity;
        bool ticking() => TickerMode.valuesOf(
          tester.element(find.byKey(const ValueKey('shape'))),
        ).enabled;

        expect(
          tester.getSize(find.byKey(const ValueKey('shape'))),
          const Size(80, 10),
        );
        expect(opacity(), 0);
        expect(ticking(), isFalse);
        expect(find.bySemanticsLabel('Loading topic'), findsOneWidget);

        await tester.pump(
          TopicSkeletonReveal.delay - const Duration(milliseconds: 1),
        );
        expect(opacity(), 0);

        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(DMotion.enter);
        expect(opacity(), 1);
        expect(ticking(), isTrue);
      } finally {
        handle.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
