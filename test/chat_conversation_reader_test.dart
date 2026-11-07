import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_conversation.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;
import 'chat_thread_controller_test.dart' as threads;
import 'support/fakes.dart';

void main() {
  test(
    'a remounted thread reader owns its open while previous metadata is pending',
    () async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        chatThreadGate: gate,
        chatThreadsByKey: {
          FakeDiscourseApi.chatThreadKey(9, 22): threads.threadDetail(),
        },
        chatMessagesByKey: {
          'thread-9-22': fixtures.page([threads.threadMessage(100)]),
        },
      );
      final subject = fixtures.build(
        api: api,
        clock: () => DateTime.utc(2026, 11, 7),
      );
      addTearDown(subject.chat.dispose);
      final previous = subject.chat.acquireReader(
        fixtures.site,
        threads.target,
        readerId: 'tab',
      );
      final opening = previous.open();
      await Future<void>.delayed(Duration.zero);
      expect(api.chatThreadsRequested, hasLength(1));
      previous.dispose();
      final replacement = subject.chat.acquireReader(
        fixtures.site,
        threads.target,
        readerId: 'tab',
      );
      addTearDown(replacement.dispose);
      final reopening = replacement.open();
      gate.complete();
      await Future.wait([opening, reopening]);
      expect(replacement.stream.fetchedOnce, isTrue);
      expect(replacement.messages.map((message) => message.id), [100]);
    },
  );

  test(
    'passive reader caches release pins and queued arrivals do not defeat the LRU budget',
    () async {
      final subject = fixtures.build(
        channels: {
          fixtures.site: ChatChannels(
            public: [fixtures.channel(9), fixtures.channel(10)],
          ),
        },
        messages: {
          '9': fixtures.page([fixtures.message(100)], canLoadMoreFuture: true),
          '10': fixtures.page([
            const ChatMessage(
              id: 200,
              channelId: 10,
              cooked: '<p>200</p>',
              author: ChatMessageAuthor(id: 2, username: 'sam'),
            ),
          ]),
        },
        maxRetainedCanonicalMessageIdsPerSite: 50,
        clock: () => DateTime.utc(2026, 11, 7),
      );
      addTearDown(subject.chat.dispose);
      final tracker = fixtures.attachTracker(subject.chat);
      await subject.chat.loadChannels(fixtures.site);
      final source = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'tab',
      );
      source.beginViewing();
      await source.open();
      tracker.deliverPluginMessage('/chat/9', {
        'type': 'sent',
        'chat_message': {
          'id': 101,
          'chat_channel_id': 9,
          'cooked': '<p>New arrival</p>',
          'user': {'id': 2, 'username': 'sam'},
        },
      });
      expect(source.stream.pendingNewMessages, 1);
      source.dispose();
      expect(source.isCurrent, isFalse);
      expect(subject.chat.pinnedMessageCountForTesting(fixtures.site), 0);
      final cached = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'tab',
      );
      expect(cached.stream.messageIds, [100]);
      expect(cached.stream.pendingNewMessages, 1);
      await cached.open();
      expect(subject.api.chatMessagesRequested, hasLength(1));
      cached.dispose();
      final next = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(10),
        readerId: 'another-tab',
      );
      addTearDown(next.dispose);
      next.beginViewing();
      await next.open();
      final evicted = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'tab',
      );
      addTearDown(evicted.dispose);
      expect(evicted.stream.fetchedOnce, isFalse);
      expect(evicted.stream.messageIds, isEmpty);
    },
  );

  test(
    'disposing a hidden reader releases its local pins while the default send owner survives',
    () async {
      final gate = Completer<void>();
      final subject = fixtures.build(
        currentUser: const DiscourseUser(id: 7, username: 'reader'),
        channels: {
          fixtures.site: ChatChannels(
            public: [fixtures.channel(9), fixtures.channel(10)],
          ),
        },
        messages: {
          '9': fixtures.page([fixtures.message(100)]),
          '10': fixtures.page([
            const ChatMessage(
              id: 200,
              channelId: 10,
              cooked: '<p>200</p>',
              author: ChatMessageAuthor(id: 2, username: 'sam'),
            ),
          ]),
        },
        sendGate: gate,
        sentMessageId: 101,
        maxRetainedCanonicalMessageIdsPerSite: 100,
      );
      addTearDown(subject.chat.dispose);
      await subject.chat.loadChannels(fixtures.site);
      final source = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'tab',
      );
      final view = source.beginViewing();
      await source.open();
      final send = subject.chat.sendMessage(
        fixtures.site,
        9,
        OutgoingChatMessage.text('Pending send'),
      )!;
      source.endViewing(view);
      expect(subject.chat.pinnedMessageCountForTesting(fixtures.site), 2);
      source.dispose();
      expect(subject.chat.pinnedMessageCountForTesting(fixtures.site), 1);
      expect(subject.chat.stream(fixtures.site, 9).localMessageIds, [
        send.localId,
      ]);
      expect(
        subject.store.read<ChatMessage>(fixtures.site, send.localId),
        isNotNull,
      );
      await subject.chat.openChannel(fixtures.site, 10);
      final reopened = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'tab',
      );
      addTearDown(reopened.dispose);
      expect(reopened.stream.messageIds, isEmpty);
      expect(reopened.stream.localMessageIds, [send.localId]);
      gate.complete();
      await send.settled;
      expect(
        subject.store.read<ChatMessage>(fixtures.site, send.localId)?.delivery,
        ChatMessageDelivery.sent,
      );
    },
  );

  test(
    'forgetting an account clears passive reader windows before reacquisition',
    () async {
      final subject = fixtures.build(
        messages: {
          '9': fixtures.page([fixtures.message(100)]),
        },
      );
      addTearDown(subject.chat.dispose);
      final source = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'tab',
      );
      await source.open();
      source.dispose();
      subject.chat.forget(fixtures.site);
      final replacement = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'tab',
      );
      addTearDown(replacement.dispose);
      expect(replacement.stream.fetchedOnce, isFalse);
      expect(replacement.messages, isEmpty);
    },
  );

  for (final target in <ChatStreamTarget>[
    const ChatChannelTarget(9),
    threads.target,
  ]) {
    test(
      '${target.storageKey} reader retains parked arrivals independently of its seed owner',
      () async {
        final threaded = target is ChatThreadTarget;
        ChatMessagePage page(
          List<int> ids, {
          bool past = false,
          bool future = false,
        }) => (
          messages: [
            for (final id in ids)
              threaded ? threads.threadMessage(id) : fixtures.message(id),
          ],
          canLoadMorePast: past,
          canLoadMoreFuture: future,
          targetMessageId: null,
        );
        final base = threaded ? 'thread-9-22' : '9';
        final api = FakeDiscourseApi(
          chatChannelsBySite: {
            fixtures.site: ChatChannels(public: [fixtures.channel(9)]),
          },
          chatThreadsByKey: {
            FakeDiscourseApi.chatThreadKey(9, 22): threads.threadDetail(),
          },
          chatMessagesByKey: {
            base: page([100, 101], past: true),
            '$base~past~100': page([98, 99]),
            '$base~future~99': page([100, 101], future: true),
            '$base~future~101': page([102]),
          },
        );
        final subject = fixtures.build(
          api: api,
          maxRetainedCanonicalMessageIdsPerSite: 2,
          clock: () => DateTime.utc(2026, 8, 12, 12),
        );
        addTearDown(subject.chat.dispose);
        final tracker = fixtures.attachTracker(subject.chat);
        await subject.chat.loadChannels(fixtures.site);
        final conversation = threaded
            ? ChatControllerConversationCapability(
                subject.chat,
              ).openThread(siteUrl: fixtures.site, channelId: 9, threadId: 22)
            : null;
        if (conversation != null) {
          await conversation.refresh();
          await conversation.loadOlder();
        } else {
          final viewing = subject.chat.beginViewingChannel(fixtures.site, 9);
          addTearDown(
            () => subject.chat.endViewingChannel(fixtures.site, 9, viewing),
          );
          await subject.chat.openChannel(fixtures.site, 9);
          await subject.chat.loadOlderFor(fixtures.site, target);
        }
        expect(subject.chat.streamFor(fixtures.site, target).messageIds, [
          98,
          99,
        ]);
        expect(
          subject.chat.streamFor(fixtures.site, target).canLoadMoreFuture,
          isTrue,
        );
        void arrive(int id) => tracker.deliverPluginMessage(
          threaded ? '/chat/9/thread/22' : '/chat/9',
          threaded
              ? threads.threadSentEvent(id)
              : {
                  'type': 'sent',
                  'chat_message': {
                    'id': id,
                    'chat_channel_id': 9,
                    'cooked': '<p>$id live</p>',
                    'created_at': '2026-08-12T12:00:00.000Z',
                    'user': {'id': 2, 'username': 'sam'},
                  },
                },
        );
        arrive(102);
        arrive(103);
        expect(
          subject.chat.streamFor(fixtures.site, target).pendingNewMessages,
          2,
        );
        conversation?.close();
        final reader = subject.chat.acquireReader(
          fixtures.site,
          target,
          readerId: 'handoff',
        );
        addTearDown(reader.dispose);
        reader.beginViewing();
        await reader.open();
        expect(reader.stream.pendingNewMessages, 2);
        final latest = subject.chat.acquireReader(
          fixtures.site,
          target,
          readerId: 'latest',
        );
        addTearDown(latest.dispose);
        latest.beginViewing();
        await latest.open();
        await latest.showLatest();
        expect(latest.stream.pendingNewMessages, 0);
        expect(latest.stream.messageIds, [102, 103]);
        expect(reader.stream.pendingNewMessages, 2);
        expect(
          subject.chat.streamFor(fixtures.site, target).pendingNewMessages,
          2,
        );
        arrive(103);
        expect(reader.stream.pendingNewMessages, 2);
        arrive(104);
        expect(reader.stream.pendingNewMessages, 3);
        expect(reader.stream.messageIds, [98, 99]);

        await subject.chat.loadNewerFor(fixtures.site, target);
        await subject.chat.loadNewerFor(fixtures.site, target);
        expect(
          subject.chat.streamFor(fixtures.site, target).pendingNewMessages,
          0,
        );
        expect(reader.stream.pendingNewMessages, 3);
        arrive(105);
        expect(reader.stream.pendingNewMessages, 4);
        await reader.loadNewer();
        await reader.loadNewer();
        expect(reader.stream.pendingNewMessages, 0);
        expect(reader.stream.messageIds, [104, 105]);
      },
    );
  }

  for (final target in <ChatStreamTarget>[
    const ChatChannelTarget(9),
    threads.target,
  ]) {
    for (final older in [true, false]) {
      test(
        '${target.storageKey} reader does not inherit pending ${older ? 'older' : 'newer'} paging',
        () async {
          final api = _SeedPagingApi();
          final subject = fixtures.build(api: api);
          addTearDown(subject.chat.dispose);
          await subject.chat.loadChannels(fixtures.site);
          final conversation = target is ChatThreadTarget
              ? ChatControllerConversationCapability(
                  subject.chat,
                ).openThread(siteUrl: fixtures.site, channelId: 9, threadId: 22)
              : null;
          if (conversation != null) {
            await conversation.refresh();
          } else {
            await subject.chat.openChannel(fixtures.site, 9);
          }
          final gate = Completer<void>();
          api.directionalGate = gate;
          final pending = older
              ? conversation?.loadOlder() ??
                    subject.chat.loadOlderFor(fixtures.site, target)
              : subject.chat.loadNewerFor(fixtures.site, target);
          conversation?.close();
          final held = subject.chat.streamFor(fixtures.site, target);
          expect(older ? held.loadingOlder : held.loadingNewer, isTrue);
          final reader = subject.chat.acquireReader(
            fixtures.site,
            target,
            readerId: 'new-tab',
          );
          addTearDown(reader.dispose);
          await reader.open();
          gate.complete();
          await pending;
          expect(
            subject.chat.streamFor(fixtures.site, target).messageIds,
            older ? [99, 100, 101] : [100, 101, 102],
          );
          expect(reader.stream.messageIds, [100, 101]);
          expect(reader.stream.loadingOlder, isFalse);
          expect(reader.stream.loadingNewer, isFalse);
          if (older) {
            await reader.loadOlder();
            expect(reader.stream.messageIds, [99, 100, 101]);
          } else {
            await reader.loadNewer();
            expect(reader.stream.messageIds, [100, 101, 102]);
          }
        },
      );
    }
  }

  testWidgets(
    'a new reader does not retain another owner notice after its timer expires',
    (tester) async {
      final subject = fixtures.build(
        messages: {
          '9': fixtures.page([fixtures.message(100)]),
        },
      );
      addTearDown(subject.chat.dispose);
      subject.store.put(fixtures.site, fixtures.channel(9));
      final tracker = fixtures.attachTracker(subject.chat);
      await subject.chat.openChannel(fixtures.site, 9);
      final view = subject.chat.beginViewingChannel(fixtures.site, 9);
      addTearDown(() => subject.chat.endViewingChannel(fixtures.site, 9, view));
      tracker.deliverPluginMessage('/chat/9', {
        'type': 'notice',
        'channel_id': 9,
        'text_content': 'Some mentioned users cannot see this channel.',
      });
      expect(subject.chat.stream(fixtures.site, 9).notice, isNotNull);
      final reader = subject.chat.acquireReader(
        fixtures.site,
        const ChatChannelTarget(9),
        readerId: 'new-tab',
      );
      addTearDown(reader.dispose);
      await reader.open();
      await tester.pump(const Duration(seconds: 4));
      expect(subject.chat.stream(fixtures.site, 9).notice, isNull);
      expect(reader.stream.notice, isNull);
      expect(reader.stream.messageIds, [100]);
    },
  );
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

final class _SeedPagingApi extends FakeDiscourseApi {
  _SeedPagingApi()
    : super(
        chatChannelsBySite: {
          fixtures.site: ChatChannels(public: [fixtures.channel(9)]),
        },
        chatThreadsByKey: {
          FakeDiscourseApi.chatThreadKey(9, 22): threads.threadDetail(),
        },
        chatMessagesByKey: {
          for (final base in ['9', 'thread-9-22']) ...{
            base: fixtures.page(
              [fixtures.message(100), fixtures.message(101)],
              canLoadMorePast: true,
              canLoadMoreFuture: true,
            ),
            '$base~past~100': fixtures.page([fixtures.message(99)]),
            '$base~future~101': fixtures.page([fixtures.message(102)]),
          },
        },
      );

  Completer<void>? directionalGate;

  @override
  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    if (before != null || after != null) await directionalGate?.future;
    return super.chatMessages(
      siteUrl: siteUrl,
      channelId: channelId,
      before: before,
      after: after,
      targetMessageId: targetMessageId,
      fromLastRead: fromLastRead,
      pageSize: pageSize,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<ChatMessagePage> chatThreadMessages({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? before,
    int? after,
    int? targetMessageId,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    if (before != null || after != null) await directionalGate?.future;
    return super.chatThreadMessages(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
      before: before,
      after: after,
      targetMessageId: targetMessageId,
      pageSize: pageSize,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
