import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;
import 'chat_thread_controller_test.dart' as threads;
import 'support/fakes.dart';

void main() {
  for (final target in <ChatStreamTarget>[
    const ChatChannelTarget(9),
    threads.target,
  ]) {
    test(
      '${target.storageKey} readers page independently and share records',
      () async {
        final base = target is ChatThreadTarget ? 'thread-9-22' : '9';
        final api = FakeDiscourseApi(
          chatChannelsBySite: {
            fixtures.site: ChatChannels(
              public: [fixtures.channel(9, lastRead: 0)],
              direct: const [],
            ),
          },
          chatThreadsByKey: {
            FakeDiscourseApi.chatThreadKey(9, 22): threads.threadDetail(),
          },
          chatMessagesByKey: {
            base: fixtures.page([fixtures.message(100), fixtures.message(101)]),
            '$base~target~42': fixtures.page(
              [fixtures.message(41), fixtures.message(42)],
              canLoadMoreFuture: true,
              canLoadMorePast: true,
            ),
            '$base~past~41': fixtures.page([fixtures.message(40)]),
          },
        );
        final subject = fixtures.build(api: api);
        addTearDown(subject.chat.dispose);
        await subject.chat.loadChannels(fixtures.site);
        final source = subject.chat.acquireReader(
          fixtures.site,
          target,
          readerId: 'source',
        );
        final destination = subject.chat.acquireReader(
          fixtures.site,
          target,
          readerId: 'destination',
        );
        addTearDown(source.dispose);
        addTearDown(destination.dispose);
        await source.open();
        final sourceWindow = source.stream;
        await destination.open(targetMessageId: 42, force: true);
        await destination.loadOlder();
        expect(source.stream, same(sourceWindow));
        expect(source.messages.map((m) => m.id), [100, 101]);
        expect(destination.messages.map((m) => m.id), [40, 41, 42]);
        expect(destination.stream.anchorMessageId, 42);
        final sourceToken = source.beginViewing();
        final destinationToken = destination.beginViewing();
        source.endViewing(sourceToken);
        source.dispose();
        expect(source.isCurrent, isFalse);
        expect(destination.isCurrent, isTrue);
        expect(destination.messages.map((m) => m.id), [40, 41, 42]);
        destination.endViewing(destinationToken);
        subject.chat.forget(fixtures.site);
        expect(destination.isCurrent, isFalse);
        expect(destination.stream.messageIds, isEmpty);
      },
    );
  }

  test(
    'live arrivals extend each present reader and park behind historical gaps',
    () async {
      final subject = fixtures.build(
        currentUser: fixtures.currentUser,
        channels: {
          fixtures.site: ChatChannels(
            public: [fixtures.channel(9)],
            direct: const [],
            newMessageBusLastIds: const {9: 70},
            kickMessageBusLastIds: const {9: 72},
          ),
        },
        messages: {
          '9': fixtures.page([fixtures.message(100)]),
          '9~target~42': fixtures.page([
            fixtures.message(42),
          ], canLoadMoreFuture: true),
        },
      );
      addTearDown(subject.chat.dispose);
      final tracker = fixtures.attachTracker(subject.chat);
      await subject.chat.loadChannels(fixtures.site);
      final latest = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'latest',
      );
      final history = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'history',
      );
      addTearDown(latest.dispose);
      addTearDown(history.dispose);
      latest.beginViewing();
      history.beginViewing();
      await latest.open();
      await history.open(targetMessageId: 42, force: true);
      tracker.deliverPluginMessage(
        '/chat/9/new-messages',
        fixtures.newMessageEvent(
          channelId: 9,
          messageId: 101,
          authorId: 2,
          createdAt: '2026-08-08T13:00:00.000Z',
        ),
      );
      expect(latest.stream.messageIds, [100, 101]);
      expect(history.stream.messageIds, [42]);
      expect(history.stream.pendingNewMessages, 1);
      tracker.deliverPluginMessage('/chat/9/kick', {'channel_id': 9});
      expect(latest.stream.messageIds, isEmpty);
      expect(history.stream.messageIds, isEmpty);
      expect(latest.stream.error, isNotNull);
      expect(history.stream.error, isNotNull);
    },
  );

  test(
    'read admission uses the reader window and shares account cursors',
    () async {
      final subject = fixtures.build(
        currentUser: fixtures.currentUser,
        channels: {
          fixtures.site: ChatChannels(
            public: [fixtures.channel(9, lastRead: 0, unread: 8)],
            direct: const [],
          ),
        },
        messages: {
          '9': fixtures.page([fixtures.message(100)]),
          '9~target~42': fixtures.page([
            fixtures.message(42),
          ], canLoadMoreFuture: true),
        },
      );
      addTearDown(subject.chat.dispose);
      await subject.chat.loadChannels(fixtures.site);
      final latest = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'latest',
      );
      final history = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'history',
      );
      addTearDown(latest.dispose);
      addTearDown(history.dispose);
      latest.beginViewing();
      history.beginViewing();
      await latest.open();
      await history.open(targetMessageId: 42, force: true);
      await history.markRead(42);
      expect(
        subject.chat.channel(fixtures.site, 9)!.tracking.unreadCount,
        greaterThan(0),
      );
      await latest.markRead(100);
      expect(subject.chat.channel(fixtures.site, 9)!.tracking.unreadCount, 0);
      await history.markRead(42);
      expect(subject.api.chatReadsMarked.map((r) => r.messageId), [42, 100]);
    },
  );

  test(
    'one optimistic send is shared by readers and reconciles once',
    () async {
      final gate = Completer<void>();
      final subject = fixtures.build(
        currentUser: const DiscourseUser(id: 7, username: 'reader'),
        channels: {
          fixtures.site: ChatChannels(
            public: [fixtures.channel(9)],
            direct: const [],
            newMessageBusLastIds: const {9: 70},
            kickMessageBusLastIds: const {9: 72},
          ),
        },
        messages: {
          '9': fixtures.page([fixtures.message(100)]),
        },
        sendGate: gate,
        sentMessageId: 101,
      );
      addTearDown(subject.chat.dispose);
      final tracker = fixtures.attachTracker(subject.chat);
      await subject.chat.loadChannels(fixtures.site);
      final first = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'first',
      );
      final second = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'second',
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      first.beginViewing();
      second.beginViewing();
      await first.open();
      await second.open();
      final send = subject.chat.sendMessage(
        fixtures.site,
        9,
        OutgoingChatMessage.text('hello'),
      )!;
      expect(first.stream.localMessageIds, [send.localId]);
      expect(second.stream.localMessageIds, [send.localId]);
      expect(first.messages.last, same(second.messages.last));
      gate.complete();
      await send.settled;
      tracker.deliverPluginMessage(
        '/chat/9',
        fixtures.sentEvent(stagedId: send.stagedId, serverId: 101),
      );
      expect(first.stream.localMessageIds, isEmpty);
      expect(second.stream.localMessageIds, isEmpty);
      expect(first.stream.messageIds.where((id) => id == 101), hasLength(1));
      expect(second.stream.messageIds.where((id) => id == 101), hasLength(1));
    },
  );
  test(
    'a scoped page confirms a send before POST without moving historical readers',
    () async {
      final gate = Completer<void>();
      final now = DateTime.utc(2026, 5, 5, 10, 1);
      final pages = {
        '9': fixtures.page([fixtures.message(100)]),
        '9~target~42': fixtures.page([
          fixtures.message(42),
        ], canLoadMoreFuture: true),
      };
      final subject = fixtures.build(
        currentUser: const DiscourseUser(id: 7, username: 'reader'),
        channels: {
          fixtures.site: ChatChannels(
            public: [fixtures.channel(9)],
            direct: const [],
          ),
        },
        messages: pages,
        sendGate: gate,
        sentMessageId: 101,
        clock: () => now,
      );
      addTearDown(subject.chat.dispose);
      const target = ChatChannelTarget(9);
      final first = subject.chat.acquireReader(
        fixtures.site,
        target,
        readerId: 'first',
      );
      final second = subject.chat.acquireReader(
        fixtures.site,
        target,
        readerId: 'second',
      );
      final history = subject.chat.acquireReader(
        fixtures.site,
        target,
        readerId: 'history',
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(history.dispose);
      await subject.chat.loadChannels(fixtures.site);
      await first.open();
      await second.open();
      await history.open(targetMessageId: 42, force: true);
      final send = subject.chat.sendMessage(
        fixtures.site,
        9,
        OutgoingChatMessage.text('hello'),
      )!;
      final canonical = ChatMessage(
        id: 101,
        channelId: 9,
        raw: 'hello',
        cooked: '<p>hello</p>',
        author: const ChatMessageAuthor(id: 7, username: 'reader'),
        createdAt: now,
      );
      pages['9'] = fixtures.page([fixtures.message(100), canonical]);
      await second.open(force: true);
      expect(first.stream.messageIds, [100, 101]);
      expect(first.stream.localMessageIds, isEmpty);
      expect(second.stream.localMessageIds, isEmpty);
      expect(
        subject.chat.streamFor(fixtures.site, target).localMessageIds,
        isEmpty,
      );
      expect(history.stream.messageIds, [42]);
      expect(history.stream.localMessageIds, [send.localId]);
      expect(history.messages.last.canonicalReceived, isTrue);
      expect(history.messages.last.serverId, 101);
      expect(history.stream.pendingNewMessages, 1);
      pages['9~future~42'] = fixtures.page([canonical]);
      await history.loadNewer();
      expect(history.stream.messageIds, [42, 101]);
      expect(history.stream.localMessageIds, isEmpty);
      gate.complete();
      await send.settled;
      expect(first.stream.messageIds.where((id) => id == 101), hasLength(1));
    },
  );

  for (final terminal in [false, true]) {
    test(
      'thread metadata failure terminal=$terminal reaches each reader without replacing its window',
      () async {
        final api = _ThreadDetailApi();
        final subject = fixtures.build(api: api);
        addTearDown(subject.chat.dispose);
        final source = subject.chat.acquireReader(
          fixtures.site,
          threads.target,
          readerId: 'source',
        );
        final destination = subject.chat.acquireReader(
          fixtures.site,
          threads.target,
          readerId: 'destination',
        );
        final empty = subject.chat.acquireReader(
          fixtures.site,
          threads.target,
          readerId: 'empty',
        );
        addTearDown(source.dispose);
        addTearDown(destination.dispose);
        addTearDown(empty.dispose);
        await source.open();
        await destination.open(targetMessageId: 42, force: true);
        final sourceWindow = source.stream;
        final destinationWindow = destination.stream;
        api.detailFailure = SiteLookupException(
          SiteLookupFailure.unreachable,
          fixtures.site,
          statusCode: terminal ? 404 : 503,
        );
        await empty.open(force: true);
        expect(empty.stream.fetchedOnce, isTrue);
        expect(empty.stream.error, isNotNull);
        for (final reader in [source, destination, empty]) {
          expect(reader.stream.threadUnavailable, terminal);
        }
        expect(
          source.stream.messageIds,
          orderedEquals(sourceWindow.messageIds),
        );
        expect(source.stream.fetches, sourceWindow.fetches);
        expect(source.stream.anchorMessageId, sourceWindow.anchorMessageId);
        expect(
          destination.stream.messageIds,
          orderedEquals(destinationWindow.messageIds),
        );
        expect(destination.stream.fetches, destinationWindow.fetches);
        expect(
          destination.stream.anchorMessageId,
          destinationWindow.anchorMessageId,
        );
        api.detailFailure = null;
        await subject.chat.refreshThreadDetail(fixtures.site, threads.target);
        for (final reader in [source, destination, empty]) {
          expect(reader.stream.threadUnavailable, isFalse);
          expect(reader.stream.error, isNull);
        }
      },
    );
  }

  test(
    'a cached canonical arrival reaches missing reader windows and held replays stay quiet',
    () async {
      final subject = fixtures.build(
        currentUser: fixtures.currentUser,
        channels: {
          fixtures.site: ChatChannels(public: [fixtures.channel(9)]),
        },
        messages: {
          '9': fixtures.page([fixtures.message(100)]),
          '9~target~42': fixtures.page([
            fixtures.message(42),
          ], canLoadMoreFuture: true),
        },
      );
      addTearDown(subject.chat.dispose);
      final tracker = fixtures.attachTracker(subject.chat);
      await subject.chat.loadChannels(fixtures.site);
      await subject.chat.openChannel(fixtures.site, 9);
      final history = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'history',
      );
      addTearDown(history.dispose);
      history.beginViewing();
      await history.open(targetMessageId: 42, force: true);
      Map<String, dynamic> event(int id) => {
        'type': 'sent',
        'chat_message': {
          'id': id,
          'chat_channel_id': 9,
          'cooked': '<p>$id</p>',
          'created_at': '2026-05-05T10:01:00.000Z',
          'user': {'id': 2, 'username': 'sam'},
        },
      };
      tracker.deliverPluginMessage('/chat/9', event(100));
      expect(history.stream.pendingNewMessages, 1);
      tracker.deliverPluginMessage('/chat/9', event(42));
      expect(history.stream.pendingNewMessages, 1);
      expect(history.stream.messageIds, [42]);
    },
  );

  test(
    'a reader GET invalidates shared grouping while preserving another window',
    () async {
      final pages = {
        '9': fixtures.page([fixtures.message(100), fixtures.message(101)]),
      };
      final subject = fixtures.build(messages: pages);
      addTearDown(subject.chat.dispose);
      final source = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'source',
      );
      final destination = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'destination',
      );
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await source.open();
      await destination.open();
      final held = source.stream;
      pages['9'] = fixtures.page([
        fixtures.message(100, authorId: 3),
        fixtures.message(101),
      ]);
      await destination.open(force: true);
      expect(source.stream.messageIds, same(held.messageIds));
      expect(source.stream.fetches, held.fetches);
      expect(source.stream.anchorMessageId, held.anchorMessageId);
      expect(source.stream.revision, greaterThan(held.revision));
      expect(source.messages.first.author.id, 3);
      expect(source.messages.first, same(destination.messages.first));
    },
  );

  test(
    'retiring one reader releases only its pins and retired handles cannot reacquire live claims',
    () async {
      final store = Store(
        policy: const StorePolicy(maxEntries: 20, maxEntriesPerSiteAndType: 2),
      );
      final subject = fixtures.build(
        store: store,
        currentUser: fixtures.currentUser,
        channels: {
          fixtures.site: ChatChannels(public: [fixtures.channel(9)]),
        },
        messages: {
          '9': fixtures.page([fixtures.message(100), fixtures.message(101)]),
        },
      );
      addTearDown(subject.chat.dispose);
      final tracker = fixtures.attachTracker(subject.chat);
      await subject.chat.loadChannels(fixtures.site);
      final source = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'source',
      );
      final destination = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'destination',
      );
      source.beginViewing();
      destination.beginViewing();
      await source.open();
      await destination.open();
      source.dispose();
      for (var id = 200; id < 210; id++) {
        store.put(fixtures.site, fixtures.message(id));
      }
      expect(destination.messages.map((m) => m.id), [100, 101]);
      expect(tracker.pluginChannelCallbacks['/chat/9'], isNotEmpty);
      destination.dispose();
      expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      source.beginViewing();
      expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      for (var id = 300; id < 310; id++) {
        store.put(fixtures.site, fixtures.message(id));
      }
      expect(store.read<ChatMessage>(fixtures.site, 100), isNull);
      expect(store.read<ChatMessage>(fixtures.site, 101), isNull);
    },
  );
  test(
    'accepted edits and deletions update every reader sharing the record',
    () async {
      final subject = fixtures.build(
        currentUser: fixtures.currentUser,
        channels: {
          fixtures.site: ChatChannels(
            public: [fixtures.channel(9, canDeleteSelf: true)],
          ),
        },
        messages: {
          '9': fixtures.page([fixtures.message(100, authorId: 7)]),
        },
      );
      addTearDown(subject.chat.dispose);
      await subject.chat.loadChannels(fixtures.site);
      final source = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'source',
      );
      final destination = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'destination',
      );
      addTearDown(source.dispose);
      addTearDown(destination.dispose);
      await source.open();
      await destination.open();
      final sourceWindow = source.stream;
      final destinationWindow = destination.stream;
      expect(
        await subject.chat.editMessage(fixtures.site, 100, 'Accepted edit'),
        isNull,
      );
      expect(source.messages.single.raw, 'Accepted edit');
      expect(source.messages.single, same(destination.messages.single));
      expect(await subject.chat.deleteMessage(fixtures.site, 100), isNull);
      expect(source.messages.single.isDeleted, isTrue);
      expect(source.messages.single, same(destination.messages.single));
      expect(source.stream.messageIds, same(sourceWindow.messageIds));
      expect(destination.stream.messageIds, same(destinationWindow.messageIds));
      expect(source.stream.revision, greaterThan(sourceWindow.revision));
      expect(
        destination.stream.revision,
        greaterThan(destinationWindow.revision),
      );
    },
  );
}

final class _ThreadDetailApi extends FakeDiscourseApi {
  _ThreadDetailApi()
    : super(
        chatThreadsByKey: {
          FakeDiscourseApi.chatThreadKey(9, 22): threads.threadDetail(),
        },
        chatMessagesByKey: {
          'thread-9-22': fixtures.page([fixtures.message(100)]),
          'thread-9-22~target~42': fixtures.page([
            fixtures.message(42),
          ], canLoadMoreFuture: true),
        },
      );
  Object? detailFailure;
  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) {
    if (detailFailure case final error?) throw error;
    return super.chatThread(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
