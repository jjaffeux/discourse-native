import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';
import 'support/topic_post_list.dart';

Future<List<int>> _pixels(
  WidgetTester tester,
  Rect region,
  String name,
) async => (await tester.runAsync(() async {
  final builder = ui.SceneBuilder();
  tester.binding.renderViews.first.debugLayer!.addToScene(builder);
  final scene = builder.build();
  final size = tester.view.physicalSize;
  final image = await scene.toImage(size.width.toInt(), size.height.toInt());
  if (const bool.fromEnvironment('captureMobileVisit')) {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File(
      '/tmp/mobile-visit-$name.png',
    ).writeAsBytes(png.buffer.asUint8List());
  }
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final pixels = <int>[];
  for (var y = region.top.toInt(); y < region.bottom.toInt(); y++) {
    pixels.addAll(
      bytes.buffer.asUint8List(
        (y * image.width + region.left.toInt()) * 4,
        region.width.toInt() * 4,
      ),
    );
  }
  image.dispose();
  scene.dispose();
  return pixels;
}))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final (privateMessage, reducedMotion) in [
    for (final privateMessage in [false, true])
      for (final reducedMotion in [false, true])
        (privateMessage, reducedMotion),
  ]) {
    testWidgets(
      'notification reader over a topic reveals the actual previous visit pm=$privateMessage reducedMotion=$reducedMotion',
      (tester) async {
        final shell = await pumpMobileShellFixture(
          tester,
          notifications: [
            DiscourseNotification.test(
              id: 80,
              typeId: NotificationTypeId(privateMessage ? 6 : 2),
              topicId: 8,
              postNumber: 1,
              slug: 'notification',
              title: 'Notification discussion',
              data: const {'display_username': 'sender'},
            ),
          ],
          topic: topicPayload(
            id: 7,
            title: 'Original discussion',
            posts: [
              for (var i = 1; i <= 30; i++)
                Post(
                  id: i,
                  postNumber: i,
                  username: 'reader',
                  cooked:
                      '<p>Original reply $i. ${List.filled(30, 'Keep this reading position.').join(' ')}</p>',
                ),
            ],
          ),
          onApi: (api) {
            api.topics[8] = topicPayload(
              id: 8,
              title: 'Notification discussion',
              privateMessage: privateMessage,
              posts: const [
                Post(
                  id: 81,
                  postNumber: 1,
                  username: 'reader',
                  cooked: '<p>Notification body</p>',
                ),
              ],
            );
          },
        );
        await tester.tap(find.byKey(const ValueKey('topic-card-7')));
        await tester.pumpAndSettle();
        await shell.appSettings.setReduceMotion(reducedMotion);
        await tester.pumpAndSettle();
        topicPostList(tester).controller!.jumpTo(600);
        await tester.pumpAndSettle();
        final offset = topicPostList(tester).controller!.offset;
        final region = Rect.fromLTWH(
          24,
          tester.getRect(find.byKey(const ValueKey('mobile-header'))).bottom +
              12,
          342,
          40,
        );
        final departure = await _pixels(tester, region, 'departure');
        final previous = shell.mobileNavigation.entryId;
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Notification discussion').last);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 8);
        expect(shell.mobileNavigation.previousEntryId, previous);

        final drag = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
        );
        await drag.moveBy(const Offset(0, 20));
        await drag.moveBy(const Offset(0, 120));
        await tester.pump();
        final viewport = tester.widget<DSheetViewport>(
          find.byType(DSheetViewport),
        );
        expect(viewport.underlay, isNotNull);
        expect(
          find.descendant(
            of: find.byWidget(viewport.underlay!),
            matching: find.byType(TopicListView),
          ),
          findsNothing,
          reason:
              'The previous visit was a reader, never a topic or message list.',
        );
        final exposed = await _pixels(tester, region, 'pull');
        final difference =
            List.generate(
              departure.length,
              (i) => (departure[i] - exposed[i]).abs(),
            ).reduce((a, b) => a + b) /
            departure.length;
        if (reducedMotion) {
          expect(
            difference,
            lessThan(3),
            reason:
                'The pull must reveal the previous reader at its departure position.',
          );
        }
        await drag.cancel();
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 8);
        await tester.drag(
          find.byKey(const ValueKey('sheet-drag-handle')),
          const Offset(0, 240),
        );
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (shell.currentContent?.topicId == 7) {
            expect(
              topicPostList(tester).controller!.offset,
              closeTo(offset, 1),
              reason: 'Original reader position on return frame $frame',
            );
          }
        }
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 7);
        expect(shell.mobileNavigation.entryId, previous);
        expect(find.byType(TopicView), findsOneWidget);
        expect(topicPostList(tester).controller!.offset, closeTo(offset, 1));
        expect(shell.handleForward(), isTrue);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 8);
        expect(shell.mobileNavigation.previousEntryId, previous);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
