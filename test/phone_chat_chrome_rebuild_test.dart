// ignore_for_file: avoid_print

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_shell.dart';
import 'support/dock_panel.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _quietSite = 'https://quiet.example';
const _chatlessSite = 'https://chatless.example';
const _ios = TargetPlatformVariant({TargetPlatform.iOS});

final _user = DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

final _chatPlace = find.byKey(const ValueKey('mobile-mode-panel/chat'));
final _badge = find.byKey(const ValueKey('chat-mobile-unread-badge'));

SiteConfig _config({
  bool chat = true,
  bool publicChannels = true,
  bool threads = true,
}) => SiteConfig(
  plugins: PluginData.none.withValue(
    chatSettingsDataKey,
    ChatSettings(
      chatEnabled: chat,
      publicChannelsEnabled: publicChannels,
      threadsEnabled: threads,
    ),
  ),
);

/// The production phone shell with twenty followed channels.
Future<ShellController> _pumpPhone(WidgetTester tester) async {
  final configs = {
    _site: _config(),
    _quietSite: _config(publicChannels: false, threads: false),
    _chatlessSite: _config(chat: false),
  };
  await pumpShell(
    tester,
    phone,
    instances: [
      for (final MapEntry(key: url, value: config) in configs.entries)
        instance(
          url.substring('https://'.length),
        ).copyWith(user: _user, config: config),
    ],
    authenticator: FakeAuthenticator()
      ..keys.addAll({for (final url in configs.keys) url: 'key'}),
    api: FakeDiscourseApi(
      user: _user,
      totals: chatNotificationTotals(),
      siteConfigs: configs,
      feeds: {
        '/latest.json': [
          for (var id = 1; id <= 40; id++)
            Topic(id: id + 100, title: 'Topic $id', slug: 'topic-$id'),
        ],
      },
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
                lastMessageId: 80,
                lastMessageAt: DateTime.utc(2026, 10, 1, 0, 21 - id),
              ),
          ],
          direct: const [],
          newChannelBusLastId: 1,
          newMessageBusLastIds: {for (var id = 1; id <= 20; id++) id: 1},
          newMentionMessageBusLastIds: {for (var id = 1; id <= 20; id++) id: 1},
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
  final shell = ShellScope.read(tester.element(primaryMainContent));
  await shell.chat.loadChannels(_site);
  await tester.pumpAndSettle();
  return shell;
}

FakeSiteTracker get _tracker =>
    FakeSiteTracker.built.lastWhere((tracker) => tracker.siteUrl == _site);

void _readCredit(int channelId, int unread) => _tracker.deliverPluginMessage(
  '/chat/user-tracking-state/7',
  {'channel_id': channelId, 'last_read_message_id': 1, 'unread_count': unread},
);

void _message(int channelId, int id) =>
    _tracker.deliverPluginMessage('/chat/$channelId/new-messages', {
      'type': 'channel',
      'channel_id': channelId,
      'message': {
        'id': id,
        'chat_channel_id': channelId,
        'cooked': '<p>new</p>',
        'created_at': DateTime.utc(2026, 10, 2, 0, id % 60).toIso8601String(),
        'user': {'id': 2, 'username': 'sam'},
      },
    }, messageId: id);

void _mention(int channelId, int id) => _tracker.deliverPluginMessage(
  '/chat/$channelId/new-mentions',
  {'channel_id': channelId, 'message_id': id},
  messageId: id,
);

Future<int> _rebuildsDuring(Future<void> Function() events) async {
  var rebuilds = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    rebuilds++;
  };
  try {
    await events();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilds;
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  group('chat traffic on a phone', () {
    testWidgets('on the Chat tab redraws the chrome only for the indicator', (
      tester,
    ) async {
      final shell = await _pumpPhone(tester);
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();

      final rebuilds = await _rebuildsDuring(() async {
        for (var event = 0; event < 10; event++) {
          _readCredit(20, 3 + event);
          await tester.pump(const Duration(milliseconds: 16));
        }
      });

      print(
        'PERF_PROOF phone-chat-chrome chat_tab_tracking_rebuilds=$rebuilds',
      );
      expect(_badge, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(rebuilds, lessThanOrEqualTo(711));
    }, variant: _ios);

    testWidgets('on the Forum tab redraws the chrome only for the indicator', (
      tester,
    ) async {
      await _pumpPhone(tester);

      final rebuilds = await _rebuildsDuring(() async {
        for (var event = 0; event < 10; event++) {
          _message(20, 200 + event);
          await tester.pump(const Duration(milliseconds: 16));
        }
      });

      print(
        'PERF_PROOF phone-chat-chrome forum_tab_message_rebuilds=$rebuilds',
      );
      expect(_badge, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(rebuilds, lessThanOrEqualTo(2149));
    }, variant: _ios);
  });

  group('the phone dock', () {
    testWidgets('shows, counts and clears the chat indicator', (tester) async {
      await _pumpPhone(tester);
      expect(_chatPlace, findsOneWidget);
      expect(_badge, findsNothing);

      _readCredit(20, 3);
      await tester.pump();
      expect(tester.widget(_badge), isA<DNotificationDot>());

      _readCredit(20, 0);
      await tester.pump();
      expect(_badge, findsNothing);

      _mention(2, 2);
      await tester.pump();
      expect(
        tester.widget<DBadge>(_badge).semanticLabel,
        'Chat, 1 urgent message',
      );

      _mention(3, 3);
      await tester.pump();
      expect(
        tester.widget<DBadge>(_badge).semanticLabel,
        'Chat, 2 urgent messages',
      );
      expect(tester.takeException(), isNull);
    }, variant: _ios);

    testWidgets('offers Chat and its places as the site allows them', (
      tester,
    ) async {
      final shell = await _pumpPhone(tester);
      Future<void> showForum(int index) async {
        shell.selectInstance(index);
        await tester.pumpAndSettle();
      }

      Future<void> expectPanel({
        required bool channels,
        required bool threads,
      }) async {
        await openDockPanel(tester);
        expect(
          dockPanelTile('Channels'),
          channels ? findsOneWidget : findsNothing,
        );
        expect(
          dockPanelTile('Threads'),
          threads ? findsOneWidget : findsNothing,
        );
        await tester.tapAt(const Offset(200, 40));
        await tester.pumpAndSettle();
      }

      expect(_chatPlace, findsOneWidget);
      await expectPanel(channels: true, threads: true);

      await showForum(1);
      expect(_chatPlace, findsOneWidget);
      await expectPanel(channels: false, threads: false);

      await showForum(2);
      expect(_chatPlace, findsNothing);

      await showForum(0);
      expect(_chatPlace, findsOneWidget);
      await expectPanel(channels: true, threads: true);
      expect(tester.takeException(), isNull);
    }, variant: _ios);
  });
}
