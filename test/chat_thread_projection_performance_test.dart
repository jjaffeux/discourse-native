import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_directory.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
final _user = const DiscourseUser(id: 7, username: 'reader').withPlugins(
  PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true),
  ),
);
const _updates = 100;
const _samples = 5;
const _channelIds = [9, 10, 11];
const _otherChannel = ChatChannel(
  id: 99,
  title: 'Other conversation',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true, lastReadMessageId: 0),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final threadsPerChannel in [1, 100]) {
    testWidgets('unrelated read updates preserve a mounted directory with '
        '${threadsPerChannel * _channelIds.length} threads', (tester) async {
      final channels = [
        for (final id in _channelIds)
          ChatChannel(
            id: id,
            title: 'Channel $id',
            kind: ChatChannelKind.category,
            threadingEnabled: true,
          ),
      ];
      final api = FakeDiscourseApi(
        user: _user,
        totals: chatNotificationTotals(),
        feeds: const {'/latest.json': []},
        chatChannelsBySite: {
          _site: ChatChannels(public: [...channels, _otherChannel]),
        },
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: channels,
          ),
        },
        chatChannelThreadPagesByKey: {
          for (final channel in channels)
            for (
              var offset = 0;
              offset < threadsPerChannel;
              offset += ChatThreadPage.pageSize
            )
              FakeDiscourseApi.chatChannelThreadPageKey(
                channel.id,
                offset,
              ): ChatThreadPage(
                threads: [
                  for (
                    var index = offset + 1;
                    index <= threadsPerChannel &&
                        index <= offset + ChatThreadPage.pageSize;
                    index++
                  )
                    _thread(channel.id, index),
                ],
                hasMore: offset + ChatThreadPage.pageSize < threadsPerChannel,
              ),
        },
      );
      late _CountingStore store;
      final plugins = installBundledPluginsWithChatStore(
        (policy) => store = _CountingStore(policy),
      );
      addTearDown(plugins.close);
      final shell = ShellController(
        plugins: plugins,
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: _user),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      final chat = shell.pluginSession.require(chatControllerService);
      await chat.loadChannels(_site);
      shell.accountActivity.applyCounts(_site, (_) => chatNotificationTotals());
      final directory = ChatThreadDirectory(chat, _site);
      addTearDown(directory.dispose);
      do {
        await directory.load();
      } while (directory.hasMore(null));
      expect(directory.threads, hasLength(threadsPerChannel * channels.length));
      expect(
        api.chatChannelThreadPagesRequested,
        hasLength(channels.length * ((threadsPerChannel + 9) ~/ 10)),
      );
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: PluginUiScope.own(
            chatPluginId,
            MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: ChatMyThreadsView(siteUrl: _site)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(FakeSiteTracker.built, isNotEmpty);
      final tracker = FakeSiteTracker.built.last;
      expect(tracker.disposed, isFalse);
      expect(tracker.userId, _user.id);
      expect(
        tracker.pluginChannelCallbacks['/chat/user-tracking-state/${_user.id}'],
        hasLength(1),
      );
      final firstId = 9000 + threadsPerChannel;
      expect(store.containsRecord<ChatThread>(_site, firstId), isTrue);
      expect(
        chat.threadRef(_site, firstId).value,
        same(store.read<ChatThread>(_site, firstId)),
      );
      expect(find.text('Thread $firstId'), findsOneWidget);
      expect(find.byType(ChatBrowseThreadRow), findsWidgets);
      final expectedIds = directory.threads.map((thread) => thread.id).toList();
      var directoryNotifications = 0;
      var chatNotifications = 0;
      var rowRebuilds = 0;
      directory.addListener(() => directoryNotifications++);
      void onChat() => chatNotifications++;
      chat.addListener(onChat);
      addTearDown(() => chat.removeListener(onChat));
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is ChatBrowseThreadRow) rowRebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (var sample = 0; sample < _samples; sample++) {
        store.threadReads = 0;
        directoryNotifications = 0;
        chatNotifications = 0;
        rowRebuilds = 0;
        for (var update = 1; update <= _updates; update++) {
          tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
            'channel_id': _otherChannel.id,
            'last_read_message_id': sample * _updates + update,
            'unread_count': 0,
            'mention_count': 0,
            'watched_threads_unread_count': 0,
          });
          await tester.pump();
        }
        final counts = {
          'workload': 'mounted-thread-directory-unrelated-channel-read',
          'threads': threadsPerChannel * channels.length,
          'page_size': ChatThreadPage.pageSize,
          'sample': sample,
          'updates': _updates,
          'canonical_thread_reads': store.threadReads,
          'directory_observer_notifications': directoryNotifications,
          'chat_notifications': chatNotifications,
          'row_rebuilds': rowRebuilds,
          'mounted_rows': find.byType(ChatBrowseThreadRow).evaluate().length,
        };
        expect(
          chat.channel(_site, 99)?.membership.lastReadMessageId,
          (sample + 1) * _updates,
        );
        expect(chatNotifications, _updates);
        expect(counts['canonical_thread_reads'], 0);
        expect(directory.threads.map((thread) => thread.id), expectedIds);
        expect(find.text('Thread $firstId'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugPrint('CHAT_THREAD_PROJECTION ${jsonEncode(counts)}');
      }
      final first = store.read<ChatThread>(_site, firstId)!;
      store.put(_site, first.copyWith(title: 'Renamed thread'));
      tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
        'channel_id': 99,
        'last_read_message_id': _samples * _updates + 1,
      });
      await tester.pumpAndSettle();
      expect(find.text('Renamed thread'), findsOneWidget);
      store.put(
        _site,
        first.copyWith(
          title: 'Renamed thread',
          tracking: const ChatTracking(unreadCount: 7),
        ),
      );
      tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
        'channel_id': 99,
        'last_read_message_id': _samples * _updates + 2,
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('chat-my-thread-unread-$firstId')),
        findsOneWidget,
      );
      expect(chat.channelThreads(_site, 9).first.id, firstId);
      store.put(
        _site,
        first.copyWith(
          originalMessage: first.originalMessage!.copyWith(
            deletedAt: DateTime.utc(2026),
          ),
        ),
      );
      tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
        'channel_id': 99,
        'last_read_message_id': _samples * _updates + 3,
      });
      await tester.pumpAndSettle();
      expect(find.text('Renamed thread'), findsNothing);
      expect(find.byKey(ValueKey('chat-my-thread-$firstId')), findsNothing);
      expect(
        directory.threads.map((thread) => thread.id),
        isNot(contains(firstId)),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

ChatThread _thread(int channelId, int index) {
  final id = channelId * 1000 + index;
  return ChatThread(
    id: id,
    channelId: channelId,
    status: 'open',
    title: 'Thread $id',
    replyCount: 1,
    lastMessageId: id * 10 + 1,
    originalMessage: ChatThreadOriginalMessage(
      id: id * 10,
      channelId: channelId,
      author: const ChatMessageAuthor(id: 2, username: 'sam'),
      excerpt: 'Original $id',
    ),
  );
}

class _CountingStore extends Store {
  _CountingStore(StorePolicy policy) : super(policy: policy);

  int threadReads = 0;

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == ChatThread) threadReads++;
    return super.read<T>(siteUrl, id);
  }
}
