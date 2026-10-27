import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';

final _bar = find.byKey(const ValueKey('mobile-bottom-bar'));
final _moreTrigger = find.descendant(
  of: _bar,
  matching: find.byWidgetPredicate(
    (widget) => widget is DMobileDockItem && widget.hasPopup,
  ),
);

void main() {
  for (final (label, pageType) in [
    ('Chats', ChatMobileSidebar),
    ('Channels', ChatBrowseChannelsView),
    ('Threads', ChatMyThreadsView),
  ]) {
    testWidgets(
      '$label directory swipes collapse the tab bar after closing More',
      (tester) async {
        final channels = [
          for (var id = 1; id <= 40; id++)
            ChatChannel(
              id: id,
              title: 'Channel $id',
              kind: ChatChannelKind.category,
              membership: const ChatMembership(following: true),
              threadingEnabled: true,
            ),
        ];
        await pumpMobileShellFixture(
          tester,
          conversations: ChatChannels(public: channels, direct: const []),
          chatBrowsePage: ChatChannelBrowsePage(
            channels: label == 'Threads' ? [channels.first] : channels,
          ),
          channelThreadPages: {
            FakeDiscourseApi.chatChannelThreadPageKey(1, 0): ChatThreadPage(
              threads: [
                for (var id = 1; id <= 40; id++)
                  ChatThread(
                    id: id,
                    channelId: 1,
                    title: 'Thread $id',
                    status: 'open',
                    replyCount: 2,
                    lastMessageId: id * 10,
                  ),
              ],
            ),
          },
        );
        await tester.tap(find.byKey(const ValueKey('mobile-mode-panel/chat')));
        await tester.pumpAndSettle();
        if (label != 'Chats') {
          final destination = find.descendant(
            of: find.byKey(const ValueKey('chat-browse-navigation')),
            matching: find.text(label),
          );
          await tester.ensureVisible(destination);
          await tester.tap(destination);
          await tester.pumpAndSettle();
        }
        final page = find.byType(pageType);
        expect(page, findsOneWidget);
        await tester.tap(_moreTrigger);
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getTopLeft(find.byKey(DMobileDock.dimKey)) +
              const Offset(10, 10),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(DMobileDock.panelKey), findsNothing);
        final gesture = await tester.startGesture(tester.getCenter(page));
        for (var frame = 0; frame < 30; frame++) {
          await gesture.moveBy(const Offset(0, -8));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('mobile-dock-reveal')).hitTestable(),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 450));
        await tester.drag(page, const Offset(0, 100));
        await tester.pumpAndSettle();
        expect(_bar.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
