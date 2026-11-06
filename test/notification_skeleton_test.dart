import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_module.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/notifications_menu.dart';
import 'support/topic_post_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final source in ['menu', 'URL']) {
    for (final privateMessage in [false, true]) {
      testWidgets(
        '$source notification keeps its skeleton in place (PM: $privateMessage)',
        (tester) async {
          final gate = Completer<void>();
          final shell = await pumpMobileShellFixture(
            tester,
            topics: const [],
            topicGate: gate,
            pluginManifest: PluginManifest([
              ...bundledWidgetTestManifest.modules,
              postVotingModule,
            ]),
            notifications: [
              DiscourseNotification.test(
                id: 99,
                typeId: NotificationTypeId(privateMessage ? 6 : 2),
                topicId: 7,
                postNumber: 12,
                slug: 'notification',
                title: 'Notification discussion',
                data: const {'display_username': 'sender'},
              ),
            ],
            topic: topicPayload(
              id: 7,
              title: 'Notification discussion',
              privateMessage: privateMessage,
              posts: [
                for (var number = 1; number <= 30; number++)
                  Post(
                    id: number,
                    postNumber: number,
                    username: 'reader',
                    cooked: '<p>Notification post $number</p>',
                  ),
              ],
            ),
          );
          if (source == 'menu') {
            await tester.tap(dockNotifications);
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('notification-row-99')));
          } else {
            expect(
              await shell.openNotificationUrl(
                'https://meta.discourse.org/t/notification/7/12',
              ),
              isTrue,
            );
          }
          await tester.pump();

          final skeleton = find.byType(TopicLoadingSkeleton);
          final placeholders = find.descendant(
            of: skeleton,
            matching: find.byType(DSkeletonRegion),
          );
          final readerSheet = find.ancestor(
            of: skeleton,
            matching: find.byType(DSheetContent),
          );
          final handle = find.descendant(
            of: readerSheet,
            matching: find.byKey(const ValueKey('sheet-drag-handle')),
          );
          double gap() =>
              tester.getTopLeft(placeholders).dy -
              tester.getBottomLeft(handle).dy;
          final openingGap = gap();
          expect(openingGap, inInclusiveRange(-16, 16));

          void expectLoadingPosition(String phase) {
            expect(gap(), closeTo(openingGap, 0.01), reason: phase);
            expect(
              tester.getBottomLeft(placeholders).dy,
              greaterThanOrEqualTo(tester.getBottomLeft(readerSheet).dy),
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
          expect(shell.currentContent?.postNumber, 12);
          expect(shell.currentTopic?.privateMessage, privateMessage);
          final targetPost = find.byKey(const ValueKey(12));
          expect(targetPost, findsOneWidget);
          expect(
            tester
                .getRect(targetPost)
                .overlaps(topicReadingViewportRect(tester)),
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
  }
}
