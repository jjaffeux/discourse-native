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

    testWidgets('a message as the server publishes it leaves an idle channel '
        'composer alone on $name', (tester) async {
      final tracker = await _pumpBusyChannel(tester, platform);
      await _openChannel(tester, platform);
      final hint = await _composerHint(tester);
      expect(hint, contains('Support'));

      void publish(int id) {
        final message = _payload(id);
        tracker
          ..deliverPluginMessage('/chat/$_channelId', {
            'type': 'sent',
            'chat_message': message,
          })
          ..deliverPluginMessage('/chat/$_channelId/new-messages', {
            'type': 'channel',
            'channel_id': _channelId,
            'message': message,
          });
      }

      // The first arrival settles the page's scroll fade, which the phone
      // composer dock follows once.
      publish(199);
      await tester.pump(const Duration(milliseconds: 16));

      final counts = await _countArrivalRebuilds(
        tester,
        (index) => publish(200 + index),
      );

      print(
        'PERF_PROOF idle-chat-composer '
        'server_published_composer_rebuilds_$name=${counts.composer} '
        'server_published_total_rebuilds_$name=${counts.total}',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Arrival 209.', findRichText: true), findsOneWidget);
      expect(counts.composer, 0);

      tracker.deliverPluginMessage('/chat/channel-edits', {
        'chat_channel_id': _channelId,
        'name': 'Renamed',
        'slug': 'renamed',
        'description': null,
      });
      await tester.pump(const Duration(milliseconds: 16));
      expect(await _composerHint(tester), contains('Renamed'));
      expect(await _composerHint(tester), isNot(contains('Support')));

      tracker.deliverPluginMessage('/chat/channel-status', {
        'chat_channel_id': _channelId,
        'status': 'read_only',
      });
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.byKey(const ValueKey('chat-composer-read-only')),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(platform));

    testWidgets('a reply as the server publishes it leaves an idle thread '
        'composer alone on $name', (tester) async {
      final tracker = await _pumpBusyChannel(tester, platform);
      await _openChannel(tester, platform);
      final shell = ShellScope.read(tester.element(primaryMainContent));
      shell.openChatThread(
        siteUrl: _site,
        channelId: _channelId,
        threadId: _threadId,
      );
      await tester.pumpAndSettle();

      final counts = await _countArrivalRebuilds(tester, (index) {
        final message = _payload(300 + index, threadId: _threadId);
        tracker
          ..deliverPluginMessage('/chat/$_channelId/thread/$_threadId', {
            'type': 'sent',
            'chat_message': message,
          })
          ..deliverPluginMessage('/chat/$_channelId/new-messages', {
            'type': 'thread',
            'channel_id': _channelId,
            'thread_id': _threadId,
            'message': message,
          });
      });

      print(
        'PERF_PROOF idle-chat-composer '
        'server_published_thread_composer_rebuilds_$name=${counts.composer} '
        'server_published_thread_total_rebuilds_$name=${counts.total}',
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

Map<String, dynamic> _payload(int id, {int? threadId}) => {
  'id': id,
  'chat_channel_id': _channelId,
  'thread_id': ?threadId,
  'cooked': '<p>Arrival $id.</p>',
  'created_at': DateTime.utc(2026, 10, 2, 0, id % 60).toIso8601String(),
  'user': {'id': 2, 'username': 'sam'},
};

Map<String, dynamic> _sent(int id, {int? threadId}) => {
  'type': 'sent',
  'chat_message': _payload(id, threadId: threadId),
};

Future<void> _openChannel(WidgetTester tester, TargetPlatform platform) async {
  final shell = ShellScope.read(tester.element(primaryMainContent));
  if (platform != TargetPlatform.macOS) {
    shell.selectMobilePanel('chat');
    await tester.pumpAndSettle();
  }
  shell.openChatChannel(_channelId);
  await tester.pumpAndSettle();
  expect(find.byType(ChatComposer), findsOneWidget);
}

Future<String> _composerHint(WidgetTester tester) async {
  final hints = tester.widgetList<Text>(
    find.descendant(of: find.byType(ChatComposer), matching: find.byType(Text)),
  );
  return hints.map((text) => text.data ?? '').join(' | ');
}

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
