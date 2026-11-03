import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_module.dart';
import 'package:discourse_native/src/shell/plugin_topic_reader.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_skeleton.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';
import 'support/topic_post_list.dart';

void main() {
  for (final resolveReader in [false, true]) {
    for (final limited in [false, true]) {
      testWidgets('desktop skeleton keeps its width through loading '
          '(resolve reader: $resolveReader, limited: $limited)', (
        tester,
      ) async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          feeds: {
            '/latest.json': [
              const Topic(
                id: 7,
                title: 'Desktop loading',
                slug: 'desktop-loading',
              ),
            ],
          },
          topicGate: gate,
          topics: {
            7: topicPayload(
              id: 7,
              title: 'Desktop loading',
              posts: [
                const Post(
                  id: 1,
                  postNumber: 1,
                  username: 'reader',
                  cooked: '<p>Loaded desktop post</p>',
                ),
              ],
            ),
          },
        );
        await pumpShell(
          tester,
          const Size(2000, 900),
          api: api,
          pluginManifest: PluginManifest([
            ...bundledWidgetTestManifest.modules,
            if (resolveReader) postVotingModule,
          ]),
        );
        await tester.drag(
          find.byKey(const ValueKey('main-panel-resize-handle')),
          const Offset(650, 0),
        );
        await tester.pumpAndSettle();
        final title = topicListTitle('Desktop loading');
        final shell = ShellScope.read(tester.element(title));
        await shell.appSettings.setLimitContentSize(limited);
        await tester.pumpAndSettle();
        await tester.tap(title);
        await tester.pump();

        final skeleton = find.byType(TopicLoadingSkeleton);
        final placeholders = find.descendant(
          of: skeleton,
          matching: find.byType(DSkeletonRegion),
        );
        void expectLoadingWidth(String phase) {
          final viewport = tester.getRect(find.byType(TopicReaderOutlet));
          final region = tester.getRect(placeholders);
          expect(viewport.width, greaterThan(825), reason: phase);
          expect(
            region.width,
            closeTo(limited ? 825 : viewport.width, 0.01),
            reason: phase,
          );
          expect(region.center.dx, closeTo(viewport.center.dx, 0.01));
        }

        expect(skeleton, findsOneWidget);
        for (var frame = 0; frame < 30; frame++) {
          expectLoadingWidth('Loading frame $frame');
          await tester.pump(const Duration(milliseconds: 16));
        }
        gate.complete();
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (skeleton.evaluate().isNotEmpty) {
            expectLoadingWidth('Reader resolution frame $frame');
          }
        }
        await tester.pumpAndSettle();
        expect(skeleton, findsNothing);
        expect(renderedText('Loaded desktop post'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
    }
  }

  for (final target in [1, 12]) {
    testWidgets(
      'phone skeleton keeps post $target layout through reader resolution',
      (tester) async {
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
        await pumpShell(
          tester,
          phone,
          api: api,
          pluginManifest: PluginManifest([
            ...bundledWidgetTestManifest.modules,
            postVotingModule,
          ]),
        );
        await tester.tap(find.byKey(const ValueKey('mobile-mode-topics')));
        await tester.pumpAndSettle();
        await tester.tap(topicListTitle('Reading position'));
        await tester.pump();

        final skeleton = find.byType(TopicLoadingSkeleton);
        final placeholders = find.descendant(
          of: skeleton,
          matching: find.byType(DSkeletonRegion),
        );
        final handle = find.byKey(const ValueKey('sheet-drag-handle')).last;
        void expectLoadingPosition(String phase) {
          final gap =
              tester.getTopLeft(placeholders).dy -
              tester.getBottomLeft(handle).dy;
          if (target > 1) {
            expect(gap, inInclusiveRange(-16, 16), reason: phase);
          } else {
            expect(gap, greaterThan(40), reason: phase);
          }
          expect(
            tester.getBottomLeft(placeholders).dy,
            greaterThanOrEqualTo(
              tester.getBottomLeft(find.byType(DSheetContent)).dy,
            ),
            reason: phase,
          );
        }

        for (var frame = 0; frame < 30; frame++) {
          expectLoadingPosition('Loading frame $frame');
          await tester.pump(const Duration(milliseconds: 16));
        }

        gate.complete();
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (skeleton.evaluate().isNotEmpty) {
            expectLoadingPosition('Reader resolution frame $frame');
          }
        }
        await tester.pumpAndSettle();
        expect(skeleton, findsNothing);
        final targetPost = find.byKey(ValueKey(target));
        expect(targetPost, findsOneWidget);
        expect(
          tester.getRect(targetPost).overlaps(topicReadingViewportRect(tester)),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
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
