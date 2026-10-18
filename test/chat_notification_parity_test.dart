import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/desktop_header_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_panel_tabs_test.dart' as panels;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  // ChatHeaderIconUnreadIndicator applies these preferences to the web's
  // aggregate count; Native's desktop and mobile Chat navigation must agree.
  for (final (preference, ordinaryOnly, dnd, label, dot) in [
    (ChatHeaderIndicatorPreference.allNew, true, false, null, true),
    (ChatHeaderIndicatorPreference.allNew, false, false, '17', false),
    (
      ChatHeaderIndicatorPreference.directMessagesAndMentions,
      true,
      false,
      null,
      false,
    ),
    (
      ChatHeaderIndicatorPreference.directMessagesAndMentions,
      false,
      false,
      '17',
      false,
    ),
    (ChatHeaderIndicatorPreference.onlyMentions, false, false, '5', false),
    (ChatHeaderIndicatorPreference.never, false, false, null, false),
    (ChatHeaderIndicatorPreference.allNew, false, true, null, false),
  ]) {
    testWidgets(
      'Chat navigation: ${preference.name}, ordinary=$ordinaryOnly, DND=$dnd',
      (tester) async {
        final mobile = defaultTargetPlatform == TargetPlatform.iOS;
        final user = DiscourseUser(
          id: 7,
          username: 'reader',
          doNotDisturbUntil: dnd
              ? DateTime.now().add(const Duration(days: 1))
              : null,
          plugins: PluginData.none.withValue(
            chatCurrentUserDataKey,
            ChatCurrentUser(
              hasChatEnabled: true,
              headerIndicatorPreference: preference,
            ),
          ),
        );
        await panels.pumpTabs(
          tester,
          size: mobile ? const Size(430, 900) : const Size(1440, 900),
          currentUser: user,
          voice: false,
          channels: {panels.site: _channels(ordinaryOnly: ordinaryOnly)},
        );
        final badge = find.byKey(
          ValueKey(
            mobile ? 'chat-mobile-unread-badge' : 'chat-sidebar-unread-badge',
          ),
        );
        if (label != null) {
          expect(badge, findsOneWidget);
          expect(
            tester.widget(badge),
            mobile ? isA<DBadge>() : isA<Semantics>(),
          );
          expect(
            find.descendant(of: badge, matching: find.text(label)),
            findsOneWidget,
          );
        } else if (dot) {
          expect(tester.widget(badge), isA<DNotificationDot>());
        } else {
          expect(badge, findsNothing);
        }
        expect(
          find.byKey(ChatHeaderButton.buttonKey),
          mobile ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(ChatHeaderButton.urgentBadgeKey),
          !mobile && label != null ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(ChatHeaderButton.unreadDotKey),
          !mobile && dot ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets('header menu uses a dot for public unreads and sums DM urgency', (
    tester,
  ) async {
    await panels.pumpTabs(
      tester,
      currentUser: DiscourseUser(
        id: 7,
        username: 'reader',
        plugins: PluginData.none.withValue(
          chatCurrentUserDataKey,
          const ChatCurrentUser(hasChatEnabled: true),
        ),
      ),
      voice: false,
      channels: {
        panels.site: ChatChannels(
          public: _channels(ordinaryOnly: true).public,
          direct: _channels().direct,
        ),
      },
    );
    await tester.tap(find.byKey(ChatHeaderButton.buttonKey));
    await tester.pumpAndSettle();
    final publicRow = find.byKey(const ValueKey('chat-header-channel-9'));
    expect(tester.widget<DesktopHeaderMenuRow>(publicRow).count, 0);
    expect(
      find.descendant(of: publicRow, matching: find.byType(DNotificationDot)),
      findsOneWidget,
    );
    final directRow = find.byKey(const ValueKey('chat-header-channel-10'));
    expect(tester.widget<DesktopHeaderMenuRow>(directRow).count, 9);
    expect(
      find.descendant(of: directRow, matching: find.text('9')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

ChatChannels _channels({bool ordinaryOnly = false}) => ChatChannels(
  public: [
    ChatChannel(
      id: 9,
      title: 'General',
      kind: ChatChannelKind.category,
      membership: const ChatMembership(following: true),
      tracking: ChatTracking(
        unreadCount: 20,
        mentionCount: ordinaryOnly ? 0 : 3,
        watchedThreadsUnreadCount: ordinaryOnly ? 0 : 5,
      ),
    ),
  ],
  direct: ordinaryOnly
      ? const []
      : const [
          ChatChannel(
            id: 10,
            title: 'Direct',
            kind: ChatChannelKind.directMessage,
            membership: ChatMembership(following: true),
            tracking: ChatTracking(unreadCount: 7, mentionCount: 2),
          ),
        ],
);
