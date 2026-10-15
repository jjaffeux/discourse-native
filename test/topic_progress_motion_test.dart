import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final material in DAppearanceMaterial.values) {
    for (final reduced in [false, true]) {
      testWidgets('topic progress follows the tab bar in both directions '
          '($material, reduced motion: $reduced)', (tester) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        if (const bool.fromEnvironment('captureTopicProgressMotion')) {
          await tester.runAsync(() async {
            final manifest =
                jsonDecode(await rootBundle.loadString('FontManifest.json'))
                    as List;
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
            material: material,
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
        final captureName =
            '${material.name}-${reduced ? 'reduced' : 'animated'}';
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
        expect(lowered.bottom, closeTo(initial.bottom + inset, .5));
        expect(lowered.size, initial.size);
        expect(lowered.right, initial.right);
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
