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
final _title = find.descendant(of: _inbox, matching: find.text('Chat'));
final _footer = find.descendant(of: _inbox, matching: find.byType(DCardFooter));
const _shortcuts = ['chat-inbox-browse', 'chat-inbox-my-threads'];

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
    'a normal height keeps the title, filters and shortcuts fixed around '
    'the scrolling conversations',
    (tester) async {
      await _pumpChatInbox(tester, phone);
      final inbox = tester.getRect(_inbox);
      final title = tester.getRect(_title);
      final row = find.byKey(const ValueKey('chat-inbox-channel-12'));
      final rowTop = tester.getRect(row).top;
      expect(tester.getRect(_footer).bottom, inbox.bottom);

      await tester.drag(row, const Offset(0, -100));
      await tester.pumpAndSettle();

      expect(tester.getRect(row).top, lessThan(rowTop));
      expect(tester.getRect(_title), title);
      expect(tester.getRect(_footer).bottom, inbox.bottom);
      for (final key in _shortcuts) {
        expect(
          find.byKey(ValueKey(key)).hitTestable(),
          findsOneWidget,
          reason: key,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'a keyboard over large text on a narrow phone scrolls the title, filters '
    'and shortcuts with the conversations',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpChatInbox(tester, const Size(320, 720));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final inbox = tester.getRect(_inbox);
      expect(
        find.byKey(const ValueKey('chat-inbox-kind-filter')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getRect(_footer).top, greaterThan(inbox.bottom));

      final scrollable = find
          .descendant(of: _inbox, matching: find.byType(Scrollable))
          .first;
      for (final key in _shortcuts) {
        final shortcut = find.byKey(ValueKey(key));
        await tester.scrollUntilVisible(shortcut, 100, scrollable: scrollable);
        final rect = tester.getRect(shortcut);
        expect(rect.top, greaterThanOrEqualTo(inbox.top), reason: key);
        expect(rect.bottom, lessThanOrEqualTo(inbox.bottom), reason: key);
        expect(shortcut.hitTestable(), findsOneWidget, reason: key);
      }
      expect(tester.getRect(_title).bottom, lessThan(inbox.top));
      expect(tester.takeException(), isNull);
    },
  );

  _mobileTest(
    'dismissing the keyboard fixes the title and shortcuts around the '
    'conversations again',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpChatInbox(tester, const Size(320, 720));
      final title = tester.getRect(_title);
      final footer = tester.getRect(_footer);
      expect(footer.bottom, tester.getRect(_inbox).bottom);

      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.drag(_title, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.getRect(_title).top, lessThan(title.top));

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();

      expect(tester.getRect(_title), title);
      expect(tester.getRect(_footer), footer);
      expect(tester.takeException(), isNull);
    },
  );
}
