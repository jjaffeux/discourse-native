// ignore_for_file: avoid_print

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _channelId = 10;
const _threadId = 3;
const _arrivals = 10;

/// An idle composer shows nothing from the transcript, so a message arriving
/// in the open channel or thread must leave every element under it alone.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    final name = platform.name.toLowerCase();

    testWidgets('arrivals leave an idle channel composer alone on $name', (
      tester,
    ) async {
      final tracker = await _pumpBusyChannel(tester, platform);
      final shell = ShellScope.read(tester.element(primaryMainContent));
      if (platform != TargetPlatform.macOS) {
        shell.selectMobilePanel('chat');
        await tester.pumpAndSettle();
      }
      shell.openChatChannel(_channelId);
      await tester.pumpAndSettle();
      expect(find.byType(ChatComposer), findsOneWidget);

      final counts = await _countArrivalRebuilds(tester, (index) {
        tracker.deliverPluginMessage('/chat/$_channelId', _sent(200 + index));
      });

      print(
        'PERF_PROOF idle-chat-composer '
        'channel_composer_rebuilds_$name=${counts.composer} '
        'channel_total_rebuilds_$name=${counts.total}',
      );
      expect(tester.takeException(), isNull);
      expect(counts.composer, 0);
    }, variant: TargetPlatformVariant.only(platform));

    testWidgets('arrivals leave an idle thread composer alone on $name', (
      tester,
    ) async {
      final tracker = await _pumpBusyChannel(tester, platform);
      final shell = ShellScope.read(tester.element(primaryMainContent));
      if (platform != TargetPlatform.macOS) {
        shell.selectMobilePanel('chat');
        await tester.pumpAndSettle();
      }
      shell.openChatChannel(_channelId);
      await tester.pumpAndSettle();
      shell.openChatThread(
        siteUrl: _site,
        channelId: _channelId,
        threadId: _threadId,
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ChatComposer && widget.threadId == _threadId,
        ),
        findsOneWidget,
      );

      final counts = await _countArrivalRebuilds(tester, (index) {
        tracker.deliverPluginMessage(
          '/chat/$_channelId/thread/$_threadId',
          _sent(300 + index, threadId: _threadId),
        );
      });

      print(
        'PERF_PROOF idle-chat-composer '
        'thread_composer_rebuilds_$name=${counts.composer} '
        'thread_total_rebuilds_$name=${counts.total}',
      );
      expect(tester.takeException(), isNull);
      expect(counts.composer, 0);
    }, variant: TargetPlatformVariant.only(platform));
  }
}

Map<String, dynamic> _sent(int id, {int? threadId}) => {
  'type': 'sent',
  'chat_message': {
    'id': id,
    'chat_channel_id': _channelId,
    'thread_id': ?threadId,
    'cooked': '<p>Arrival $id.</p>',
    'created_at': DateTime.utc(2026, 10, 2, 0, id % 60).toIso8601String(),
    'user': {'id': 2, 'username': 'sam'},
  },
};

/// Elements rebuilt over [_arrivals] deliveries, and how many of them sat
/// under a [ChatComposer].
Future<({int composer, int total})> _countArrivalRebuilds(
  WidgetTester tester,
  void Function(int index) deliver,
) async {
  var total = 0;
  var composer = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, built) {
    previous?.call(element, built);
    total++;
    if (element.widget is ChatComposer) {
      composer++;
      return;
    }
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is! ChatComposer) return true;
      composer++;
      return false;
    });
  };
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  for (var index = 0; index < _arrivals; index++) {
    deliver(index);
    await tester.pump(const Duration(milliseconds: 16));
  }
  debugOnRebuildDirtyWidget = previous;
  return (composer: composer, total: total);
}

Future<FakeSiteTracker> _pumpBusyChannel(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
    ),
  );
  ChatMessage message(int id, {int? threadId}) => ChatMessage(
    id: id,
    channelId: _channelId,
    threadId: threadId,
    cooked: '<p>Message $id in a busy channel.</p>',
    author: ChatMessageAuthor(id: id % 3 + 1, username: 'r${id % 3}'),
    createdAt: DateTime.utc(2026, 10, 1).add(Duration(minutes: id)),
  );
  await pumpShell(
    tester,
    platform == TargetPlatform.macOS ? desktop : phone,
    instances: [
      instance('meta.discourse.org').copyWith(user: user, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: FakeDiscourseApi(
      user: user,
      totals: chatNotificationTotals(),
      siteConfigs: {_site: config},
      feeds: const {'/latest.json': <Topic>[]},
      chatChannelsBySite: {
        _site: const ChatChannels(
          public: [
            ChatChannel(
              id: _channelId,
              title: 'Support',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
              threadingEnabled: true,
            ),
          ],
        ),
      },
      chatThreadsByKey: {
        FakeDiscourseApi.chatThreadKey(_channelId, _threadId): const ChatThread(
          id: _threadId,
          channelId: _channelId,
          status: 'open',
          replyCount: 40,
          title: 'A busy thread',
          membership: ChatThreadMembership(threadId: _threadId),
        ),
      },
      chatMessagesByKey: {
        '$_channelId': (
          messages: [for (var id = 1; id <= 80; id++) message(id)],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
        'thread-$_channelId-$_threadId': (
          messages: [
            for (var id = 101; id <= 140; id++)
              message(id, threadId: _threadId),
          ],
          canLoadMorePast: false,
          canLoadMoreFuture: false,
          targetMessageId: null,
        ),
      },
    ),
  );
  return FakeSiteTracker.built.lastWhere((t) => t.siteUrl == _site);
}
