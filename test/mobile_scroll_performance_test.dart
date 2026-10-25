import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;
import 'support/fakes.dart';
import 'support/topic_post_list.dart';

Set<RenderObject> _artwork(Finder root) => find
    .descendant(
      of: root,
      matching: find.byWidgetPredicate(
        (widget) => widget is RenderObjectWidget,
      ),
    )
    .evaluate()
    .map((element) => (element as RenderObjectElement).renderObject)
    // PaintingContext also reports retained boundaries when merely compositing
    // their layers. Count the artwork inside them to detect actual repaints.
    .where((object) => !object.isRepaintBoundary)
    .toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final reader in [false, true]) {
      testWidgets(
        '${reader ? 'reader' : 'topics'} isolates scroll and dock paints (flat)',
        (tester) async {
          final shell = await fixture.pumpMobileShellFixture(
            tester,
            topics: [
              for (var id = 1; id <= 100; id++)
                Topic(
                  id: id,
                  title: 'Topic $id with a longer title that wraps on mobile',
                  slug: 'topic-$id',
                ),
            ],
            topic: topicPayload(
              id: 7,
              title: 'A long discussion',
              canCreatePost: true,
              posts: [
                for (var id = 1; id <= 80; id++)
                  Post(
                    id: id,
                    postNumber: id,
                    username: 'reader',
                    cooked: '<p>Post $id discusses reading and navigation.</p>',
                  ),
              ],
            ),
          );
          await shell.forumSettings.setShared(
            shell.forumSettings.shared.copyWith(),
          );
          await tester.pumpAndSettle();
          if (reader) {
            shell.openTopic(
              const Topic(id: 7, title: 'A long discussion', slug: 'topic-7'),
            );
            await tester.pumpAndSettle();
          }
          final scrollable = find.descendant(
            of: reader ? topicPostListFinder() : find.byType(TopicListView),
            matching: find.byType(Scrollable),
          );
          expect(scrollable, findsOneWidget);
          final position = tester.state<ScrollableState>(scrollable).position;
          expect(position.maxScrollExtent, greaterThan(2000));
          position.jumpTo(1000);
          await tester.pumpAndSettle();
          final viewport = tester.getRect(scrollable);
          final page = tester.widget<DPageSurface>(
            find
                .ancestor(of: scrollable, matching: find.byType(DPageSurface))
                .first,
          );
          final titleHeight = tester
              .getSize(find.byWidget(page.header!))
              .height;
          final fixedHeader = _artwork(
            find.byKey(const ValueKey('mobile-header')),
          );
          final dock = find.byType(DMobileDock);

          final surface = find.byKey(const ValueKey('mobile-dock-surface'));
          final expandedWidth = tester.getSize(surface).width;
          var headerPaints = 0;
          var dockPaints = 0;
          var totalPaints = 0;
          var dockArtwork = <RenderObject>{};
          final previous = debugOnProfilePaint;
          debugOnProfilePaint = (object) {
            previous?.call(object);
            totalPaints++;
            if (fixedHeader.contains(object)) headerPaints++;
            if (dockArtwork.contains(object)) dockPaints++;
          };
          try {
            final gesture = await tester.startGesture(
              tester.getCenter(scrollable),
            );
            await gesture.moveBy(const Offset(0, -30));
            await tester.pump();
            final statesDuringMotion = <bool>{};
            for (final delta in [-220.0, 300.0, -300.0, 300.0]) {
              final before = position.pixels;
              await gesture.moveBy(Offset(0, delta));
              for (var frame = 0; frame < 6; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                final next = tester.widget<DMobileDock>(dock).collapsed;
                final width = tester.getSize(surface).width;
                if (width > 49 && width < expandedWidth - .1) {
                  statesDuringMotion.add(next);
                }
              }
              expect(
                position.pixels,
                delta < 0 ? greaterThan(before) : lessThan(before),
              );
              final currentViewport = tester.getRect(scrollable);
              if (reader) {
                expect(currentViewport, viewport);
              } else {
                expect(currentViewport.left, viewport.left);
                expect(currentViewport.right, viewport.right);
                expect(currentViewport.bottom, closeTo(viewport.bottom, .001));
                expect(
                  currentViewport.top,
                  inInclusiveRange(viewport.top - titleHeight, viewport.top),
                );
              }
            }
            await gesture.cancel();
            await tester.pumpAndSettle();
            expect(statesDuringMotion, containsAll([true, false]));
            expect(tester.widget<DMobileDock>(dock).collapsed, isFalse);
            debugPrint(
              'MOBILE_SCROLL_PAINTS reader=$reader platform=$platform '
              'material=flat total=$totalPaints header=$headerPaints',
            );
            expect(totalPaints, greaterThan(0));
            expect(headerPaints, 0);

            // Keep the settled navigation control's artwork cached. Its outer
            // live glass lens may still repaint to update its backdrop.
            await tester.pump(const Duration(milliseconds: 450));
            position.pointerScroll(160);
            await tester.pumpAndSettle();
            expect(tester.widget<DMobileDock>(dock).collapsed, isTrue);
            dockArtwork = _artwork(
              find.byKey(const ValueKey('mobile-dock-reveal')),
            );
            for (var frame = 0; frame < 20; frame++) {
              position.pointerScroll(4);
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(dockPaints, 0);
            expect(headerPaints, 0);
            expect(tester.takeException(), isNull);
          } finally {
            debugOnProfilePaint = previous;
          }
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
}
