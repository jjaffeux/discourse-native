import 'package:discourse_native/src/models/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _channels = ChatChannelListSection.channels;

DiscourseUser _user({bool supported = true}) => DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    ChatCurrentUser(
      canChat: true,
      canDirectMessage: true,
      hasChatEnabled: true,
      channelListPreferences: ChatChannelListPreferences.read({
        if (supported)
          for (final section in ChatChannelListSection.values) ...{
            section.filterField: 'all',
            section.sortField: 'alphabetical',
          },
      }),
    ),
  ),
);

ChatChannel _channel(
  int id,
  String title, {
  bool starred = false,
  bool dm = false,
}) => ChatChannel(
  id: id,
  title: title,
  slug: title.toLowerCase(),
  kind: dm ? ChatChannelKind.directMessage : ChatChannelKind.category,
  membership: ChatMembership(following: true, starred: starred),
  lastMessageId: id,
  lastMessageAt: DateTime.utc(2026, 9, id),
);

Future<FakeDiscourseApi> _pump(
  WidgetTester tester, {
  bool supported = true,
}) async {
  final user = _user(supported: supported);
  final api = FakeDiscourseApi(
    user: user,
    totals: chatNotificationTotals(),
    chatChannelsById: {1: _channel(1, 'Alpha')},
    chatMessagesByKey: {
      FakeDiscourseApi.chatMessagesKey(1): (
        messages: const [],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: null,
      ),
    },
    chatChannelsBySite: {
      _site: ChatChannels(
        public: [
          _channel(1, 'Alpha'),
          _channel(2, 'Beta'),
          _channel(3, 'Starred', starred: true),
        ],
        direct: [_channel(4, 'Sam', dm: true)],
      ),
    },
  );
  await pumpShell(
    tester,
    desktop,
    api: api,
    instances: [
      instance('meta.discourse.org', title: 'Meta').copyWith(user: user),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
  );
  return api;
}

Finder _sidebar(Finder finder) =>
    find.descendant(of: find.byType(InstanceSidebar), matching: finder);

void main() {
  testWidgets(
    'sidebar saves are isolated and show-all is shared with the drawer without writes',
    (tester) async {
      final api = await _pump(tester);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      final chat = shell.pluginSession.require(chatControllerService);
      final navigation = shell.pluginSession.require(chatShellService);
      var shellNotifications = 0;
      void notified() => shellNotifications++;
      shell.addListener(notified);
      addTearDown(() => shell.removeListener(notified));

      expect(
        tester.getTopLeft(_sidebar(find.text('Alpha'))).dy,
        lessThan(tester.getTopLeft(_sidebar(find.text('Beta'))).dy),
      );
      await tester.tap(
        _sidebar(find.byKey(const ValueKey('chat-list-options-channels'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent activity'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(_sidebar(find.text('Beta'))).dy,
        lessThan(tester.getTopLeft(_sidebar(find.text('Alpha'))).dy),
      );
      await tester.tap(
        _sidebar(find.byKey(const ValueKey('chat-list-options-channels'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mentions'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_sidebar(find.text('Alpha')), findsNothing);
      expect(_sidebar(find.text('Starred')), findsOneWidget);
      expect(_sidebar(find.text('Sam')), findsOneWidget);
      expect(shellNotifications, 0);
      expect(api.userPreferenceUpdates.map((write) => write.values), [
        {'chat_channel_list_sort': 'recent_activity'},
        {'chat_channel_list_filter': 'mentions'},
      ]);
      expect(
        shell.currentInstance!.user!.chatCurrentUser!.channelListPreferences
            .filterFor(_channels),
        ChatChannelListFilter.mentions,
      );
      await tester.tap(
        _sidebar(find.byKey(const ValueKey('chat-filter-toggle-channels'))),
      );
      await tester.pumpAndSettle();
      expect(_sidebar(find.text('Alpha')), findsOneWidget);
      expect(chat.channelListPreferences.bypassed(_site, _channels), isTrue);
      expect(shellNotifications, 0);

      navigation.openChannels();
      await tester.pumpAndSettle();
      final drawer = find.byType(ChatDrawerChannelsView);
      expect(drawer, findsOneWidget);
      expect(
        find.descendant(of: drawer, matching: find.text('Alpha')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: drawer,
          matching: find.byKey(const ValueKey('chat-filter-toggle-channels')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: drawer,
          matching: find.text('No channels match this filter.'),
        ),
        findsOneWidget,
      );
      expect(_sidebar(find.text('Alpha')), findsNothing);
      expect(api.userPreferenceUpdates, hasLength(2));
      expect(
        chat.channelListPreferences.preferencesFor(_site).sortFor(_channels),
        ChatChannelListSort.recentActivity,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'active channels stay visible through filtering and starring without changing navigation',
    (tester) async {
      await _pump(tester);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      final chat = shell.pluginSession.require(chatControllerService);
      final navigation = shell.pluginSession.require(chatShellService);
      expect(navigation.openChannel(1), isTrue);
      await tester.pumpAndSettle();
      expect(
        navigation.visibleChannelId,
        1,
        reason: navigation.currentContent?.id,
      );
      await chat.channelListPreferences.setFilter(
        _site,
        _channels,
        ChatChannelListFilter.mentions,
      );
      await chat.channelListPreferences.setFilter(
        _site,
        ChatChannelListSection.starred,
        ChatChannelListFilter.mentions,
      );
      await tester.pumpAndSettle();
      expect(
        chat
            .channelList(
              _site,
              _channels,
              activeChannelId: navigation.visibleChannelId,
            )
            .map((c) => (c.id, c.title)),
        [(1, 'Alpha')],
      );
      expect(_sidebar(find.text('Alpha')), findsOneWidget);
      expect(_sidebar(find.text('Beta')), findsNothing);
      final route = navigation.currentContent;
      expect(await chat.updateChannelStarred(_site, 1, true), isNull);
      await tester.pumpAndSettle();
      expect(_sidebar(find.text('Alpha')), findsOneWidget);
      expect(navigation.currentContent, route);
      expect(
        chat
            .channelList(
              _site,
              ChatChannelListSection.starred,
              activeChannelId: navigation.visibleChannelId,
            )
            .map((c) => c.id),
        [1],
      );
      expect(await chat.updateChannelStarred(_site, 1, false), isNull);
      await tester.pumpAndSettle();
      expect(_sidebar(find.text('Alpha')), findsOneWidget);
      expect(navigation.currentContent, route);
      navigation.openChannels();
      await tester.pumpAndSettle();
      expect(_sidebar(find.text('Alpha')), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'older servers expose no options and retain the direct-message action',
    (tester) async {
      final api = await _pump(tester, supported: false);
      expect(
        find.byKey(const ValueKey('chat-list-options-channels')),
        findsNothing,
      );
      expect(
        _sidebar(find.byTooltip('Start a direct message')),
        findsOneWidget,
      );
      expect(api.userPreferenceUpdates, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Native menus and bypass controls fit compact layouts and large text',
    (tester) async {
      await _pump(tester);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      final controller = shell.pluginSession
          .require(chatControllerService)
          .channelListPreferences;
      await controller.setFilter(
        _site,
        _channels,
        ChatChannelListFilter.unread,
      );
      shell.pluginSession.require(chatShellService).openChannels();
      tester.view.physicalSize = phone;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-options-channels')),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
