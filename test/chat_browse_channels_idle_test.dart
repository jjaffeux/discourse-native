// ignore_for_file: avoid_print

import 'package:discourse_native/discourse_ui.dart' show DPlaceCard;
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_ui_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
const _busyChannelId = 11;
const _messages = 10;

ChatChannel _joined(int id) => ChatChannel(
  id: id,
  title: 'Channel $id',
  kind: ChatChannelKind.category,
  canJoin: true,
  membership: const ChatMembership(following: true),
);

/// A channel's messages reach a reader on Browse channels through its
/// new-messages channel. Each changes one card's unread count, so it must
/// leave the page and every other card alone.
void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    final name = platform.name.toLowerCase();

    testWidgets('messages redraw only their own channel card on $name', (
      tester,
    ) async {
      final tracker = await _pumpBrowse(tester);
      final card = find.byKey(
        const ValueKey('chat-browse-channel-$_busyChannelId'),
      );
      expect(tester.widget<DPlaceCard>(card).unreadCount, isNull);

      var elements = 0;
      var cards = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, built) {
        previous?.call(element, built);
        elements++;
        if (element.widget is DPlaceCard) cards++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var index = 0; index < _messages; index++) {
        tracker.deliverPluginMessage('/chat/$_busyChannelId/new-messages', {
          'type': 'channel',
          'channel_id': _busyChannelId,
          'message': {
            'id': 2000 + index,
            'chat_channel_id': _busyChannelId,
            'cooked': '<p>Busy.</p>',
            'created_at': DateTime.utc(2026, 10, 2, 0, index).toIso8601String(),
            'user': {'id': 2, 'username': 'sam'},
          },
        });
        await tester.pump(const Duration(milliseconds: 16));
      }
      debugOnRebuildDirtyWidget = previous;

      print(
        'PERF_PROOF chat-browse-idle '
        'elements_rebuilt_$name=$elements cards_rebuilt_$name=$cards',
      );
      expect(tester.takeException(), isNull);
      expect(tester.widget<DPlaceCard>(card).unreadCount, '$_messages');
      expect(cards, _messages);
      expect(elements, lessThan(2000));
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('the Joined filter still drops a channel the reader leaves', (
    tester,
  ) async {
    final chatFor = <ChatController>[];
    await _pumpBrowse(
      tester,
      prepare: (chat) {
        chatFor.add(chat);
        chat.inboxFilters.browseFor(_site).membership =
            ChatChannelJoinedFilter.joined;
      },
    );
    final card = find.byKey(
      const ValueKey('chat-browse-channel-$_busyChannelId'),
    );
    expect(card, findsOneWidget);

    final chat = chatFor.single;
    final left = await chat.updateChannelFollowing(
      _site,
      chat.channel(_site, _busyChannelId)!,
      false,
    );
    await tester.pumpAndSettle();

    expect(left, isNull);
    expect(card, findsNothing);
    expect(
      find.byKey(const ValueKey('chat-browse-channel-10')),
      findsOneWidget,
    );
  });
}

Future<FakeSiteTracker> _pumpBrowse(
  WidgetTester tester, {
  void Function(ChatController chat)? prepare,
}) async {
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: FakeDiscourseApi(
      user: _user,
      chatChannelsBySite: {
        _site: ChatChannels(
          public: [for (var id = 9; id < 20; id++) _joined(id)],
        ),
      },
      chatBrowsePagesByKey: {
        FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
          channels: [for (var id = 9; id < 40; id++) _joined(id)],
        ),
      },
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  final chat = controller.pluginSession.require(chatControllerService);
  await chat.loadChannels(_site);
  prepare?.call(chat);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: PluginUiScope.own(
        chatPluginId,
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: ChatBrowseChannelsView(siteUrl: _site)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return FakeSiteTracker.built.lastWhere((t) => t.siteUrl == _site);
}
