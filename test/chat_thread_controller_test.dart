import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const site = 'https://meta.discourse.org';
const target = ChatThreadTarget(channelId: 9, threadId: 22);
const currentUser = DiscourseUser(id: 7, username: 'reader', name: 'Reader');

ChatThread threadDetail({
  bool withMembership = true,
  int replyCount = 3,
  int? messageBusLastId = 701,
  int? lastMessageId = 40,
  String status = 'open',
  String? title,
  bool force = false,
  ChatThreadPreview? preview,
  int originalAuthorId = 2,
}) => ChatThread(
  id: target.threadId,
  channelId: target.channelId,
  status: status,
  replyCount: replyCount,
  title: title,
  messageBusLastId: messageBusLastId,
  lastMessageId: lastMessageId,
  force: force,
  preview: preview,
  membership: withMembership
      ? const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.tracking,
          lastReadMessageId: 17,
        )
      : null,
  originalMessage: ChatThreadOriginalMessage(
    id: 100,
    channelId: 9,
    author: ChatMessageAuthor(id: originalAuthorId, username: 'sam'),
    message: 'Original',
    cooked: '<p>Original</p>',
    excerpt: 'Original',
  ),
);

ChatThread listedThread(
  int id, {
  int? originalMessageId,
  DateTime? lastReplyAt,
  DateTime? deletedAt,
  ChatTracking tracking = ChatTracking.none,
  ChatThreadMembership? membership,
  bool hasReplies = true,
}) {
  final originalId = originalMessageId ?? id * 10;
  final lastMessageId = hasReplies ? originalId + 1 : originalId;
  return ChatThread(
    id: id,
    channelId: 9,
    status: 'open',
    replyCount: hasReplies ? 1 : 0,
    title: 'Thread $id',
    tracking: tracking,
    membership: membership,
    lastMessageId: lastMessageId,
    preview: ChatThreadPreview(
      threadId: id,
      replyCount: hasReplies ? 1 : 0,
      lastReplyId: lastMessageId,
      lastReplyAt: lastReplyAt,
      lastReplyExcerpt: 'Reply $id',
    ),
    originalMessage: ChatThreadOriginalMessage(
      id: originalId,
      channelId: 9,
      author: const ChatMessageAuthor(id: 2, username: 'sam'),
      excerpt: 'Original $id',
      deletedAt: deletedAt,
    ),
  );
}

ChatMessage threadMessage(int id) => ChatMessage(
  id: id,
  channelId: target.channelId,
  threadId: target.threadId,
  cooked: '<p>$id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: DateTime.utc(2026, 8, 12).add(Duration(seconds: id)),
);

ChatMessagePage threadPage(
  List<int> ids, {
  bool canLoadMorePast = false,
  bool canLoadMoreFuture = false,
  int? targetMessageId,
}) => (
  messages: [for (final id in ids) threadMessage(id)],
  canLoadMorePast: canLoadMorePast,
  canLoadMoreFuture: canLoadMoreFuture,
  targetMessageId: targetMessageId,
);

ChatChannel followedChannel({
  bool threadingEnabled = true,
  ChatMembership membership = const ChatMembership(
    following: true,
    lastReadMessageId: 10,
  ),
  ChatChannelStatus status = ChatChannelStatus.open,
}) => ChatChannel(
  id: 9,
  title: 'Support',
  kind: ChatChannelKind.category,
  membership: membership,
  status: status,
  threadingEnabled: threadingEnabled,
);

Future<void> waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true.');
}

Map<String, dynamic> threadSentEvent(int id) => {
  'type': 'sent',
  'chat_message': {
    'id': id,
    'chat_channel_id': target.channelId,
    'thread_id': target.threadId,
    'cooked': '<p>$id live</p>',
    'created_at': '2026-08-12T12:00:00.000Z',
    'user': {'id': 2, 'username': 'sam'},
  },
};

Map<String, dynamic> authoritativePreviewEvent({int replyCount = 4}) => {
  'type': 'update_thread_original_message',
  'original_message_id': 100,
  'thread_id': target.threadId,
  'preview': {
    'reply_count': replyCount,
    'last_reply_id': 104,
    'last_reply_created_at': '2026-08-12T12:00:00.000Z',
    'last_reply_excerpt': 'Authoritative',
    'last_reply_user': {'id': 3, 'username': 'lee'},
    'participant_count': 2,
    'participant_users': [
      {'id': 2, 'username': 'sam'},
      {'id': 3, 'username': 'lee'},
    ],
  },
};

final class _AdversarialThreadApi extends FakeDiscourseApi {
  _AdversarialThreadApi({
    required ChatThread detail,
    Map<String, ChatMessagePage> pages = const {},
    Map<String, ChatChannels> channels = const {},
    bool holdDetail = false,
    bool holdMessages = false,
    this.missingTargetMessageId,
    this.detailFailure,
    this.targetMessageGates = const {},
    this.targetMessageStarts = const {},
    int? sentMessageId = 900,
  }) : super(
         chatThreadsByKey: {
           FakeDiscourseApi.chatThreadKey(target.channelId, target.threadId):
               detail,
         },
         chatMessagesByKey: pages,
         chatChannelsBySite: channels,
         chatSentMessageId: sentMessageId,
       ) {
    if (holdDetail) {
      detailStarted = Completer<void>();
      detailGate = Completer<void>();
    }
    if (holdMessages) {
      messagesStarted = Completer<void>();
      messagesGate = Completer<void>();
    }
  }

  final List<String> callOrder = [];
  final List<({int channelId, int threadId, int messageId})> threadReads = [];
  Completer<void>? detailStarted;
  Completer<void>? detailGate;
  Completer<void>? messagesStarted;
  Completer<void>? messagesGate;
  Completer<void>? notificationStarted;
  Completer<void>? notificationGate;
  Object? notificationFailure;
  ChatThreadMembership? notificationResponse;
  final int? missingTargetMessageId;
  final Object? detailFailure;
  final Map<int, Completer<void>> targetMessageGates;
  final Map<int, Completer<void>> targetMessageStarts;

  void holdNotification({Object? failure, ChatThreadMembership? response}) {
    notificationStarted = Completer<void>();
    notificationGate = Completer<void>();
    notificationFailure = failure;
    notificationResponse = response;
  }

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) async {
    callOrder.add('detail');
    final started = detailStarted;
    if (started != null && !started.isCompleted) started.complete();
    await detailGate?.future;
    if (detailFailure case final failure?) throw failure;
    return super.chatThread(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: threadId,
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
    callOrder.add('messages');
    final started = messagesStarted;
    if (started != null && !started.isCompleted) started.complete();
    final targetStarted = targetMessageId == null
        ? null
        : targetMessageStarts[targetMessageId];
    if (targetStarted != null && !targetStarted.isCompleted) {
      targetStarted.complete();
    }
    if (targetMessageId != null) {
      await targetMessageGates[targetMessageId]?.future;
    }
    await messagesGate?.future;
    final page = await super.chatThreadMessages(
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
    if (missingTargetMessageId != null &&
        targetMessageId == missingTargetMessageId) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        statusCode: 404,
      );
    }
    return page;
  }

  @override
  Future<void> markChatThreadRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required int messageId,
    String? clientId,
  }) async {
    threadReads.add((
      channelId: channelId,
      threadId: threadId,
      messageId: messageId,
    ));
  }

  @override
  Future<ChatThreadMembership> updateChatThreadNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required ChatThreadNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    chatThreadNotificationLevelsUpdated.add((
      channelId: channelId,
      threadId: threadId,
      notificationLevel: notificationLevel,
    ));
    final started = notificationStarted;
    if (started != null && !started.isCompleted) started.complete();
    await notificationGate?.future;
    if (notificationFailure case final failure?) throw failure;
    return notificationResponse ??
        ChatThreadMembership(
          threadId: threadId,
          notificationLevel: notificationLevel,
        );
  }
}

final class _SequencedDetailApi extends FakeDiscourseApi {
  final List<Completer<ChatThread>> responses = [];
  int calls = 0;

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) {
    chatThreadsRequested.add((channelId: channelId, threadId: threadId));
    calls += 1;
    final response = Completer<ChatThread>();
    responses.add(response);
    return response.future;
  }
}

final class _PendingNotificationResponse {
  _PendingNotificationResponse(this.level);

  final ChatThreadNotificationLevel level;
  final Completer<ChatThreadMembership> response = Completer();
}

final class _SequencedNotificationApi extends FakeDiscourseApi {
  final List<_PendingNotificationResponse> pending = [];

  @override
  Future<ChatThreadMembership> updateChatThreadNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required ChatThreadNotificationLevel notificationLevel,
    String? clientId,
  }) {
    chatThreadNotificationLevelsUpdated.add((
      channelId: channelId,
      threadId: threadId,
      notificationLevel: notificationLevel,
    ));
    final request = _PendingNotificationResponse(notificationLevel);
    pending.add(request);
    return request.response.future;
  }
}

({ChatController chat, Store store}) _controllerFor(
  ChatApi api, {
  Store? store,
  DiscourseUser user = currentUser,
}) {
  final credentials = FakeApiCredentialReader()..keys[site] = 'key';
  final resolvedStore = store ?? Store();
  final chat = ChatController(
    api: api,
    credentials: credentials,
    store: resolvedStore,
    currentUserFor: (_) => user,
    minimumWindowRefreshInterval: Duration.zero,
    clock: () => DateTime.utc(2026, 8, 12, 12),
  );
  addTearDown(chat.dispose);
  return (chat: chat, store: resolvedStore);
}

FakeSiteTracker attachTracker(ChatController chat) {
  final tracker = FakeSiteTracker(
    siteUrl: site,
    onIncomingTopics: () {},
    onNotifications: (_) {},
    onReviewableCounts: (_) {},
    userId: currentUser.id,
    apiKey: 'key',
  );
  chat.attachTracker(site, tracker);
  return tracker;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('My Threads caches and appends core account pages', () async {
    final secondThread = threadDetail(
      replyCount: 1,
      title: 'Second thread',
    ).copyWith(lastMessageId: 80);
    final pageTwoThread = ChatThread(
      id: 23,
      channelId: 12,
      status: 'open',
      replyCount: secondThread.replyCount,
      title: secondThread.title,
      lastMessageId: secondThread.lastMessageId,
      originalMessage: const ChatThreadOriginalMessage(
        id: 200,
        channelId: 12,
        author: ChatMessageAuthor(id: 3, username: 'lee'),
        excerpt: 'Second original',
      ),
    );
    final api = FakeDiscourseApi(
      chatChannelsBySite: const {site: ChatChannels(hasThreads: true)},
      chatThreadPagesByOffset: {
        0: ChatThreadPage(
          threads: [threadDetail(title: 'Deploy plan')],
          channels: [followedChannel()],
          hasMore: true,
        ),
        1: ChatThreadPage(
          threads: [pageTwoThread],
          channels: const [
            ChatChannel(
              id: 12,
              title: 'Design',
              kind: ChatChannelKind.category,
            ),
          ],
        ),
      },
    );
    final subject = _controllerFor(api);

    await subject.chat.loadChannels(site);
    expect(subject.chat.hasThreads(site), isTrue);

    await subject.chat.loadMyThreads(site);
    await subject.chat.loadMyThreads(site);
    expect(api.chatThreadPagesRequested, [(offset: 0, limit: 10)]);
    expect(subject.chat.myThreads(site).map((thread) => thread.id), [22]);
    expect(subject.chat.channel(site, 9)?.title, 'Support');
    expect(subject.chat.myThreadsHaveMore(site), isTrue);

    await subject.chat.loadMyThreads(site, more: true);
    expect(api.chatThreadPagesRequested.last, (offset: 1, limit: 10));
    expect(subject.chat.myThreads(site).map((thread) => thread.id), [22, 23]);
    expect(subject.chat.channel(site, 12)?.title, 'Design');
    expect(subject.chat.myThreadsHaveMore(site), isFalse);
  });

  test('channel threads page, filter, and sort like the web list', () async {
    final api = FakeDiscourseApi(
      chatChannelsBySite: {
        site: ChatChannels(public: [followedChannel()]),
      },
      chatChannelThreadPagesByKey: {
        FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
          threads: [
            listedThread(1, lastReplyAt: DateTime.utc(2026, 8, 12, 11)),
            listedThread(
              2,
              lastReplyAt: DateTime.utc(2026, 8, 12, 9),
              tracking: const ChatTracking(unreadCount: 1),
            ),
            listedThread(
              3,
              lastReplyAt: DateTime.utc(2026, 8, 12, 8),
              tracking: const ChatTracking(watchedThreadsUnreadCount: 1),
            ),
            listedThread(4, hasReplies: false),
            listedThread(5, deletedAt: DateTime.utc(2026, 8, 12, 10)),
          ],
          hasMore: true,
        ),
        FakeDiscourseApi.chatChannelThreadPageKey(9, 5): ChatThreadPage(
          threads: [
            listedThread(6, lastReplyAt: DateTime.utc(2026, 8, 12, 12)),
          ],
        ),
      },
    );
    final subject = _controllerFor(api);

    await subject.chat.loadChannels(site);
    await subject.chat.loadChannelThreads(site, 9);
    await subject.chat.loadChannelThreads(site, 9);

    expect(api.chatChannelThreadPagesRequested, [
      (channelId: 9, offset: 0, limit: 10),
    ]);
    expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
      3,
      2,
      1,
    ]);
    expect(subject.chat.channelThreadsHaveMore(site, 9), isTrue);

    await subject.chat.loadChannelThreads(site, 9, more: true);

    expect(api.chatChannelThreadPagesRequested.last, (
      channelId: 9,
      offset: 5,
      limit: 10,
    ));
    expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
      3,
      2,
      6,
      1,
    ]);
    expect(subject.chat.channelThreadsHaveMore(site, 9), isFalse);
  });

  test(
    'live tracking, deletion, and restoration reproject channel threads',
    () async {
      final api = FakeDiscourseApi(
        chatChannelsBySite: {
          site: ChatChannels(public: [followedChannel()]),
        },
        chatChannelThreadPagesByKey: {
          FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
            threads: [
              listedThread(
                22,
                originalMessageId: 100,
                lastReplyAt: DateTime.utc(2026, 8, 12, 9),
                membership: const ChatThreadMembership(
                  threadId: 22,
                  notificationLevel: ChatThreadNotificationLevel.tracking,
                ),
              ),
              listedThread(
                23,
                originalMessageId: 200,
                lastReplyAt: DateTime.utc(2026, 8, 12, 11),
              ),
            ],
          ),
        },
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      await subject.chat.loadChannelThreads(site, 9);
      final view = subject.chat.beginViewingChannel(site, 9);
      addTearDown(() => subject.chat.endViewingChannel(site, 9, view));

      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        23,
        22,
      ]);

      tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
        'channel_id': 9,
        'thread_id': 22,
        'unread_count': 0,
        'mention_count': 0,
        'watched_threads_unread_count': 0,
        'thread_tracking': {'watched_threads_unread_count': 1},
      });
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        22,
        23,
      ]);

      tracker.deliverPluginMessage('/chat/9', {
        'type': 'delete',
        'deleted_id': 100,
        'deleted_at': '2026-08-12T12:00:00.000Z',
      });
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        23,
      ]);

      tracker.deliverPluginMessage('/chat/9', {
        'type': 'restore',
        'chat_message': {
          'id': 100,
          'chat_channel_id': 9,
          'thread_id': 22,
          'cooked': '<p>Original 22</p>',
          'created_at': '2026-08-12T08:00:00.000Z',
          'user': {'id': 2, 'username': 'sam'},
          'thread': {
            'id': 22,
            'reply_count': 1,
            'preview': {
              'last_reply_id': 221,
              'last_reply_created_at': '2026-08-12T09:00:00.000Z',
            },
          },
        },
      });
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        22,
        23,
      ]);
    },
  );

  test(
    'openThread waits for detail, stores its cursor, then targets messages',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(messageBusLastId: 701),
        holdDetail: true,
        pages: {
          'thread-9-22~target~21': threadPage(
            [20, 21, 22],
            canLoadMorePast: true,
            canLoadMoreFuture: true,
            targetMessageId: 20,
          ),
        },
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingThread(site, target);
      addTearDown(() => subject.chat.endViewingThread(site, target, view));

      final opening = subject.chat.openThread(
        site,
        target,
        targetMessageId: 21,
      );
      await api.detailStarted!.future;

      expect(api.callOrder, ['detail']);
      expect(api.chatThreadMessagesRequested, isEmpty);
      expect(
        tracker.pluginChannelCallbacks['/chat/9/thread/22'],
        anyOf(isNull, isEmpty),
      );

      api.detailGate!.complete();
      await opening;

      expect(api.callOrder, ['detail', 'messages']);
      expect(api.chatThreadMessagesRequested.single.targetMessageId, 21);
      expect(subject.chat.thread(site, 22)?.messageBusLastId, 701);
      expect(subject.chat.streamFor(site, target).messageIds, [20, 21, 22]);
      expect(subject.chat.streamFor(site, target).lastReadOnOpen, 17);
      expect(subject.chat.streamFor(site, target).anchorMessageId, 21);
      expect(tracker.pluginChannelLastIds['/chat/9/thread/22'], 701);
    },
  );

  test('thread history pages independently in both directions', () async {
    final api = _AdversarialThreadApi(
      detail: threadDetail(),
      pages: {
        'thread-9-22~target~20': threadPage(
          [20, 21],
          canLoadMorePast: true,
          canLoadMoreFuture: true,
          targetMessageId: 20,
        ),
        'thread-9-22~past~20': threadPage([10, 11]),
        'thread-9-22~future~21': threadPage([30, 31]),
      },
    );
    final subject = _controllerFor(api);

    await subject.chat.openThread(site, target, targetMessageId: 20);
    await subject.chat.loadOlderFor(site, target);
    await subject.chat.loadNewerFor(site, target);

    expect(
      api.chatThreadMessagesRequested.map(
        (request) => (
          before: request.before,
          after: request.after,
          targetMessageId: request.targetMessageId,
        ),
      ),
      [
        (before: null, after: null, targetMessageId: 20),
        (before: 20, after: null, targetMessageId: null),
        (before: null, after: 21, targetMessageId: null),
      ],
    );
    expect(subject.chat.streamFor(site, target).messageIds, [
      10,
      11,
      20,
      21,
      30,
      31,
    ]);
    expect(subject.chat.streamFor(site, target).canLoadMorePast, isFalse);
    expect(subject.chat.streamFor(site, target).canLoadMoreFuture, isFalse);
    expect(subject.chat.stream(site, target.channelId).messageIds, isEmpty);
  });

  test(
    'an unavailable exact target falls back to the default thread anchor',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        missingTargetMessageId: 999,
        pages: {
          'thread-9-22': threadPage([16, 17, 18], targetMessageId: 17),
        },
      );
      final subject = _controllerFor(api);

      await subject.chat.openThread(site, target, targetMessageId: 999);

      expect(
        api.chatThreadMessagesRequested.map(
          (request) => request.targetMessageId,
        ),
        [999, null],
      );
      final stream = subject.chat.streamFor(site, target);
      expect(stream.messageIds, [16, 17, 18]);
      expect(stream.anchorMessageId, 17);
      expect(stream.error, isNull);
      expect(
        stream.notice,
        'That message is unavailable. Showing the thread instead.',
      );
    },
  );

  test(
    'sendMessageTo posts the thread id and never enters the channel stream',
    () async {
      final api = _AdversarialThreadApi(detail: threadDetail());
      final store = Store()
        ..put(site, followedChannel())
        ..put(site, threadDetail());
      final subject = _controllerFor(api, store: store);

      final handle = subject.chat.sendMessageTo(
        site,
        target,
        OutgoingChatMessage.text('A threaded reply'),
      )!;

      expect(subject.chat.streamFor(site, target).localMessageIds, [
        handle.localId,
      ]);
      expect(
        subject.chat.stream(site, target.channelId).localMessageIds,
        isEmpty,
      );
      expect(
        subject.store.read<ChatMessage>(site, handle.localId)?.threadId,
        22,
      );
      expect(await handle.settled, ChatSendResult.sent);
      expect(api.chatMessagesSent.single.threadId, target.threadId);
      expect(api.chatMessagesSent.single.channelId, target.channelId);
      expect(subject.chat.stream(site, target.channelId).messageIds, isEmpty);
    },
  );

  test(
    'thread read receipts require membership and stay separate from channel reads',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(withMembership: false),
      );
      final store = Store()..put(site, threadDetail(withMembership: false));
      final subject = _controllerFor(api, store: store);

      await subject.chat.markReadFor(site, target, 30);
      expect(api.threadReads, isEmpty);

      subject.store.put(site, threadDetail(lastMessageId: 30));
      await subject.chat.markReadFor(site, target, 30);

      expect(api.threadReads, [(channelId: 9, threadId: 22, messageId: 30)]);
      expect(api.chatReadsMarked, isEmpty);
      expect(subject.chat.thread(site, 22)?.membership?.lastReadMessageId, 30);

      subject.store.put(site, followedChannel());
      await subject.chat.markReadFor(site, const ChatChannelTarget(9), 11);

      expect(api.chatReadsMarked, [(channelId: 9, messageId: 11)]);
      expect(api.threadReads, hasLength(1));
    },
  );

  test(
    'notification update is optimistic and commits the server membership',
    () async {
      final api = _AdversarialThreadApi(detail: threadDetail())
        ..holdNotification(
          response: const ChatThreadMembership(
            threadId: 22,
            notificationLevel: ChatThreadNotificationLevel.watching,
            lastReadMessageId: 17,
          ),
        );
      final store = Store()..put(site, threadDetail());
      final subject = _controllerFor(api, store: store);

      final updating = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.watching,
      );

      expect(
        subject.chat.thread(site, 22)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.watching,
      );
      await api.notificationStarted!.future;
      api.notificationGate!.complete();

      expect(await updating, isTrue);
      expect(
        subject.chat.thread(site, 22)?.membership,
        api.notificationResponse,
      );
    },
  );

  test('original author can update the thread title', () async {
    final api = _AdversarialThreadApi(
      detail: threadDetail(originalAuthorId: currentUser.id!),
    );
    final store = Store()
      ..put(site, threadDetail(originalAuthorId: currentUser.id!));
    final subject = _controllerFor(api, store: store);

    expect(
      subject.chat.canEditThreadTitle(
        site,
        subject.chat.thread(site, target.threadId),
      ),
      isTrue,
    );
    expect(
      await subject.chat.updateThreadTitle(site, target, 'Deploy plan'),
      isTrue,
    );

    expect(api.chatThreadTitlesUpdated, const [
      (channelId: 9, threadId: 22, title: 'Deploy plan'),
    ]);
    expect(subject.chat.thread(site, target.threadId)?.title, 'Deploy plan');
  });

  test('thread title updates are hidden from ordinary participants', () async {
    final api = _AdversarialThreadApi(detail: threadDetail());
    final store = Store()..put(site, threadDetail());
    final subject = _controllerFor(api, store: store);

    expect(
      subject.chat.canEditThreadTitle(
        site,
        subject.chat.thread(site, target.threadId),
      ),
      isFalse,
    );
    expect(
      await subject.chat.updateThreadTitle(site, target, 'Not mine'),
      isFalse,
    );
    expect(api.chatThreadTitlesUpdated, isEmpty);
    expect(subject.chat.thread(site, target.threadId)?.title, isNull);
  });

  test('staff can update another author\'s thread title', () async {
    final api = _AdversarialThreadApi(detail: threadDetail());
    final store = Store()..put(site, threadDetail());
    final subject = _controllerFor(
      api,
      store: store,
      user: const DiscourseUser(id: 7, username: 'moderator', staff: true),
    );

    expect(
      await subject.chat.updateThreadTitle(site, target, 'Moderated title'),
      isTrue,
    );
    expect(
      subject.chat.thread(site, target.threadId)?.title,
      'Moderated title',
    );
  });

  test(
    'failed optimistic notification update restores an absent membership',
    () async {
      final api =
          _AdversarialThreadApi(detail: threadDetail(withMembership: false))
            ..holdNotification(
              failure: const WriteException(WriteFailure.unreachable),
            );
      final store = Store()..put(site, threadDetail(withMembership: false));
      final subject = _controllerFor(api, store: store);

      final updating = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.muted,
      );
      expect(
        subject.chat.thread(site, 22)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.muted,
      );
      await api.notificationStarted!.future;
      api.notificationGate!.complete();

      expect(await updating, isFalse);
      expect(subject.chat.thread(site, 22)?.membership, isNull);
    },
  );

  test(
    'root preview events are authoritative and duplicate delivery never increments twice',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(
          replyCount: 4,
          preview: const ChatThreadPreview(
            threadId: 22,
            replyCount: 4,
            lastReplyId: 104,
          ),
        ),
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingChannel(site, target.channelId);
      addTearDown(
        () => subject.chat.endViewingChannel(site, target.channelId, view),
      );
      subject.store.put(
        site,
        const ChatMessage(
          id: 100,
          channelId: 9,
          threadId: 22,
          cooked: '<p>Original</p>',
          author: ChatMessageAuthor(id: 2, username: 'sam'),
          thread: ChatThreadPreview(threadId: 22, replyCount: 3),
        ),
      );
      subject.store.put(site, threadDetail(replyCount: 3));
      final event = authoritativePreviewEvent(replyCount: 4);

      tracker.deliverPluginMessage('/chat/9', event);
      tracker.deliverPluginMessage('/chat/9', event);

      expect(subject.store.read<ChatMessage>(site, 100)?.thread?.replyCount, 4);
      expect(
        subject.store.read<ChatMessage>(site, 100)?.thread?.lastReplyId,
        104,
      );
      expect(subject.chat.thread(site, 22)?.replyCount, 4);
      await Future<void>.delayed(Duration.zero);
      expect(subject.chat.thread(site, 22)?.replyCount, 4);
    },
  );

  test('root subscription starts at the channel snapshot cursor', () async {
    final api = _AdversarialThreadApi(
      detail: threadDetail(),
      channels: {
        site: ChatChannels(
          public: [followedChannel()],
          channelMessageBusLastIds: const {9: 700},
        ),
      },
    );
    final subject = _controllerFor(api);
    final tracker = attachTracker(subject.chat);

    await subject.chat.loadChannels(site);
    final view = subject.chat.beginViewingChannel(site, target.channelId);
    addTearDown(
      () => subject.chat.endViewingChannel(site, target.channelId, view),
    );

    expect(tracker.pluginChannelLastIds['/chat/9'], 700);
  });

  test(
    'thread tracking stays separate from parent channel aggregates',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        channels: {
          site: ChatChannels(public: [followedChannel()]),
        },
      );
      final store = Store()..put(site, threadDetail());
      final subject = _controllerFor(api, store: store);
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);

      tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
        'channel_id': 9,
        'thread_id': 22,
        'last_read_message_id': 33,
        'unread_count': 7,
        'mention_count': 6,
        'watched_threads_unread_count': 5,
        'thread_tracking': {
          'unread_count': 1,
          'mention_count': 2,
          'watched_threads_unread_count': 3,
        },
      });

      expect(
        subject.chat.channel(site, 9)?.tracking,
        const ChatTracking(
          unreadCount: 7,
          mentionCount: 6,
          watchedThreadsUnreadCount: 5,
        ),
      );
      expect(subject.chat.channel(site, 9)?.membership.lastReadMessageId, 10);
      expect(
        subject.chat.thread(site, 22)?.tracking,
        const ChatTracking(
          unreadCount: 1,
          mentionCount: 2,
          watchedThreadsUnreadCount: 3,
        ),
      );
      expect(subject.chat.thread(site, 22)?.membership?.lastReadMessageId, 33);
    },
  );

  test('a sent thread event inserts only into the thread stream', () {
    final api = _AdversarialThreadApi(detail: threadDetail());
    final store = Store()..put(site, threadDetail());
    final subject = _controllerFor(api, store: store);
    final tracker = attachTracker(subject.chat);
    final view = subject.chat.beginViewingThread(site, target);
    addTearDown(() => subject.chat.endViewingThread(site, target, view));

    tracker.deliverPluginMessage('/chat/9/thread/22', threadSentEvent(30));

    expect(subject.chat.streamFor(site, target).messageIds, [30]);
    expect(subject.chat.stream(site, target.channelId).messageIds, isEmpty);
    expect(subject.store.read<ChatMessage>(site, 30)?.threadId, 22);
  });

  test(
    'live replay during an anchored fetch is deduplicated and kept pending',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        holdMessages: true,
        pages: {
          'thread-9-22~target~20': threadPage(
            [19, 20, 21],
            canLoadMoreFuture: true,
            targetMessageId: 20,
          ),
        },
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingThread(site, target);
      addTearDown(() => subject.chat.endViewingThread(site, target, view));

      final opening = subject.chat.openThread(
        site,
        target,
        targetMessageId: 20,
      );
      await api.messagesStarted!.future;
      final event = threadSentEvent(30);
      tracker.deliverPluginMessage('/chat/9/thread/22', event);
      api.messagesGate!.complete();
      await opening;

      expect(subject.chat.streamFor(site, target).messageIds, [19, 20, 21]);
      expect(subject.chat.streamFor(site, target).pendingNewMessages, 1);

      tracker.deliverPluginMessage('/chat/9/thread/22', event);
      expect(subject.chat.streamFor(site, target).messageIds, [19, 20, 21]);
      expect(subject.chat.streamFor(site, target).pendingNewMessages, 1);
    },
  );

  test('thread reaction events update the held message without refetching', () {
    final api = _AdversarialThreadApi(detail: threadDetail());
    final store = Store()
      ..put(site, threadDetail())
      ..put(site, threadMessage(30));
    final subject = _controllerFor(api, store: store);
    final tracker = attachTracker(subject.chat);
    final view = subject.chat.beginViewingThread(site, target);
    addTearDown(() => subject.chat.endViewingThread(site, target, view));

    tracker.deliverPluginMessage('/chat/9/thread/22', {
      'type': 'reaction',
      'chat_message_id': 30,
      'emoji': 'heart',
      'action': 'add',
      'user': {'id': currentUser.id, 'username': currentUser.username},
    });
    tracker.deliverPluginMessage('/chat/9/thread/22', {
      'type': 'reaction',
      'chat_message_id': 30,
      'emoji': 'heart',
      'action': 'add',
      'user': {'id': 8, 'username': 'other'},
    });

    expect(subject.store.read<ChatMessage>(site, 30)?.reactions, const [
      ChatReaction(emoji: 'heart', count: 2, reacted: true, reactorIds: [7, 8]),
    ]);
    expect(api.callOrder, isEmpty);

    tracker.deliverPluginMessage('/chat/9/thread/22', {
      'type': 'reaction',
      'chat_message_id': 30,
      'emoji': 'heart',
      'action': 'remove',
      'user': {'id': currentUser.id, 'username': currentUser.username},
    });
    expect(subject.store.read<ChatMessage>(site, 30)?.reactions, const [
      ChatReaction(emoji: 'heart', count: 1, reactorIds: [8]),
    ]);
  });

  test(
    'an active thread view watches root and thread paths with the detail cursor',
    () {
      final api = _AdversarialThreadApi(
        detail: threadDetail(messageBusLastId: 733),
      );
      final store = Store()..put(site, threadDetail(messageBusLastId: 733));
      final subject = _controllerFor(api, store: store);
      final tracker = attachTracker(subject.chat);

      final view = subject.chat.beginViewingThread(site, target);

      expect(tracker.pluginChannelCallbacks['/chat/9'], hasLength(1));
      expect(tracker.pluginChannelCallbacks['/chat/9/thread/22'], hasLength(1));
      expect(tracker.pluginChannelLastIds['/chat/9'], isNull);
      expect(tracker.pluginChannelLastIds['/chat/9/thread/22'], 733);

      subject.chat.endViewingThread(site, target, view);
      expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      expect(tracker.pluginChannelCallbacks['/chat/9/thread/22'], isEmpty);
    },
  );

  test('active root and thread cursors advance across remounts', () async {
    final api = _AdversarialThreadApi(
      detail: threadDetail(messageBusLastId: 701),
      channels: {
        site: ChatChannels(
          public: [followedChannel()],
          channelMessageBusLastIds: const {9: 700},
        ),
      },
    );
    final store = Store()..put(site, threadDetail(messageBusLastId: 701));
    final subject = _controllerFor(api, store: store);
    final tracker = attachTracker(subject.chat);
    await subject.chat.loadChannels(site);

    final first = subject.chat.beginViewingThread(site, target);
    tracker.deliverPluginMessage('/chat/9', const {}, messageId: 750);
    tracker.deliverPluginMessage('/chat/9/thread/22', const {}, messageId: 760);
    subject.chat.endViewingThread(site, target, first);

    final second = subject.chat.beginViewingThread(site, target);
    addTearDown(() => subject.chat.endViewingThread(site, target, second));
    expect(tracker.pluginChannelLastIds['/chat/9'], 750);
    expect(tracker.pluginChannelLastIds['/chat/9/thread/22'], 760);
  });

  test('dual-delivered original reactions are applied exactly once', () {
    final api = _AdversarialThreadApi(detail: threadDetail());
    const original = ChatMessage(
      id: 100,
      channelId: 9,
      threadId: 22,
      cooked: '<p>Original</p>',
      author: ChatMessageAuthor(id: 2, username: 'sam'),
      thread: ChatThreadPreview(threadId: 22, replyCount: 3),
    );
    final store = Store()
      ..put(site, followedChannel())
      ..put(site, threadDetail())
      ..put(site, original);
    final subject = _controllerFor(api, store: store);
    final tracker = attachTracker(subject.chat);
    final view = subject.chat.beginViewingThread(site, target);
    addTearDown(() => subject.chat.endViewingThread(site, target, view));
    final event = {
      'type': 'reaction',
      'chat_message_id': 100,
      'emoji': 'heart',
      'action': 'add',
      'user': {'id': 8, 'username': 'other'},
    };

    tracker.deliverPluginMessage('/chat/9', event, messageId: 702);
    tracker.deliverPluginMessage('/chat/9/thread/22', event, messageId: 703);

    expect(subject.store.read<ChatMessage>(site, 100)?.reactions, const [
      ChatReaction(emoji: 'heart', count: 1, reactorIds: [8]),
    ]);
  });

  test(
    'a preview event dirties an in-flight detail and synchronizes its new title',
    () async {
      const oldPreview = ChatThreadPreview(
        threadId: 22,
        replyCount: 3,
        title: 'Old title',
      );
      const newPreview = ChatThreadPreview(
        threadId: 22,
        replyCount: 4,
        title: 'New title',
        lastReplyId: 104,
      );
      final api = _SequencedDetailApi();
      final store = Store()
        ..put(site, threadDetail(title: 'Old title', preview: oldPreview))
        ..put(
          site,
          const ChatMessage(
            id: 100,
            channelId: 9,
            threadId: 22,
            cooked: '<p>Original</p>',
            author: ChatMessageAuthor(id: 2, username: 'sam'),
            thread: oldPreview,
          ),
        );
      final subject = _controllerFor(api, store: store);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingChannel(site, 9);
      addTearDown(() => subject.chat.endViewingChannel(site, 9, view));

      final refreshing = subject.chat.refreshThreadDetail(site, target);
      await waitUntil(() => api.calls == 1);
      tracker.deliverPluginMessage(
        '/chat/9',
        authoritativePreviewEvent(replyCount: 4),
        messageId: 704,
      );
      api.responses[0].complete(
        threadDetail(title: 'Old title', preview: oldPreview),
      );
      await waitUntil(() => api.calls == 2);
      api.responses[1].complete(
        threadDetail(
          title: 'New title',
          replyCount: 4,
          lastMessageId: 104,
          preview: newPreview,
        ),
      );
      await refreshing;

      expect(subject.chat.thread(site, 22)?.title, 'New title');
      expect(subject.chat.thread(site, 22)?.replyCount, 4);
      expect(subject.store.read<ChatMessage>(site, 100)?.thread, newPreview);
    },
  );

  test(
    'thread metadata updates even when the root message is not held',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(
          replyCount: 4,
          preview: const ChatThreadPreview(
            threadId: 22,
            replyCount: 4,
            lastReplyId: 104,
          ),
        ),
      );
      final store = Store()..put(site, threadDetail(replyCount: 3));
      final subject = _controllerFor(api, store: store);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingChannel(site, 9);
      addTearDown(() => subject.chat.endViewingChannel(site, 9, view));

      tracker.deliverPluginMessage(
        '/chat/9',
        authoritativePreviewEvent(replyCount: 4),
      );
      await waitUntil(() => api.chatThreadsRequested.isNotEmpty);
      await Future<void>.delayed(Duration.zero);

      expect(subject.chat.thread(site, 22)?.replyCount, 4);
      expect(subject.chat.thread(site, 22)?.preview?.lastReplyId, 104);
    },
  );

  test('a full detail refetch clears a removed title and membership', () async {
    final api = _SequencedDetailApi();
    final store = Store()..put(site, threadDetail(title: 'Temporary title'));
    final subject = _controllerFor(api, store: store);

    final refreshing = subject.chat.refreshThreadDetail(site, target);
    await waitUntil(() => api.calls == 1);
    api.responses.single.complete(threadDetail(withMembership: false));
    await refreshing;

    expect(subject.chat.thread(site, 22)?.title, isNull);
    expect(subject.chat.thread(site, 22)?.membership, isNull);
    await subject.chat.markReadFor(site, target, 30);
    expect(api.chatReadsMarked, isEmpty);
  });

  test(
    'terminal detail failures remove stale state and transient ones do not',
    () async {
      final terminalApi = _AdversarialThreadApi(
        detail: threadDetail(),
        detailFailure: const SiteLookupException(
          SiteLookupFailure.unreachable,
          site,
          statusCode: 404,
        ),
      );
      final terminalStore = Store()
        ..put(site, followedChannel())
        ..put(site, threadDetail());
      final terminal = _controllerFor(terminalApi, store: terminalStore);

      await terminal.chat.refreshThreadDetail(site, target);
      expect(terminal.chat.streamFor(site, target).threadUnavailable, isTrue);
      expect(terminal.chat.thread(site, 22), isNull);
      expect(terminal.chat.canSendMessageTo(site, target), isFalse);

      final transientApi = _AdversarialThreadApi(
        detail: threadDetail(),
        detailFailure: const SiteLookupException(
          SiteLookupFailure.unreachable,
          site,
        ),
      );
      final transientStore = Store()
        ..put(site, followedChannel())
        ..put(site, threadDetail());
      final transient = _controllerFor(transientApi, store: transientStore);

      await transient.chat.refreshThreadDetail(site, target);
      expect(transient.chat.streamFor(site, target).threadUnavailable, isFalse);
      expect(transient.chat.thread(site, 22), isNotNull);
    },
  );

  test('the newest exact target wins overlapping thread opens', () async {
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final api = _AdversarialThreadApi(
      detail: threadDetail(),
      targetMessageGates: {20: firstGate, 30: secondGate},
      targetMessageStarts: {20: firstStarted, 30: secondStarted},
      pages: {
        'thread-9-22~target~20': threadPage([19, 20, 21]),
        'thread-9-22~target~30': threadPage([29, 30, 31]),
      },
    );
    final subject = _controllerFor(api);

    final first = subject.chat.openThread(site, target, targetMessageId: 20);
    await firstStarted.future;
    final second = subject.chat.openThread(site, target, targetMessageId: 30);
    await secondStarted.future;
    secondGate.complete();
    await second;
    firstGate.complete();
    await first;

    expect(subject.chat.streamFor(site, target).messageIds, [29, 30, 31]);
    expect(subject.chat.streamFor(site, target).anchorMessageId, 30);
  });

  test(
    'notification writes serialize and a failed latest choice rolls back',
    () async {
      final api = _SequencedNotificationApi();
      final store = Store()..put(site, threadDetail());
      final subject = _controllerFor(api, store: store);

      final first = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.watching,
      );
      await waitUntil(() => api.pending.length == 1);
      final second = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.muted,
      );
      expect(
        subject.chat.thread(site, 22)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.muted,
      );
      expect(api.pending, hasLength(1));

      api.pending[0].response.complete(
        const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.watching,
          lastReadMessageId: 17,
        ),
      );
      await waitUntil(() => api.pending.length == 2);
      expect(
        subject.chat.thread(site, 22)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.muted,
      );
      api.pending[1].response.completeError(
        const WriteException(WriteFailure.unreachable),
      );

      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(
        subject.chat.thread(site, 22)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.watching,
      );
      expect(
        api.chatThreadNotificationLevelsUpdated.map(
          (request) => request.notificationLevel,
        ),
        [
          ChatThreadNotificationLevel.watching,
          ChatThreadNotificationLevel.muted,
        ],
      );
    },
  );

  test(
    'new-message tracking updates a held watched thread and its parent',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        channels: {
          site: ChatChannels(public: [followedChannel()]),
        },
      );
      final store = Store()
        ..put(
          site,
          threadDetail(lastMessageId: 20).copyWith(
            membership: const ChatThreadMembership(
              threadId: 22,
              notificationLevel: ChatThreadNotificationLevel.watching,
              lastReadMessageId: 17,
            ),
          ),
        );
      final subject = _controllerFor(api, store: store);
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);

      tracker.deliverPluginMessage('/chat/9/new-messages', {
        'type': 'thread',
        'channel_id': 9,
        'thread_id': 22,
        'force_thread': false,
        'message': {
          'id': 30,
          'chat_channel_id': 9,
          'created_at': '2026-08-12T12:00:00.000Z',
          'user': {'id': 8, 'username': 'other'},
        },
      });

      expect(subject.chat.thread(site, 22)?.lastMessageId, 30);
      expect(subject.chat.thread(site, 22)?.membership?.lastReadMessageId, 17);
      expect(
        subject.chat.thread(site, 22)?.tracking.watchedThreadsUnreadCount,
        1,
      );
      expect(
        subject.chat.channel(site, 9)?.tracking.watchedThreadsUnreadCount,
        1,
      );
      expect(subject.chat.channel(site, 9)?.unreadThreadOverview, contains(22));
    },
  );

  test('delete moves a thread read cursor off the deleted reply', () {
    final detail = threadDetail(lastMessageId: 30).copyWith(
      membership: const ChatThreadMembership(
        threadId: 22,
        notificationLevel: ChatThreadNotificationLevel.tracking,
        lastReadMessageId: 30,
      ),
    );
    final api = _AdversarialThreadApi(detail: detail);
    final store = Store()
      ..put(site, detail)
      ..put(site, threadMessage(30));
    final subject = _controllerFor(api, store: store);
    final tracker = attachTracker(subject.chat);
    final view = subject.chat.beginViewingThread(site, target);
    addTearDown(() => subject.chat.endViewingThread(site, target, view));

    tracker.deliverPluginMessage('/chat/9/thread/22', {
      'type': 'delete',
      'deleted_id': 30,
      'deleted_at': '2026-08-12T12:01:00.000Z',
      'latest_not_deleted_message_id': 29,
    });

    expect(subject.chat.thread(site, 22)?.membership?.lastReadMessageId, 29);
    expect(subject.chat.thread(site, 22)?.lastMessageId, 29);
    expect(subject.store.read<ChatMessage>(site, 30), isNull);
  });

  test(
    'thread send and creation gates revalidate authoritative state',
    () async {
      final created = threadDetail();
      final api = FakeDiscourseApi(
        createdChatThreadsByKey: {
          FakeDiscourseApi.createdChatThreadKey(9, 100): created,
        },
      );
      final store = Store();
      final subject = _controllerFor(api, store: store);

      store
        ..put(site, followedChannel(threadingEnabled: false))
        ..put(site, threadDetail(force: false));
      expect(subject.chat.canSendMessageTo(site, target), isFalse);
      expect(
        await subject.chat.createThread(
          site,
          channelId: 9,
          originalMessageId: 100,
        ),
        isNull,
      );
      expect(api.chatThreadsCreated, isEmpty);

      store.put(site, threadDetail(force: true));
      expect(subject.chat.canSendMessageTo(site, target), isTrue);
      store.put(site, threadDetail(force: true, status: 'closed'));
      expect(subject.chat.canSendMessageTo(site, target), isFalse);

      store.put(site, followedChannel());
      expect(
        await subject.chat.createThread(
          site,
          channelId: 9,
          originalMessageId: 100,
        ),
        created,
      );
      expect(api.chatThreadsCreated, hasLength(1));
    },
  );
}
