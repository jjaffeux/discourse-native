import 'dart:ui' as ui;

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';
import 'support/topic_post_list.dart';

/// Reads painted colours from the frame on screen, by logical position.
Future<Color Function(Offset)> _paintedColors(WidgetTester tester) async {
  final ratio = tester.view.devicePixelRatio;
  return (await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final size = tester.view.physicalSize;
    final image = await scene.toImage(size.width.toInt(), size.height.toInt());
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final width = image.width;
    image.dispose();
    scene.dispose();
    return (Offset position) {
      final pixel =
          ((position.dy * ratio).floor() * width +
              (position.dx * ratio).floor()) *
          4;
      return Color.fromARGB(
        bytes[pixel + 3],
        bytes[pixel],
        bytes[pixel + 1],
        bytes[pixel + 2],
      );
    };
  }))!;
}

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final (paragraphs, scrollBy) in [
    (12, 850.0),
    (320, 850.0),
    (320, 0.0),
  ]) {
    testWidgets(
      'forward swipe ($paragraphs paragraphs, scroll $scrollBy) restores the topic without a blank identity or body',
      (tester) async {
        const title = 'Returning to a community discussion';
        const row = Topic(id: 7, title: title, slug: 'shared');
        final shell = await pumpMobileShellFixture(
          tester,
          topic: topicPayload(
            id: 7,
            title: title,
            categoryId: 42,
            tags: const [TopicTag(id: 1, name: 'navigation')],
            posts: [
              for (var id = 1; id <= 8; id++)
                Post(
                  id: id,
                  postNumber: id,
                  username: 'reader',
                  cooked: List.filled(
                    paragraphs,
                    '<p>Post $id keeps the discussion going.</p>',
                  ).join(),
                ),
            ],
          ),
          sidebarCategories: const [
            TopicCategory(
              id: 42,
              name: 'Support',
              slug: 'support',
              color: '0088cc',
            ),
          ],
        );
        shell.openTopic(row);
        for (var frame = 0; frame < 40; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        if (scrollBy > 0) {
          await tester.drag(topicPostListFinder(), Offset(0, -scrollBy));
          await tester.pumpAndSettle();
        }
        final header = find.byKey(const ValueKey('mobile-header'));
        final identity = find.descendant(
          of: header,
          matching: find.text(title),
        );
        expect(identity, findsOneWidget);
        final metadata = find.byKey(const ValueKey('topic-bar-metadata'));
        expect(metadata, findsOneWidget);
        final savedPost = shell.topicScrollPostNumber(7) ?? 1;
        final anchor = find.byKey(ValueKey(savedPost));
        final savedBounds = tester.getRect(anchor);
        final savedOffset = topicPostList(tester).controller!.offset;
        expect(savedOffset, scrollBy > 0 ? greaterThan(0) : 0);
        shell.handleBack();
        await tester.pumpAndSettle();

        final surface = tester.getRect(
          find.byKey(const ValueKey('mobile-root')),
        );
        Future<TestGesture> reveal() async {
          final gesture = await tester.startGesture(
            Offset(surface.right - 5, surface.center.dy),
          );
          await gesture.moveBy(
            const Offset(-180, 0),
            timeStamp: const Duration(milliseconds: 200),
          );
          await tester.pump();
          return gesture;
        }

        final cancelled = await reveal();
        expect(identity, findsOneWidget);
        final opacity = tester
            .widget<Opacity>(
              find.ancestor(of: identity, matching: find.byType(Opacity)).first,
            )
            .opacity;
        expect(opacity, scrollBy > 0 ? inExclusiveRange(0, 1) : 0);
        expect(
          find.byKey(const ValueKey('mobile-page-title')).hitTestable(),
          findsNothing,
        );
        await cancelled.cancel();
        await tester.pumpAndSettle();
        expect(identity, findsNothing);
        expect(shell.currentContent?.isTopicList, isTrue);
        final gesture = await reveal();
        expect(
          identity,
          findsOneWidget,
          reason: 'the retained topic title appears during the swipe',
        );
        expect(
          metadata,
          findsOneWidget,
          reason: 'the retained category and tags appear during the swipe',
        );
        final swipeImage = tester
            .widget<RawImage>(
              find.descendant(
                of: find.byKey(const ValueKey('history-next-preview')),
                matching: find.byType(RawImage),
              ),
            )
            .image!
            .clone();
        addTearDown(swipeImage.dispose);
        await gesture.up();
        var observedHandoff = false;
        var coveredLoading = false;
        final handoff = find.byKey(const ValueKey('history-page-handoff'));
        for (var frame = 0; frame < 80; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          if (shell.currentContent?.isTopic != true) continue;
          if (handoff.evaluate().isNotEmpty) {
            observedHandoff = true;
            final image = tester
                .widget<RawImage>(
                  find.descendant(of: handoff, matching: find.byType(RawImage)),
                )
                .image!;
            expect(image.isCloneOf(swipeImage), isTrue);
          }
          if (find.byType(TopicLoadingSkeleton).evaluate().isNotEmpty) {
            coveredLoading = true;
            expect(
              tester.widget<Opacity>(handoff).opacity,
              1,
              reason:
                  'frame $frame must keep the swipe image over the loading reader',
            );
            expect(topicPostListFinder().hitTestable(), findsNothing);
          } else {
            expect(
              tester.getRect(anchor).top,
              closeTo(savedBounds.top, 1),
              reason: 'frame $frame must preserve the reading position',
            );
          }
        }
        expect(observedHandoff, isTrue);
        if (paragraphs == 320) expect(coveredLoading, isTrue);
        expect(handoff, findsNothing);
        expect(find.byType(TopicLoadingSkeleton), findsNothing);
        expect(find.byType(TopicView), findsOneWidget);
        if (scrollBy > 0) {
          final topicPosition = topicPostList(tester).controller!.position;
          await tester.tap(find.byKey(const ValueKey('mobile-page-title')));
          await tester.pumpAndSettle();
          expect(topicPosition.pixels, 0);
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  for (final pull in [true, false]) {
    testWidgets(
      '${pull ? 'pulling down' : 'going back from'} a topic opened from another topic never shows the earlier topic loading',
      (tester) async {
        List<Post> posts(int topicId) => [
          for (var number = 1; number <= 8; number++)
            Post(
              id: topicId * 100 + number,
              postNumber: number,
              username: 'reader',
              cooked: List.filled(
                320,
                '<p>Post $number keeps topic $topicId going.</p>',
              ).join(),
            ),
        ];
        const first = Topic(id: 7, title: 'First discussion', slug: 'first');
        const second = Topic(id: 8, title: 'Second discussion', slug: 'second');
        final shell = await pumpMobileShellFixture(
          tester,
          topic: topicPayload(id: 7, title: first.title, posts: posts(7)),
          onApi: (api) => api.topics[8] = topicPayload(
            id: 8,
            title: second.title,
            posts: posts(8),
          ),
        );
        Future<void> load() async {
          for (var frame = 0; frame < 40; frame++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pumpAndSettle();
        }

        shell.openTopic(first);
        await load();
        await tester.drag(topicPostListFinder(), const Offset(0, -850));
        await tester.pumpAndSettle();
        shell.openTopic(second);
        await load();
        expect(shell.currentContent?.topicId, 8);
        expect(find.byType(TopicLoadingSkeleton), findsNothing);

        if (pull) {
          final drag = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
          );
          for (var step = 1; step <= 20; step++) {
            await drag.moveBy(
              const Offset(0, 10),
              timeStamp: Duration(milliseconds: step * 20),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          await drag.up();
        } else {
          shell.handleBack();
        }
        final handoff = find.byKey(const ValueKey('history-page-handoff'));
        var returned = false;
        for (var frame = 0; frame < 80; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          if (shell.currentContent?.topicId != 7) continue;
          returned = true;
          if (find.byType(TopicLoadingSkeleton).evaluate().isEmpty) continue;
          expect(
            handoff,
            findsOneWidget,
            reason: 'frame $frame shows the first topic loading uncovered',
          );
          expect(
            tester.widget<Opacity>(handoff).opacity,
            1,
            reason: 'frame $frame fades the image over the loading reader',
          );
        }
        expect(returned, isTrue);
        expect(handoff, findsNothing);
        expect(find.byType(TopicLoadingSkeleton), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets(
    'pulling a topic down to its list leaves the live list usable at once',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      await tester.tap(find.byKey(const ValueKey('topic-card-7')));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 7);

      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      for (var step = 1; step <= 20; step++) {
        await drag.moveBy(
          const Offset(0, 10),
          timeStamp: Duration(milliseconds: step * 20),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await drag.up();
      final card = find.byKey(const ValueKey('topic-card-7'));
      var returned = false;
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (shell.currentContent?.isTopicList != true) continue;
        returned = true;
        expect(
          card.hitTestable(),
          findsOneWidget,
          reason: 'frame $frame must not cover the live list with its image',
        );
      }
      expect(returned, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  // A topic opened at its start rises over the bar, so its retained image
  // sits higher than a list page. Both samples lie in the sheet's blank
  // leading margin: one above the bar's lower edge, one below it.
  const sheetOverBar = Offset(8, 30);
  const sheetBelowBar = Offset(8, 60);
  const topic = Topic(id: 7, title: 'A topic over the bar', slug: 'shared');

  Offset onPreview(WidgetTester tester, Finder image, Offset imagePoint) {
    final bounds = tester.getRect(image);
    final scale = bounds.width / tester.widget<RawImage>(image).image!.width;
    return bounds.topLeft + imagePoint * scale * tester.view.devicePixelRatio;
  }

  testWidgets(
    'a forward swipe draws the whole incoming topic sheet over the bar',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      shell.openTopic(topic);
      await _pumpFrames(tester, 40);
      await tester.pumpAndSettle();
      shell.handleBack();
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byKey(const ValueKey('mobile-header')));
      final list = await _paintedColors(tester);

      final surface = tester.getRect(find.byKey(const ValueKey('mobile-root')));
      final gesture = await tester.startGesture(
        Offset(surface.right - 5, surface.center.dy),
      );
      await gesture.moveBy(
        const Offset(-300, 0),
        timeStamp: const Duration(milliseconds: 200),
      );
      await tester.pump();
      final image = find.descendant(
        of: find.byKey(const ValueKey('history-next-preview')),
        matching: find.byType(RawImage),
      );
      final overBar = onPreview(tester, image, sheetOverBar);
      final belowBar = onPreview(tester, image, sheetBelowBar);
      expect(overBar.dy, lessThan(bar.bottom));
      expect(belowBar.dy, greaterThan(bar.bottom));
      final swipe = await _paintedColors(tester);
      expect(list(overBar), isNot(swipe(belowBar)));
      expect(
        swipe(overBar),
        swipe(belowBar),
        reason: 'the bar must not cut off the top of the incoming sheet',
      );
      final bounds = tester.getRect(image);
      final snapshot = tester.widget<RawImage>(image).image!;
      expect(
        bounds.height / bounds.width,
        closeTo(snapshot.height / snapshot.width, .001),
        reason: 'the incoming sheet must keep its foot',
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'a back swipe uncovers a topic over the bar only where the page has left',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      shell.openTopic(topic);
      await _pumpFrames(tester, 40);
      await tester.pumpAndSettle();
      shell.pushContent(ContentRoute.topicList(TopicListMode.unread));
      await _pumpFrames(tester, 40);
      final bar = tester.getRect(find.byKey(const ValueKey('mobile-header')));
      final list = await _paintedColors(tester);

      final surface = tester.getRect(find.byKey(const ValueKey('mobile-root')));
      final gesture = await tester.startGesture(
        Offset(surface.left + 5, surface.center.dy),
      );
      await gesture.moveBy(
        const Offset(300, 0),
        timeStamp: const Duration(milliseconds: 200),
      );
      await tester.pump();
      final image = find.descendant(
        of: find.byKey(const ValueKey('history-previous-preview')),
        matching: find.byType(RawImage),
      );
      final overBar = onPreview(tester, image, sheetOverBar);
      final belowBar = onPreview(tester, image, sheetBelowBar);
      expect(overBar.dy, lessThan(bar.bottom));
      expect(belowBar.dy, greaterThan(bar.bottom));
      final swipe = await _paintedColors(tester);
      expect(list(overBar), isNot(swipe(belowBar)));
      expect(
        swipe(overBar),
        swipe(belowBar),
        reason: 'the bar must not cut off the top of the revealed sheet',
      );
      final stillCovered = Offset(surface.left + 340, overBar.dy);
      expect(
        swipe(stillCovered),
        list(stillCovered),
        reason: 'the bar stays above the part of the page still in place',
      );
      await gesture.cancel();
      // The pushed list never finishes loading here, so its skeleton keeps
      // animating.
      await _pumpFrames(tester, 40);
      expect(shell.currentContent?.isTopicList, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
