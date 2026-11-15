import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;
import 'support/dock_corner.dart';
import 'support/fakes.dart';
import 'support/topic_post_list.dart';

final _progress = find.byKey(const ValueKey('topic-progress-button'));

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('captureTopicProgressMotion')) return;
  await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(390, 844);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/topic-progress-motion-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    scene.dispose();
  });
}

Future<void> _loadCaptureFonts(WidgetTester tester) async {
  if (const bool.fromEnvironment('captureTopicProgressMotion')) {
    await tester.runAsync(() async {
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final entry in manifest.cast<Map<String, dynamic>>()) {
        final loader = FontLoader(entry['family'] as String);
        for (final face
            in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
          loader.addFont(rootBundle.load(face['asset'] as String));
        }
        await loader.load();
      }
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('topic controls return at the bottom of recommendations', (
    tester,
  ) async {
    final shell = await fixture.pumpMobileShellFixture(
      tester,
      topic: topicPayload(
        id: 7,
        title: 'A discussion with recommendations',
        canCreatePost: true,
        posts: [
          for (var id = 1; id <= 3; id++)
            Post(
              id: id,
              postNumber: id,
              username: 'reader',
              cooked: List.filled(8, '<p>Reading the discussion.</p>').join(),
            ),
        ],
        recommendations: TopicRecommendations(
          sources: [
            TopicRecommendationSource(
              definition: coreSuggestedTopicRecommendationSource,
              topics: [
                for (var id = 1; id <= 12; id++)
                  Topic(
                    id: 100 + id,
                    title: 'Suggested discussion $id',
                    slug: 'suggested-$id',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    shell.openTopic(
      const Topic(
        id: 7,
        title: 'A discussion with recommendations',
        slug: 'topic-7',
      ),
    );
    await tester.pumpAndSettle();
    final scroll = topicPostList(tester).controller!;
    final bookmark = find.byKey(const ValueKey('topic-header-bookmark-button'));
    final notifications = find.byKey(
      const ValueKey('topic-header-notification-button'),
    );
    expect(_progress.hitTestable(), findsOneWidget);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final bottom = scroll.offset;
    scroll.jumpTo(bottom - 100);
    await tester.pumpAndSettle();
    expect(_progress.hitTestable(), findsNothing);
    expect(bookmark.hitTestable(), findsNothing);
    expect(notifications.hitTestable(), findsNothing);

    scroll.position.pointerScroll(200);
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, 0);
    expect(_progress.hitTestable(), findsOneWidget);
    expect(bookmark.hitTestable(), findsOneWidget);
    expect(notifications.hitTestable(), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(_progress);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(DButton, 'First post'), findsOneWidget);
    expect(find.widgetWithText(DButton, 'Latest post'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'mobile scrollbar moves the reader and dismisses on release',
    (tester) async {
      await _loadCaptureFonts(tester);
      final shell = await fixture.pumpMobileShellFixture(
        tester,
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
      if (const bool.fromEnvironment('captureTopicProgressMotion')) {
        await shell.forumSettings.setShared(
          shell.forumSettings.shared.copyWith(
            font: ForumFont.lato,
            interfaceFont: ForumFont.lato,
          ),
        );
      }
      shell.openTopic(
        const Topic(id: 7, title: 'A long discussion', slug: 'topic-7'),
      );
      await tester.pumpAndSettle();
      final position = topicPostList(tester).controller!.position;
      final bar = find.byWidgetPredicate(
        (widget) =>
            widget is DScrollBar &&
            widget.variant == DScrollBarVariant.scrubber,
      );
      final first = find.widgetWithText(DButton, 'First post');
      final latest = find.widgetWithText(DButton, 'Latest post');
      await tester.tap(_progress);
      await tester.pumpAndSettle();
      expect(first.hitTestable(), findsOneWidget);
      expect(latest.hitTestable(), findsOneWidget);
      expect(find.byType(TopicProgressPanel), findsNothing);
      expect(
        tester.getRect(latest).bottom,
        lessThan(tester.getRect(_progress).top),
      );

      final viewport = tester.getRect(bar);
      final start = Offset(viewport.right - 11, viewport.center.dy);
      final origin = position.pixels;
      final drag = await tester.startGesture(start);
      await tester.pump();
      expect(position.pixels, origin);

      await drag.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(milliseconds: 16));
      final afterDown = position.pixels;
      expect(afterDown, greaterThan(origin + 120));
      expect(first, findsOneWidget);
      await drag.moveBy(const Offset(-30, -24));
      await tester.pump(const Duration(milliseconds: 16));
      final afterReverse = position.pixels;
      expect(afterReverse, lessThan(afterDown));
      expect(afterReverse, greaterThan(origin));
      expect(latest, findsOneWidget);

      await drag.up();
      await tester.pump();
      expect(first, findsNothing);
      expect(latest, findsNothing);
      expect(tester.widget<DScrollBar>(bar).showScrollbar, isFalse);
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(afterReverse, 1));
      await _capture(
        tester,
        '${Theme.of(tester.element(_progress)).platform.name}-released',
      );

      await tester.tap(_progress);
      await tester.pumpAndSettle();
      await _capture(
        tester,
        '${Theme.of(tester.element(_progress)).platform.name}-scrollbar-open',
      );
      await tester.tap(latest);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.postNumber, 80);
      expect(latest, findsNothing);
      await tester.tap(_progress);
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(shell.currentContent?.postNumber, 1);
      expect(first, findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  for (final foot in [0.0, 34.0]) {
    for (final reduced in [false, true]) {
      testWidgets('topic progress follows the tab bar in both directions '
          '(flat, foot $foot, reduced motion: $reduced)', (tester) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        tester.view.padding = FakeViewPadding(top: 44, bottom: foot);
        tester.view.viewPadding = FakeViewPadding(top: 44, bottom: foot);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await _loadCaptureFonts(tester);
        final shell = await fixture.pumpMobileShellFixture(
          tester,
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
          shell.forumSettings.shared.copyWith(
            font: ForumFont.lato,
            interfaceFont: ForumFont.lato,
          ),
        );
        shell.openTopic(
          const Topic(id: 7, title: 'A long discussion', slug: 'topic-7'),
        );
        await tester.pumpAndSettle();
        final scrollable = find.descendant(
          of: topicPostListFinder(),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(2000));
        position.jumpTo(1000);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byType(TopicView));
        final initial = tester.getRect(_progress);
        final inset = DScrollChrome.bottomInsetOf(tester.element(_progress));
        expect(inset, greaterThan(0));
        expect(
          initial.bottom,
          closeTo(viewport.bottom - DSpacing.sm - inset, .5),
        );
        final captureName =
            'flat-${foot.toInt()}-${reduced ? 'reduced' : 'animated'}';
        await _capture(tester, '$captureName-expanded');

        Future<List<double>> move(double delta, String name) async {
          await tester.pump(const Duration(milliseconds: 450));
          final before = position.pixels;
          position.pointerScroll(delta);
          await tester.pump();
          final bottoms = <double>[];
          for (var frame = 0; frame < 50; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            bottoms.add(tester.getRect(_progress).bottom);
            expect(tester.getRect(find.byType(TopicView)), viewport);
            if (frame == 8) {
              await _capture(tester, '$captureName-$name-moving');
            }
          }
          await tester.pumpAndSettle();
          expect(position.pixels, closeTo(before + delta, .01));
          expect(_progress.hitTestable(), findsOneWidget);
          return bottoms;
        }

        final down = await move(160, 'down');
        final lowered = tester.getRect(_progress);
        expect(
          tester.widget<DMobileDock>(find.byType(DMobileDock)).collapsed,
          isTrue,
        );
        final circle = tester.getRect(
          find.byKey(const ValueKey('mobile-dock-surface')),
        );
        final topics = tester.getRect(
          find.byKey(const ValueKey('mobile-dock-reveal')),
        );
        expect(lowered.center.dy, closeTo(topics.center.dy, .01));
        expect(lowered.center.dy, closeTo(circle.center.dy, .01));
        final corner = dockCornerAt(lowered.height, foot);
        expect(viewport.right - lowered.right, closeTo(corner, .01));
        final circleCorner = dockCornerAt(circle.height, foot);
        expect(circleCorner, closeTo(foot == 0 ? 6 : 12.98, .01));
        expect(circle.left, closeTo(circleCorner, .01));
        expect(viewport.bottom - circle.bottom, closeTo(circleCorner, .01));
        expect(lowered.bottom, greaterThan(initial.bottom));
        expect(lowered.size, initial.size);
        await _capture(tester, '$captureName-collapsed');

        final up = await move(-160, 'up');
        expect(
          tester.widget<DMobileDock>(find.byType(DMobileDock)).collapsed,
          isFalse,
        );
        expect(tester.getRect(_progress), initial);
        for (final (frames, increasing) in [(down, true), (up, false)]) {
          final intermediate = frames.where(
            (bottom) =>
                bottom > initial.bottom + .5 && bottom < lowered.bottom - .5,
          );
          if (reduced) {
            expect(intermediate, isEmpty);
          } else {
            expect(intermediate.toSet().length, greaterThan(3));
            for (var i = 1; i < frames.length; i++) {
              expect(
                frames[i],
                increasing
                    ? greaterThanOrEqualTo(frames[i - 1] - .01)
                    : lessThanOrEqualTo(frames[i - 1] + .01),
              );
            }
          }
        }
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }
  }
}
