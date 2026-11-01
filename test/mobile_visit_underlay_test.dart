import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final privateMessage in [false, true]) {
    testWidgets(
      'notification reader over a topic reveals the actual previous visit pm=$privateMessage',
      (tester) async {
        final shell = await pumpMobileShellFixture(
          tester,
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
        final previous = shell.mobileNavigation.entryId;
        expect(
          await shell.openNotificationUrl(
            'https://meta.discourse.org/t/notification/8/1',
          ),
          isTrue,
        );
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
        await drag.cancel();
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 8);
        await tester.drag(
          find.byKey(const ValueKey('sheet-drag-handle')),
          const Offset(0, 240),
        );
        await tester.pumpAndSettle();
        expect(shell.currentContent?.topicId, 7);
        expect(shell.mobileNavigation.entryId, previous);
        expect(find.byType(TopicView), findsOneWidget);
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
