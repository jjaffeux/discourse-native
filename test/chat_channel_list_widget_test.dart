import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
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
  await tester.tap(find.byKey(const ValueKey('sidebar-panel-switch-chat')));
  await tester.pumpAndSettle();
  return api;
}

Finder _sidebar(Finder finder) =>
    find.descendant(of: find.byType(InstanceSidebar), matching: finder);

void main() {
  testWidgets('channel heading and rows follow the shared content width', (
    tester,
  ) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(2000, 900);
    final shell = ShellScope.read(tester.element(find.byType(MainContent)));
    shell.pushContent(
      const ContentRoute(
        id: ChatPlugin.channelsRouteId,
        title: 'Chat',
        icon: DIcons.comments,
        openInSecondaryPanel: true,
      ),
    );
    await tester.pumpAndSettle();

    final page = find.byType(ChatChannelsView);
    const headingKey = ValueKey('chat-channel-list-heading-content');
    const rowKey = ValueKey('chat-channel-list-channel-1');
    const listKey = PageStorageKey<ChatChannelListKind>(
      ChatChannelListKind.channels,
    );
    final pageWidth = tester.getSize(page).width;
    expect(pageWidth, greaterThan(DPageReadingLane.maxWidth + 28));

    for (final limited in [false, true, false]) {
      await shell.appSettings.setLimitContentSize(limited);
      await tester.pumpAndSettle();

      final heading = tester.getRect(find.byKey(headingKey));
      final row = tester.getRect(find.byKey(rowKey));
      expect(tester.getSize(find.byKey(listKey)).width, pageWidth);
      expect(
        heading.width,
        limited ? DPageReadingLane.maxWidth : pageWidth - 28,
      );
      expect(row.width, limited ? DPageReadingLane.maxWidth : pageWidth - 16);
      expect(heading.center.dx, closeTo(row.center.dx, 2.1));
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'channel list saves are isolated and leave the sidebar inbox alone',
    (tester) async {
      final api = await _pump(tester);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      final chat = shell.pluginSession.require(chatControllerService);
      final navigation = shell.pluginSession.require(chatShellService);

      // The inbox orders by activity alone and exposes no list preferences.
      expect(
        _sidebar(find.byKey(const ValueKey('chat-list-options-channels'))),
        findsNothing,
      );
      navigation.openChannels();
      await tester.pumpAndSettle();
      var shellNotifications = 0;
      void notified() => shellNotifications++;
      shell.addListener(notified);
      addTearDown(() => shell.removeListener(notified));
      final channelList = find.byType(ChatChannelsView);
      Finder inList(Finder finder) =>
          find.descendant(of: channelList, matching: finder);
      Future<void> choose(String option) async {
        await tester.tap(
          inList(find.byKey(const ValueKey('chat-list-options-channels'))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(option));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }

      expect(
        tester.getTopLeft(inList(find.text('Alpha'))).dy,
        lessThan(tester.getTopLeft(inList(find.text('Beta'))).dy),
      );
      await choose('Recent activity');
      expect(
        tester.getTopLeft(inList(find.text('Beta'))).dy,
        lessThan(tester.getTopLeft(inList(find.text('Alpha'))).dy),
      );
      await choose('Mentions');
      expect(inList(find.text('Alpha')), findsNothing);
      expect(
        inList(find.text('No channels match this filter.')),
        findsOneWidget,
      );
      expect(_sidebar(find.text('Alpha')), findsOneWidget);
      expect(_sidebar(find.text('Beta')), findsOneWidget);
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
        inList(find.byKey(const ValueKey('chat-filter-toggle-channels'))),
      );
      await tester.pumpAndSettle();
      expect(inList(find.text('Alpha')), findsOneWidget);
      expect(chat.channelListPreferences.bypassed(_site, _channels), isTrue);
      expect(api.userPreferenceUpdates, hasLength(2));
      expect(shellNotifications, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'active channels stay listed through filtering and starring without changing navigation',
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
      final route = navigation.currentContent;
      expect(await chat.updateChannelStarred(_site, 1, true), isNull);
      await tester.pumpAndSettle();
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
      expect(navigation.currentContent, route);
      expect(_sidebar(find.text('Alpha')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'older servers expose no options and retain the direct-message action',
    (tester) async {
      final api = await _pump(tester, supported: false);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      final action = find.byKey(const ValueKey('chat-sidebar-start-message'));
      expect(tester.widget<DButton>(action).variant, DButtonVariant.primary);
      // Pinned beneath the inbox rather than above its filters.
      expect(
        tester.getRect(action).top,
        greaterThan(tester.getRect(_sidebar(find.text('Sam'))).bottom),
      );

      shell.pluginSession.require(chatShellService).openChannels();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-list-options-channels')),
        findsNothing,
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Start chatting'), findsOneWidget);
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
