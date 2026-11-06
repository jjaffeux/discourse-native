import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/notifications_menu.dart';

void main() {
  testWidgets(
    'channel title returns after dismissing a notification topic',
    (tester) async {
      const ingress = MethodChannel('org.discourse.native/notification_opens');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ingress, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(ingress, null));
      final shell = await pumpMobileShellFixture(
        tester,
        conversations: const ChatChannels(
          public: [
            ChatChannel(
              id: 10,
              title: 'Support',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
            ),
          ],
          direct: [],
        ),
        notifications: const [
          DiscourseNotification.test(
            id: 1,
            typeId: NotificationTypeId(2),
            title: 'Shared topic card',
            topicId: 7,
            postNumber: 1,
            slug: 'shared',
            data: {'display_username': 'sam'},
          ),
        ],
      );
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-inbox-channel-10')));
      await tester.pumpAndSettle();

      final title = find.byKey(const ValueKey('mobile-page-title'));
      void expectChannelTitle() {
        expect(title.hitTestable(), findsOneWidget);
        expect(
          tester.widget<DButton>(title).semanticLabel,
          'Back to the top of Support',
        );
      }

      expectChannelTitle();

      await tester.tap(dockNotifications);
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notification-row-1')));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 7);
      expect(find.byType(UserMenuPanel), findsNothing);

      await tester.drag(
        find.byKey(const ValueKey('sheet-drag-handle')),
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, isNull);
      expect(find.byType(ChatChannelView), findsOneWidget);
      expectChannelTitle();
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
