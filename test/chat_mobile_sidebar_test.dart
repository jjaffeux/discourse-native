import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

final _inbox = find.byType(ChatMobileSidebar);
final _title = find.descendant(of: _inbox, matching: find.text('Browse chats'));
final _navigation = find.byKey(const ValueKey('chat-browse-navigation'));

void _mobileTest(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: const TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  }),
);

/// The production mobile shell on its Chat tab, with more conversations than
/// a phone shows at once.
Future<void> _pumpChatInbox(WidgetTester tester, Size size) async {
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(
        chatEnabled: true,
        publicChannelsEnabled: true,
        threadsEnabled: true,
      ),
    ),
  );
  await pumpShell(
    tester,
    size,
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Meta',
      ).copyWith(user: _user, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: _user,
      totals: chatNotificationTotals(),
      siteConfigs: {_site: config},
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        _site: ChatChannels(
          hasThreads: true,
          public: [
            for (var id = 1; id <= 20; id++)
              ChatChannel(
                id: id,
                title: 'Channel $id',
                kind: ChatChannelKind.category,
                membership: const ChatMembership(following: true),
                tracking: const ChatTracking(),
              ),
          ],
          direct: const [],
        ),
      },
    ),
  );
  // Enlarged text on a narrow phone moves Chat into the dock's More menu.
  final dockTab = find.byKey(const ValueKey('mobile-mode-panel/chat'));
  if (dockTab.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('mobile-mode-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DDropdownMenuItem),
        matching: find.text('Chat'),
      ),
    );
  } else {
    await tester.tap(dockTab);
  }
  await tester.pumpAndSettle();
  expect(_inbox, findsOneWidget);
}

void main() {
  _mobileTest(
    'normal height keeps peer navigation and filters above the scrolling chats',
    (tester) async {
      await _pumpChatInbox(tester, phone);
      final title = tester.getRect(_title);
      final navigation = tester.getRect(_navigation);
      final list = find.descendant(of: _inbox, matching: find.byType(ListView));
      await tester.drag(list, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(tester.getRect(_title), title);
      expect(tester.getRect(_navigation), navigation);
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('Threads'), findsOneWidget);
      expect(find.byType(DCardFooter), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'keyboard and large text keep navigation and conversations reachable',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpChatInbox(tester, const Size(320, 720));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(of: _inbox, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('chat-inbox-channel-20')),
        100,
        scrollable: scrollable,
      );
      expect(
        find.byKey(const ValueKey('chat-inbox-channel-20')).hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(_title, -100, scrollable: scrollable);
      expect(_title.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest('dismissing the keyboard fixes the title and navigation again', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpChatInbox(tester, const Size(320, 720));
    final title = tester.getRect(_title);
    final navigation = tester.getRect(_navigation);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.drag(_title, const Offset(0, -150));
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.getRect(_title), title);
    expect(tester.getRect(_navigation), navigation);
    expect(tester.takeException(), isNull);
  });
}
