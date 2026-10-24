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
  ChatChannelKind kind = ChatChannelKind.category,
  bool userSilenced = false,
}) => ChatChannel(
  id: 9,
  title: 'Support',
  kind: kind,
  userSilenced: userSilenced,
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

/// The server's user-tracking echo once the reader has read the thread through
/// [lastReadMessageId]: nothing is unread in the thread or its channel.
Map<String, dynamic> threadReadEcho(int lastReadMessageId) => {
  'channel_id': target.channelId,
  'thread_id': target.threadId,
  'last_read_message_id': lastReadMessageId,
  'unread_count': 0,
  'mention_count': 0,
  'watched_threads_unread_count': 0,
  'thread_tracking': {
    'unread_count': 0,
    'mention_count': 0,
    'watched_threads_unread_count': 0,
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

final class _SequencedTitleApi extends FakeDiscourseApi {
  final List<Completer<void>> responses = [];

  @override
  Future<void> updateChatThreadTitle({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required String title,
    String? clientId,
  }) {
    chatThreadTitlesUpdated.add((
      channelId: channelId,
      threadId: threadId,
      title: title,
    ));
    final response = Completer<void>();
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

/// Answers each thread-list page through its own completer so a test can
/// finish an earlier page after a later refresh has already been issued.
final class _SequencedThreadListApi extends FakeDiscourseApi {
  _SequencedThreadListApi({
    super.chatChannelsBySite,
    super.createdChatThreadsByKey,
    super.chatThreadsByKey,
  });

  Object? titleFailure;

  @override
  Future<void> updateChatThreadTitle({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required String title,
    String? clientId,
  }) async {
    await super.updateChatThreadTitle(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      threadId: threadId,
      title: title,
      clientId: clientId,
    );
    if (titleFailure case final failure?) throw failure;
  }

  final List<Completer<ChatThreadPage>> myThreadPages = [];
  final List<Completer<ChatThreadPage>> channelThreadPages = [];
  Completer<void>? _myThreadPageStarted;
  Completer<void>? _channelThreadPageStarted;

  /// Resolves once the next my-threads page request reaches the API.
  Future<void> nextMyThreadPage() =>
      (_myThreadPageStarted = Completer<void>()).future;

  /// Resolves once the next channel threads page request reaches the API.
  Future<void> nextChannelThreadPage() =>
      (_channelThreadPageStarted = Completer<void>()).future;

  @override
  Future<ChatThreadPage> chatThreads({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) {
    chatThreadPagesRequested.add((offset: offset, limit: limit));
    final response = Completer<ChatThreadPage>();
    myThreadPages.add(response);
    _myThreadPageStarted?.complete();
    _myThreadPageStarted = null;
    return response.future;
  }

  @override
  Future<ChatThreadPage> chatChannelThreads({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) {
    chatChannelThreadPagesRequested.add((
      channelId: channelId,
      offset: offset,
      limit: limit,
    ));
    final response = Completer<ChatThreadPage>();
    channelThreadPages.add(response);
    _channelThreadPageStarted?.complete();
    _channelThreadPageStarted = null;
    return response.future;
  }
}

({ChatController chat, Store store}) _controllerFor(
  ChatApi api, {
  Store? store,
  DiscourseUser user = currentUser,
  FakeApiCredentialReader? credentials,
  FakePluginRequestHost? requests,
  bool autoDispose = true,
  DateTime Function()? clock,
}) {
  credentials ??= FakeApiCredentialReader()..keys[site] = 'key';
  final resolvedStore = store ?? Store();
  final chat = ChatController(
    api: api,
    requests: requests ?? FakePluginRequestHost(credentials: credentials),
    store: resolvedStore,
    currentUserFor: (_) => user,
    minimumWindowRefreshInterval: Duration.zero,
    clock: clock ?? () => DateTime.utc(2026, 8, 12, 12),
  );
  if (autoDispose) addTearDown(chat.dispose);
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

  for (final personal in [true, false]) {
    final listName = personal ? 'personal' : 'channel';
    for (final (label, edits, staleTitle) in [
      ('rename', ['After'], 'Before'),
      ('clear', [''], 'Before'),
      ('return to original', ['After', 'Before'], 'Intermediate'),
      ('accepted same value', ['Before'], 'Stale'),
    ]) {
      test(
        '$listName list retains a $label accepted during its request',
        () async {
          final api = _SequencedThreadListApi();
          final before = threadDetail(title: 'Before', originalAuthorId: 7);
          final subject = _controllerFor(
            api,
            store: Store()
              ..put(site, followedChannel())
              ..put(site, before),
          );
          Future<void> load() => personal
              ? subject.chat.loadMyThreads(site, force: true)
              : subject.chat.loadChannelThreads(site, 9, force: true);
          final pages = personal ? api.myThreadPages : api.channelThreadPages;
          final refreshing = load();
          await waitUntil(() => pages.length == 1);

          for (final title in edits) {
            expect(
              await subject.chat.updateThreadTitle(site, target, title),
              isTrue,
            );
          }
          pages.single.complete(
            ChatThreadPage(threads: [before.copyWith(title: staleTitle)]),
          );
          await refreshing;

          expect(subject.chat.thread(site, 22)?.title, edits.last);
          final projected = personal
              ? subject.chat.myThreads(site)
              : subject.chat.channelThreads(site, 9);
          expect(projected.single.title, edits.last);

          final fresh = load();
          await waitUntil(() => pages.length == 2);
          pages.last.complete(
            ChatThreadPage(threads: [before.copyWith(clearTitle: true)]),
          );
          await fresh;
          expect(subject.chat.thread(site, 22)?.title, isNull);
        },
      );
    }

    for (final title in ['Live title', null]) {
      test('$listName list retains a live detail title of $title', () async {
        final before = threadDetail(title: 'Before');
        final live = before.copyWith(title: title, clearTitle: title == null);
        final api = _SequencedThreadListApi(
          chatThreadsByKey: {FakeDiscourseApi.chatThreadKey(9, 22): live},
        );
        final subject = _controllerFor(
          api,
          store: Store()
            ..put(site, followedChannel())
            ..put(site, before),
        );
        final tracker = attachTracker(subject.chat);
        final viewing = subject.chat.beginViewingChannel(site, 9);
        addTearDown(() => subject.chat.endViewingChannel(site, 9, viewing));
        final pages = personal ? api.myThreadPages : api.channelThreadPages;
        final refreshing = personal
            ? subject.chat.loadMyThreads(site)
            : subject.chat.loadChannelThreads(site, 9);
        await waitUntil(() => pages.length == 1);

        tracker.deliverPluginMessage('/chat/9', authoritativePreviewEvent());
        await waitUntil(() => subject.chat.thread(site, 22)?.title == title);
        pages.single.complete(ChatThreadPage(threads: [before]));
        await refreshing;

        expect(subject.chat.thread(site, 22)?.title, title);
        final projected = personal
            ? subject.chat.myThreads(site)
            : subject.chat.channelThreads(site, 9);
        expect(projected.single.title, title);
        expect(await subject.chat.refreshThreadDetail(site, target), isNotNull);
        expect(subject.chat.thread(site, 22)?.title, title);
      });
    }

    test('$listName list accepts a title after a refused rename', () async {
      final before = threadDetail(title: 'Before', originalAuthorId: 7);
      final api = _SequencedThreadListApi()
        ..titleFailure = const WriteException(WriteFailure.forbidden);
      final subject = _controllerFor(
        api,
        store: Store()
          ..put(site, followedChannel())
          ..put(site, before),
      );
      final pages = personal ? api.myThreadPages : api.channelThreadPages;
      final refreshing = personal
          ? subject.chat.loadMyThreads(site)
          : subject.chat.loadChannelThreads(site, 9);
      await waitUntil(() => pages.length == 1);

      expect(
        await subject.chat.updateThreadTitle(site, target, 'Refused'),
        isFalse,
      );
      pages.single.complete(
        ChatThreadPage(threads: [before.copyWith(title: 'Server')]),
      );
      await refreshing;

      expect(subject.chat.thread(site, 22)?.title, 'Server');
    });
  }

  test(
    'a kick clears cached previews and rejects a late my-threads page',
    () async {
      final api = _SequencedThreadListApi(
        chatChannelsBySite: {
          site: ChatChannels(
            public: [followedChannel()],
            kickMessageBusLastIds: const {9: 72},
          ),
        },
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      final started = api.nextMyThreadPage();
      final initial = subject.chat.loadMyThreads(site);
      await started;
      api.myThreadPages[0].complete(
        ChatThreadPage(threads: [listedThread(22)], hasMore: true),
      );
      await initial;
      final preview = subject.store.ref<ChatThread>(site, 22);
      final lateStarted = api.nextMyThreadPage();
      final late = subject.chat.loadMyThreads(site, more: true);
      await lateStarted;
      tracker.deliverPluginMessage('/chat/9/kick', {'channel_id': 9});
      expect(subject.chat.myThreads(site), isEmpty);
      expect(preview.value, isNull);
      api.myThreadPages[1].complete(
        ChatThreadPage(
          threads: [listedThread(23)],
          channels: [followedChannel()],
        ),
      );
      await late;
      expect(subject.chat.myThreads(site), isEmpty);
      expect(subject.chat.channel(site, 9), isNull);
      expect(subject.chat.thread(site, 23), isNull);
      expect(subject.chat.myThreadsLoadingMore(site), isFalse);
    },
  );

  test(
    'a kick rejects late thread detail and its cached original preview',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        holdDetail: true,
        channels: {
          site: ChatChannels(
            public: [followedChannel()],
            kickMessageBusLastIds: const {9: 72},
          ),
        },
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      subject.store.put(site, threadMessage(100));
      final pending = subject.chat.openThread(site, target);
      await api.detailStarted!.future;
      tracker.deliverPluginMessage('/chat/9/kick', {'channel_id': 9});
      api.detailGate!.complete();
      await pending;
      expect(subject.chat.thread(site, 22), isNull);
      expect(subject.store.read<ChatMessage>(site, 100), isNull);
      expect(subject.chat.streamFor(site, target).messageIds, isEmpty);
      expect(
        subject.chat.streamFor(site, target).error,
        'You no longer have access to this channel.',
      );
      expect(api.callOrder, ['detail']);
    },
  );

  test(
    'a kick rejects a late thread window without restoring cached messages',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        holdMessages: true,
        pages: {
          'thread-9-22': threadPage([101]),
        },
        channels: {
          site: ChatChannels(
            public: [followedChannel()],
            kickMessageBusLastIds: const {9: 72},
          ),
        },
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      final pending = subject.chat.openThread(site, target);
      await api.messagesStarted!.future;
      tracker.deliverPluginMessage('/chat/9/kick', {'channel_id': 9});
      api.messagesGate!.complete();
      await pending;
      expect(subject.chat.streamFor(site, target).messageIds, isEmpty);
      expect(
        subject.chat.streamFor(site, target).error,
        'You no longer have access to this channel.',
      );
      expect(subject.store.read<ChatMessage>(site, 101), isNull);
      expect(subject.chat.thread(site, 22), isNull);
    },
  );

  test(
    'refresh replaces my threads with authorized unfollowed results',
    () async {
      final api = _SequencedThreadListApi();
      final subject = _controllerFor(api);
      for (final id in [22, 23]) {
        final started = api.nextMyThreadPage();
        final request = subject.chat.loadMyThreads(site, force: true);
        await started;
        api.myThreadPages.last.complete(
          ChatThreadPage(
            threads: [listedThread(id)],
            channels: [
              followedChannel(
                membership: const ChatMembership(following: false),
              ),
            ],
          ),
        );
        await request;
        expect(subject.chat.myThreads(site).map((thread) => thread.id), [id]);
      }
      expect(subject.chat.publicChannels(site), isEmpty);
      expect(subject.chat.channel(site, 9)?.membership.following, isFalse);
    },
  );

  test('my threads caches and appends core account pages', () async {
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

  for (final personal in [true, false]) {
    for (final fails in [false, true]) {
      test(
        '${personal ? "personal" : "channel"} list retirement rejects late '
        '${fails ? "failure" : "success"} without finishing its replacement',
        () async {
          final api = _SequencedThreadListApi(
            chatChannelsBySite: {
              site: ChatChannels(public: [followedChannel()]),
            },
          );
          final subject = _controllerFor(api);
          Future<void> load() => personal
              ? subject.chat.loadMyThreads(site)
              : subject.chat.loadChannelThreads(site, 9);
          Future<void> started() =>
              personal ? api.nextMyThreadPage() : api.nextChannelThreadPage();
          final pages = personal ? api.myThreadPages : api.channelThreadPages;
          await subject.chat.loadChannels(site);
          final oldStarted = started();
          final old = load();
          await oldStarted;
          subject.chat.forget(site);
          await subject.chat.loadChannels(site);
          final replacementStarted = started();
          final replacement = load();
          await replacementStarted;

          if (fails) {
            pages[0].completeError(StateError('Retired account'));
          } else {
            pages[0].complete(ChatThreadPage(threads: [listedThread(1)]));
          }
          await old;
          expect(subject.chat.thread(site, 1), isNull);
          expect(subject.chat.myThreadsLoaded(site), isFalse);
          expect(subject.chat.channelThreadsLoaded(site, 9), isFalse);
          expect(subject.chat.myThreadsError(site), isNull);
          expect(subject.chat.channelThreadsError(site, 9), isNull);
          expect(load(), same(replacement));

          pages[1].complete(ChatThreadPage(threads: [listedThread(2)]));
          await replacement;
          final threads = personal
              ? subject.chat.myThreads(site)
              : subject.chat.channelThreads(site, 9);
          expect(threads.map((thread) => thread.id), [2]);
          expect(subject.chat.channelThreadsLoading(site, 9), isFalse);
        },
      );
    }
  }

  test('local creation shifts both wire offsets once per new thread', () async {
    final created = listedThread(3);
    final api = _SequencedThreadListApi(
      chatChannelsBySite: {
        site: ChatChannels(public: [followedChannel()]),
      },
      createdChatThreadsByKey: {
        FakeDiscourseApi.createdChatThreadKey(9, 30): created,
      },
    );
    final subject = _controllerFor(api);
    await subject.chat.loadChannels(site);
    final personalStarted = api.nextMyThreadPage();
    final personal = subject.chat.loadMyThreads(site);
    await personalStarted;
    api.myThreadPages.single.complete(
      ChatThreadPage(threads: [listedThread(1)], hasMore: true),
    );
    await personal;
    final channelStarted = api.nextChannelThreadPage();
    final channel = subject.chat.loadChannelThreads(site, 9);
    await channelStarted;
    api.channelThreadPages.single.complete(
      ChatThreadPage(threads: [listedThread(1)], hasMore: true),
    );
    await channel;

    for (var attempt = 0; attempt < 2; attempt++) {
      expect(
        await subject.chat.createThread(
          site,
          channelId: 9,
          originalMessageId: 30,
        ),
        created,
      );
    }
    expect(subject.chat.myThreads(site).map((thread) => thread.id), [3, 1]);
    expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
      3,
      1,
    ]);
    final nextPersonalStarted = api.nextMyThreadPage();
    final nextPersonal = subject.chat.loadMyThreads(site, more: true);
    await nextPersonalStarted;
    final nextChannelStarted = api.nextChannelThreadPage();
    final nextChannel = subject.chat.loadChannelThreads(site, 9, more: true);
    await nextChannelStarted;
    expect(api.chatThreadPagesRequested.last.offset, 2);
    expect(api.chatChannelThreadPagesRequested.last.offset, 2);
    api.myThreadPages.last.complete(const ChatThreadPage());
    api.channelThreadPages.last.complete(const ChatThreadPage());
    await Future.wait([nextPersonal, nextChannel]);
  });

  for (final personal in [true, false]) {
    test('${personal ? "personal" : "channel"} list replaces an expired lease '
        'without replacing its retained conversation', () async {
      final api = _SequencedThreadListApi();
      final requests = FakePluginRequestHost(
        credentials: FakeApiCredentialReader()..keys[site] = 'key',
      );
      final subject = _controllerFor(api, requests: requests);
      subject.store.put(site, followedChannel());
      final conversation = subject.chat.streamListenableFor(site, target);
      Future<void> load() => personal
          ? subject.chat.loadMyThreads(site)
          : subject.chat.loadChannelThreads(site, 9);
      Future<void> started() =>
          personal ? api.nextMyThreadPage() : api.nextChannelThreadPage();
      final pages = personal ? api.myThreadPages : api.channelThreadPages;
      final oldStarted = started();
      final old = load();
      await oldStarted;
      requests.lifecycle.invalidate(site);
      final nextStarted = started();
      final next = load();
      await nextStarted;
      pages.first.complete(ChatThreadPage(threads: [listedThread(1)]));
      await old;
      expect(subject.chat.thread(site, 1), isNull);
      expect(load(), same(next));
      expect(
        subject.chat.streamListenableFor(site, target),
        same(conversation),
      );
      pages.last.complete(ChatThreadPage(threads: [listedThread(2)]));
      await next;
      final threads = personal
          ? subject.chat.myThreads(site)
          : subject.chat.channelThreads(site, 9);
      expect(threads.map((thread) => thread.id), [2]);
    });
  }

  for (final personal in [true, false]) {
    for (final dispose in [false, true]) {
      test(
        '${personal ? "personal" : "channel"} list '
        '${dispose ? "disposal" : "forget"} disowns a credential wait',
        () async {
          final api = _SequencedThreadListApi();
          final credentials = _HeldTitleCredentials();
          final subject = _controllerFor(
            api,
            credentials: credentials,
            autoDispose: !dispose,
          );
          subject.store.put(site, followedChannel());
          final pending = personal
              ? subject.chat.loadMyThreads(site)
              : subject.chat.loadChannelThreads(site, 9);
          await credentials.started.future;
          if (dispose) {
            subject.chat.dispose();
          } else {
            subject.chat.forget(site);
          }
          credentials.key.complete('key');
          await pending;
          expect(api.myThreadPages, isEmpty);
          expect(api.channelThreadPages, isEmpty);
          expect(subject.chat.myThreadsLoaded(site), isFalse);
          expect(subject.chat.channelThreadsLoaded(site, 9), isFalse);
        },
      );
    }
  }

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
    'channel threads follow canonical writes from an empty result',
    () async {
      final api = FakeDiscourseApi(
        chatChannelThreadPagesByKey: {
          FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
            threads: [
              listedThread(1, hasReplies: false),
              listedThread(2, deletedAt: DateTime.utc(2026, 8, 12)),
            ],
          ),
        },
      );
      final subject = _controllerFor(api);
      subject.store.put(site, followedChannel());
      await subject.chat.loadChannelThreads(site, 9);

      expect(subject.chat.channelThreads(site, 9), isEmpty);
      subject.store.put(site, listedThread(1));
      subject.store.put(site, listedThread(2));
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        2,
        1,
      ]);

      subject.store.update<ChatThread>(
        site,
        1,
        (thread) => thread.copyWith(
          title: 'Canonical title',
          tracking: const ChatTracking(unreadCount: 1),
        ),
      );
      final unread = subject.chat.channelThreads(site, 9);
      expect(unread.map((thread) => thread.id), [1, 2]);
      expect(unread.first.title, 'Canonical title');
      expect(() => unread.add(listedThread(3)), throwsUnsupportedError);

      subject.store.put(
        site,
        listedThread(
          2,
          tracking: const ChatTracking(watchedThreadsUnreadCount: 1),
        ),
      );
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        2,
        1,
      ]);

      subject.store.remove<ChatThread>(site, 2);
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        1,
      ]);
      subject.store.update<ChatThread>(
        site,
        1,
        (thread) => thread.copyWith(
          originalMessage: thread.originalMessage!.copyWith(
            deletedAt: DateTime.utc(2026, 8, 12),
          ),
        ),
      );
      expect(subject.chat.channelThreads(site, 9), isEmpty);
      subject.store.put(site, listedThread(1));
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        1,
      ]);
    },
  );

  test(
    'channel threads drop evicted records and rematerialize canonical rows',
    () async {
      final api = FakeDiscourseApi(
        chatChannelThreadPagesByKey: {
          FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
            threads: [listedThread(1), listedThread(2)],
          ),
        },
      );
      final subject = _controllerFor(
        api,
        store: Store(
          policy: const StorePolicy(
            maxEntries: 100,
            maxEntriesPerSiteAndType: 2,
          ),
        ),
      );
      subject.store.put(site, followedChannel());
      await subject.chat.loadChannelThreads(site, 9);
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        2,
        1,
      ]);

      subject.store.put(site, listedThread(3));
      expect(subject.store.containsRecord<ChatThread>(site, 1), isFalse);
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        2,
      ]);

      subject.store.put(
        site,
        listedThread(1).copyWith(title: 'Rematerialized'),
      );
      final threads = subject.chat.channelThreads(site, 9);
      expect(threads.map((thread) => thread.id), [2, 1]);
      expect(threads.last.title, 'Rematerialized');
    },
  );

  test(
    'channel thread projections release evicted records across channel visits',
    () async {
      ChatThread record(int channelId, int id) => ChatThread(
        id: id,
        channelId: channelId,
        status: 'open',
        replyCount: 1,
        lastMessageId: id * 10 + 1,
      );
      final api = FakeDiscourseApi(
        chatChannelThreadPagesByKey: {
          for (final channelId in [9, 10, 11])
            FakeDiscourseApi.chatChannelThreadPageKey(
              channelId,
              0,
            ): ChatThreadPage(
              threads: [
                record(channelId, channelId * 10),
                record(channelId, channelId * 10 + 1),
              ],
            ),
        },
      );
      final subject = _controllerFor(
        api,
        store: Store(
          policy: const StorePolicy(
            maxEntries: 100,
            maxEntriesPerSiteAndType: 2,
          ),
        ),
      );

      for (final channelId in [9, 10, 11]) {
        await subject.chat.loadChannelThreads(
          site,
          channelId,
          directoryChannel: ChatChannel(
            id: channelId,
            title: 'Channel $channelId',
            kind: ChatChannelKind.category,
            threadingEnabled: true,
          ),
        );
        expect(
          subject.chat
              .channelThreads(site, channelId)
              .map((thread) => thread.id),
          [channelId * 10 + 1, channelId * 10],
        );
        expect(
          subject.chat.retainedChannelThreadRecordsForTesting(site),
          lessThanOrEqualTo(2),
        );
        expect(
          subject.store.statisticsForTesting.entriesFor<ChatThread>(site),
          2,
        );
        for (
          var previousChannelId = 9;
          previousChannelId < channelId;
          previousChannelId++
        ) {
          expect(
            subject.store.containsRecord<ChatThread>(
              site,
              previousChannelId * 10,
            ),
            isFalse,
          );
          expect(
            subject.store.containsRecord<ChatThread>(
              site,
              previousChannelId * 10 + 1,
            ),
            isFalse,
          );
          expect(
            subject.chat.channelThreadsLoaded(site, previousChannelId),
            isTrue,
          );
        }
      }

      subject.store.put(site, record(9, 90));
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        90,
      ]);
      expect(subject.chat.retainedChannelThreadRecordsForTesting(site), 1);
    },
  );

  for (final reset in ['lease expiry', 'forget', 'disposal', 'kick']) {
    test('channel threads discard a loaded result after $reset', () async {
      final api = _SequencedThreadListApi(
        chatChannelsBySite: {
          site: ChatChannels(
            public: [followedChannel()],
            kickMessageBusLastIds: const {9: 72},
          ),
        },
      );
      final requests = FakePluginRequestHost(
        credentials: FakeApiCredentialReader()..keys[site] = 'key',
      );
      final subject = _controllerFor(
        api,
        requests: requests,
        autoDispose: reset != 'disposal',
      );
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      final started = api.nextChannelThreadPage();
      final initial = subject.chat.loadChannelThreads(site, 9);
      await started;
      api.channelThreadPages.single.complete(
        ChatThreadPage(threads: [listedThread(1)]),
      );
      await initial;
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        1,
      ]);

      switch (reset) {
        case 'lease expiry':
          requests.lifecycle.invalidate(site);
        case 'forget':
          subject.chat.forget(site);
          subject.store.forget(site);
        case 'disposal':
          subject.chat.dispose();
        case 'kick':
          tracker.deliverPluginMessage('/chat/9/kick', {'channel_id': 9});
      }
      expect(subject.chat.channelThreads(site, 9), isEmpty);
      expect(subject.chat.channelThreadsLoaded(site, 9), isFalse);

      if (reset == 'disposal' || reset == 'kick') return;
      await subject.chat.loadChannels(site);
      final nextStarted = api.nextChannelThreadPage();
      final next = subject.chat.loadChannelThreads(site, 9);
      await nextStarted;
      api.channelThreadPages.last.complete(
        ChatThreadPage(threads: [listedThread(2)]),
      );
      await next;
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        2,
      ]);
    });
  }

  test('a my-threads refresh supersedes a page already in flight', () async {
    final api = _SequencedThreadListApi(
      chatChannelsBySite: {
        site: ChatChannels(public: [followedChannel()]),
      },
    );
    final subject = _controllerFor(api);
    await subject.chat.loadChannels(site);

    final initialStarted = api.nextMyThreadPage();
    final initial = subject.chat.loadMyThreads(site);
    await initialStarted;
    api.myThreadPages[0].complete(
      ChatThreadPage(threads: [listedThread(1)], hasMore: true),
    );
    await initial;
    expect(subject.chat.myThreads(site).map((thread) => thread.id), [1]);

    final pageStarted = api.nextMyThreadPage();
    final page = subject.chat.loadMyThreads(site, more: true);
    await pageStarted;
    final refreshStarted = api.nextMyThreadPage();
    final refresh = subject.chat.loadMyThreads(site, force: true);
    api.myThreadPages[1].complete(ChatThreadPage(threads: [listedThread(2)]));
    await page;

    expect(subject.chat.myThreads(site).map((thread) => thread.id), [1]);
    expect(subject.chat.myThreadsLoadingMore(site), isTrue);
    await refreshStarted;
    expect(api.chatThreadPagesRequested, [
      (offset: 0, limit: 10),
      (offset: 1, limit: 10),
      (offset: 0, limit: 10),
    ]);

    api.myThreadPages[2].complete(
      ChatThreadPage(threads: [listedThread(3)], hasMore: true),
    );
    await refresh;

    expect(subject.chat.myThreads(site).map((thread) => thread.id), [3]);
    expect(subject.chat.myThreadsHaveMore(site), isTrue);
    expect(subject.chat.myThreadsLoadingMore(site), isFalse);
    expect(subject.chat.myThreadsError(site), isNull);

    final nextStarted = api.nextMyThreadPage();
    final next = subject.chat.loadMyThreads(site, more: true);
    await nextStarted;
    expect(api.chatThreadPagesRequested.last, (offset: 1, limit: 10));
    api.myThreadPages[3].complete(const ChatThreadPage());
    await next;
    expect(subject.chat.myThreads(site).map((thread) => thread.id), [3]);
  });

  test('a my-threads page answered before a local read and level change keeps '
      'them', () async {
    const tracked = ChatThreadMembership(
      threadId: 22,
      notificationLevel: ChatThreadNotificationLevel.tracking,
      lastReadMessageId: 17,
    );
    final answeredBefore = listedThread(
      22,
      tracking: const ChatTracking(unreadCount: 2),
      membership: tracked,
    );
    final api = _SequencedThreadListApi(
      chatChannelsBySite: {
        site: ChatChannels(public: [followedChannel()]),
      },
    );
    final subject = _controllerFor(api);
    await subject.chat.loadChannels(site);
    subject.store.put(site, answeredBefore);

    final started = api.nextMyThreadPage();
    final refresh = subject.chat.loadMyThreads(site, force: true);
    await started;
    await subject.chat.markReadFor(site, target, 40);
    expect(
      await subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.watching,
      ),
      isTrue,
    );
    api.myThreadPages.single.complete(
      ChatThreadPage(threads: [answeredBefore]),
    );
    await refresh;

    final held = subject.chat.thread(site, 22)!;
    expect(subject.chat.myThreads(site).map((thread) => thread.id), [22]);
    expect(held.membership?.lastReadMessageId, 40);
    expect(
      held.membership?.notificationLevel,
      ChatThreadNotificationLevel.watching,
    );
  });

  test(
    'a channel threads page answered before a read echo keeps the thread read',
    () async {
      final answeredBefore = listedThread(
        22,
        tracking: const ChatTracking(unreadCount: 2),
        membership: const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.tracking,
          lastReadMessageId: 17,
        ),
      );
      final api = _SequencedThreadListApi(
        chatChannelsBySite: {
          site: ChatChannels(public: [followedChannel()]),
        },
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      subject.store.put(site, answeredBefore);

      final started = api.nextChannelThreadPage();
      final refresh = subject.chat.loadChannelThreads(site, 9, force: true);
      await started;
      tracker.deliverPluginMessage(
        '/chat/user-tracking-state/7',
        threadReadEcho(40),
      );
      api.channelThreadPages.single.complete(
        ChatThreadPage(threads: [answeredBefore]),
      );
      await refresh;

      final held = subject.chat.thread(site, 22)!;
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        22,
      ]);
      expect(held.tracking, ChatTracking.none);
      expect(held.membership?.lastReadMessageId, 40);
    },
  );

  test(
    'a channel threads refresh supersedes a page already in flight',
    () async {
      final api = _SequencedThreadListApi(
        chatChannelsBySite: {
          site: ChatChannels(public: [followedChannel()]),
        },
      );
      final subject = _controllerFor(api);
      await subject.chat.loadChannels(site);

      final initialStarted = api.nextChannelThreadPage();
      final initial = subject.chat.loadChannelThreads(site, 9);
      await initialStarted;
      api.channelThreadPages[0].complete(
        ChatThreadPage(threads: [listedThread(1)], hasMore: true),
      );
      await initial;
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        1,
      ]);

      final pageStarted = api.nextChannelThreadPage();
      final page = subject.chat.loadChannelThreads(site, 9, more: true);
      await pageStarted;
      final refreshStarted = api.nextChannelThreadPage();
      final refresh = subject.chat.loadChannelThreads(site, 9, force: true);
      api.channelThreadPages[1].complete(
        ChatThreadPage(threads: [listedThread(2)]),
      );
      await page;

      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        1,
      ]);
      expect(subject.chat.channelThreadsLoadingMore(site, 9), isTrue);
      await refreshStarted;
      expect(api.chatChannelThreadPagesRequested, [
        (channelId: 9, offset: 0, limit: 10),
        (channelId: 9, offset: 1, limit: 10),
        (channelId: 9, offset: 0, limit: 10),
      ]);

      api.channelThreadPages[2].complete(
        ChatThreadPage(threads: [listedThread(3)], hasMore: true),
      );
      await refresh;

      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        3,
      ]);
      expect(subject.chat.channelThreadsHaveMore(site, 9), isTrue);
      expect(subject.chat.channelThreadsLoadingMore(site, 9), isFalse);
      expect(subject.chat.channelThreadsError(site, 9), isNull);

      final nextStarted = api.nextChannelThreadPage();
      final next = subject.chat.loadChannelThreads(site, 9, more: true);
      await nextStarted;
      expect(api.chatChannelThreadPagesRequested.last, (
        channelId: 9,
        offset: 1,
        limit: 10,
      ));
      api.channelThreadPages[3].complete(const ChatThreadPage());
      await next;
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        3,
      ]);
    },
  );

  test(
    'a channel threads revalidation adds new threads to the pages already read',
    () async {
      final firstPage = FakeDiscourseApi.chatChannelThreadPageKey(9, 0);
      final pages = {
        firstPage: ChatThreadPage(threads: [listedThread(1)], hasMore: true),
        FakeDiscourseApi.chatChannelThreadPageKey(9, 1): ChatThreadPage(
          threads: [listedThread(2)],
          hasMore: true,
        ),
        FakeDiscourseApi.chatChannelThreadPageKey(9, 3): ChatThreadPage(
          threads: [listedThread(4)],
        ),
      };
      final api = FakeDiscourseApi(
        chatChannelsBySite: {
          site: ChatChannels(public: [followedChannel()]),
        },
        chatChannelThreadPagesByKey: pages,
      );
      final subject = _controllerFor(api);
      Iterable<int> ids() =>
          subject.chat.channelThreads(site, 9).map((thread) => thread.id);
      await subject.chat.loadChannels(site);
      await subject.chat.loadChannelThreads(site, 9);
      await subject.chat.loadChannelThreads(site, 9, more: true);
      expect(ids(), [2, 1]);

      pages[firstPage] = ChatThreadPage(
        threads: [listedThread(3), listedThread(1)],
        hasMore: true,
      );
      await subject.chat.loadChannelThreads(site, 9, revalidate: true);

      expect(ids(), [3, 2, 1]);
      expect(subject.chat.channelThreadsHaveMore(site, 9), isTrue);

      // Thread 3 pushed the server's second page down by one row.
      await subject.chat.loadChannelThreads(site, 9, more: true);

      expect(
        api.chatChannelThreadPagesRequested.map((request) => request.offset),
        [0, 1, 0, 3],
      );
      expect(ids(), [4, 3, 2, 1]);
      expect(subject.chat.channelThreadsHaveMore(site, 9), isFalse);
    },
  );

  test(
    'a failed channel threads revalidation keeps the held list quietly',
    () async {
      final firstPage = FakeDiscourseApi.chatChannelThreadPageKey(9, 0);
      final pages = {
        firstPage: ChatThreadPage(threads: [listedThread(1)]),
      };
      final api = FakeDiscourseApi(
        chatChannelsBySite: {
          site: ChatChannels(public: [followedChannel()]),
        },
        chatChannelThreadPagesByKey: pages,
      );
      final subject = _controllerFor(api);
      await subject.chat.loadChannels(site);
      await subject.chat.loadChannelThreads(site, 9);

      pages.remove(firstPage);
      await subject.chat.loadChannelThreads(site, 9, revalidate: true);

      expect(api.chatChannelThreadPagesRequested, hasLength(2));
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        1,
      ]);
      expect(subject.chat.channelThreadsError(site, 9), isNull);
    },
  );

  test(
    'a channel threads revalidation joins a first page already in flight',
    () async {
      final api = FakeDiscourseApi(
        chatChannelsBySite: {
          site: ChatChannels(public: [followedChannel()]),
        },
        chatChannelThreadPagesByKey: {
          FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
            threads: [listedThread(1)],
          ),
        },
      );
      final subject = _controllerFor(api);
      await subject.chat.loadChannels(site);

      final first = subject.chat.loadChannelThreads(site, 9);
      final revalidation = subject.chat.loadChannelThreads(
        site,
        9,
        revalidate: true,
      );
      await Future.wait([first, revalidation]);

      expect(api.chatChannelThreadPagesRequested, hasLength(1));
      expect(subject.chat.channelThreads(site, 9).map((thread) => thread.id), [
        1,
      ]);
    },
  );

  test(
    'a channel threads revalidation supersedes a page already in flight',
    () async {
      final api = _SequencedThreadListApi(
        chatChannelsBySite: {
          site: ChatChannels(public: [followedChannel()]),
        },
      );
      final subject = _controllerFor(api);
      Iterable<int> ids() =>
          subject.chat.channelThreads(site, 9).map((thread) => thread.id);
      await subject.chat.loadChannels(site);

      final initialStarted = api.nextChannelThreadPage();
      final initial = subject.chat.loadChannelThreads(site, 9);
      await initialStarted;
      api.channelThreadPages[0].complete(
        ChatThreadPage(threads: [listedThread(1)], hasMore: true),
      );
      await initial;

      final pageStarted = api.nextChannelThreadPage();
      final page = subject.chat.loadChannelThreads(site, 9, more: true);
      await pageStarted;
      final revalidationStarted = api.nextChannelThreadPage();
      final revalidation = subject.chat.loadChannelThreads(
        site,
        9,
        revalidate: true,
      );
      api.channelThreadPages[1].complete(
        ChatThreadPage(threads: [listedThread(2)]),
      );
      await page;

      expect(ids(), [1]);
      await revalidationStarted;
      api.channelThreadPages[2].complete(
        ChatThreadPage(
          threads: [listedThread(3), listedThread(1)],
          hasMore: true,
        ),
      );
      await revalidation;

      expect(ids(), [3, 1]);
      expect(subject.chat.channelThreadsHaveMore(site, 9), isTrue);
      expect(subject.chat.channelThreadsLoadingMore(site, 9), isFalse);

      final nextStarted = api.nextChannelThreadPage();
      final next = subject.chat.loadChannelThreads(site, 9, more: true);
      await nextStarted;
      expect(
        api.chatChannelThreadPagesRequested.map((request) => request.offset),
        [0, 1, 0, 2],
      );
      api.channelThreadPages[3].complete(
        ChatThreadPage(threads: [listedThread(2)]),
      );
      await next;
      expect(ids(), [3, 2, 1]);
    },
  );

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
    'opening a thread waits for detail, stores its cursor, then targets messages',
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

  test('jump to latest in a thread lands after its read marker', () async {
    final api = _AdversarialThreadApi(
      detail: threadDetail(),
      pages: {
        'thread-9-22~target~17': threadPage([
          16,
          17,
          18,
        ], canLoadMoreFuture: true),
        'thread-9-22': threadPage([17, 18, 40], targetMessageId: 17),
      },
    );
    final subject = _controllerFor(api);
    await subject.chat.openThread(site, target, targetMessageId: 17);
    expect(subject.chat.streamFor(site, target).anchorMessageId, 17);

    await subject.chat.showLatestFor(site, target);

    final stream = subject.chat.streamFor(site, target);
    expect(stream.anchorMessageId, 40);
    expect(stream.lastReadOnOpen, 17);
    expect(stream.atPresent, isTrue);
  });

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

  testWidgets('a notice expires when its listener starts history paging', (
    tester,
  ) async {
    final api = _AdversarialThreadApi(
      detail: threadDetail(),
      missingTargetMessageId: 999,
      pages: {
        'thread-9-22': threadPage([16, 17, 18], canLoadMorePast: true),
        'thread-9-22~past~16': threadPage([15]),
      },
    );
    final subject = _controllerFor(api);
    final stream = subject.chat.streamListenableFor(site, target);
    Future<void>? paging;
    var pagingStarted = false;
    void loadHistoryOnNotice() {
      if (stream.value.notice != null && !pagingStarted) {
        pagingStarted = true;
        paging = subject.chat.loadOlderFor(site, target);
      }
    }

    stream.addListener(loadHistoryOnNotice);

    await subject.chat.openThread(site, target, targetMessageId: 999);
    expect(paging, isNotNull);
    await paging;
    expect(stream.value.messageIds, [15, 16, 17, 18]);
    expect(stream.value.notice, isNotNull);

    await tester.pump(const Duration(seconds: 4));

    expect(stream.value.notice, isNull);
    stream.removeListener(loadHistoryOnNotice);
  });

  test(
    'sending a thread reply includes its ID and never enters the channel stream',
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

  group('thread title permissions', () {
    for (final (label, title, valid) in [
      ('empty', '', true),
      ('100 ASCII', 'a' * 100, true),
      ('100 emoji', '🧵' * 100, true),
      ('100 combining scalars', 'e\u0301' * 50, true),
      ('101 ASCII', 'a' * 101, false),
      ('101 emoji', '🧵' * 101, false),
      ('102 combining scalars', 'e\u0301' * 51, false),
    ]) {
      test('$label title follows the server character limit', () async {
        final detail = threadDetail(originalAuthorId: currentUser.id!);
        final api = _AdversarialThreadApi(detail: detail);
        final store = Store()..put(site, detail);
        final subject = _controllerFor(api, store: store);

        expect(
          await subject.chat.updateThreadTitle(site, target, title),
          valid,
        );
        expect(
          api.chatThreadTitlesUpdated,
          valid
              ? [
                  (
                    channelId: target.channelId,
                    threadId: target.threadId,
                    title: title,
                  ),
                ]
              : isEmpty,
        );
        expect(
          subject.chat.thread(site, target.threadId)?.title,
          valid ? title : null,
        );
      });
    }

    for (final kind in ChatChannelKind.values) {
      for (final staff in [false, true]) {
        test(
          '${kind.name} ${staff ? "staff" : "author"} rename follows silence without changing closed-channel policy',
          () async {
            final detail = threadDetail(
              originalAuthorId: staff ? 2 : currentUser.id!,
            );
            final api = _AdversarialThreadApi(detail: detail);
            final store = Store()..put(site, detail);
            final subject = _controllerFor(
              api,
              store: store,
              user: DiscourseUser(id: 7, username: 'reader', staff: staff),
            );
            store.put(site, followedChannel(kind: kind, userSilenced: true));
            expect(subject.chat.canEditThreadTitle(site, detail), isFalse);
            expect(
              await subject.chat.updateThreadTitle(site, target, 'Blocked'),
              isFalse,
            );
            expect(api.chatThreadTitlesUpdated, isEmpty);
            expect(subject.chat.thread(site, 22)?.title, isNull);

            store.put(
              site,
              followedChannel(kind: kind, status: ChatChannelStatus.closed),
            );
            expect(subject.chat.canEditThreadTitle(site, detail), isTrue);
            expect(
              await subject.chat.updateThreadTitle(site, target, 'Allowed'),
              isTrue,
            );
            expect(api.chatThreadTitlesUpdated, const [
              (channelId: 9, threadId: 22, title: 'Allowed'),
            ]);
            expect(subject.chat.thread(site, 22)?.title, 'Allowed');
          },
        );

        test(
          '${kind.name} silenced ${staff ? "staff" : "author"} cannot restore or create threads',
          () async {
            final api = _AdversarialThreadApi(detail: threadDetail());
            final message = ChatMessage(
              id: 100,
              channelId: 9,
              cooked: '<p>Deleted</p>',
              author: const ChatMessageAuthor(id: 7, username: 'reader'),
              deletedAt: DateTime.utc(2026),
              deletedById: 7,
            );
            final store = Store()
              ..put(site, message)
              ..put(site, followedChannel(kind: kind, userSilenced: true));
            final subject = _controllerFor(
              api,
              store: store,
              user: DiscourseUser(id: 7, username: 'reader', staff: staff),
            );
            expect(subject.chat.canRestoreMessage(site, message), isFalse);
            expect(await subject.chat.restoreMessage(site, 100), isNotNull);
            expect(
              await subject.chat.createThread(
                site,
                channelId: 9,
                originalMessageId: 100,
              ),
              isNull,
            );
            expect(api.chatMessagesRestored, isEmpty);
            expect(api.chatThreadsCreated, isEmpty);
          },
        );
      }
    }

    test(
      'silence received during credential lookup prevents the rename request',
      () async {
        final detail = threadDetail(originalAuthorId: 7);
        final api = _AdversarialThreadApi(detail: detail);
        final credentials = _HeldTitleCredentials();
        final store = Store()
          ..put(site, detail)
          ..put(site, followedChannel());
        final subject = _controllerFor(
          api,
          store: store,
          credentials: credentials,
        );
        final saving = subject.chat.updateThreadTitle(site, target, 'Blocked');
        await credentials.started.future;
        store.put(site, followedChannel(userSilenced: true));
        credentials.key.complete('key');
        expect(await saving, isFalse);
        expect(api.chatThreadTitlesUpdated, isEmpty);
        expect(subject.chat.thread(site, 22)?.title, isNull);
      },
    );

    test('the original author can update the title', () async {
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

    test('ordinary participants cannot update the title', () async {
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

    test('staff can update another author\'s title', () async {
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
      expect(api.chatThreadTitlesUpdated, const [
        (channelId: 9, threadId: 22, title: 'Moderated title'),
      ]);
      expect(
        subject.chat.thread(site, target.threadId)?.title,
        'Moderated title',
      );
    });
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
    'a refused notification level keeps a read made while it was in flight',
    () async {
      final api = _AdversarialThreadApi(detail: threadDetail())
        ..holdNotification(
          failure: const WriteException(WriteFailure.unreachable),
        );
      final store = Store()..put(site, threadDetail());
      final subject = _controllerFor(api, store: store);

      final updating = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.watching,
      );
      await api.notificationStarted!.future;
      await subject.chat.markReadFor(site, target, 40);
      expect(api.threadReads, const [
        (channelId: 9, threadId: 22, messageId: 40),
      ]);
      api.notificationGate!.complete();

      expect(await updating, isFalse);
      final membership = subject.chat.thread(site, 22)?.membership;
      expect(
        membership?.notificationLevel,
        ChatThreadNotificationLevel.tracking,
      );
      expect(membership?.lastReadMessageId, 40);
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

  test('a read echo clears a tracked thread back to zero unread', () async {
    final api = _AdversarialThreadApi(
      detail: threadDetail(),
      channels: {
        site: ChatChannels(public: [followedChannel()]),
      },
    );
    final store = Store()
      ..put(
        site,
        threadDetail().copyWith(tracking: const ChatTracking(unreadCount: 2)),
      );
    final subject = _controllerFor(api, store: store);
    final tracker = attachTracker(subject.chat);
    await subject.chat.loadChannels(site);

    tracker.deliverPluginMessage(
      '/chat/user-tracking-state/7',
      threadReadEcho(40),
    );

    final held = subject.chat.thread(site, 22)!;
    expect(held.tracking, ChatTracking.none);
    expect(held.membership?.lastReadMessageId, 40);
  });

  test(
    'a read thread stays read through its echo and a my-threads refresh',
    () async {
      final api = FakeDiscourseApi(
        chatChannelsBySite: {
          site: ChatChannels(
            public: [followedChannel()],
            newMessageBusLastIds: const {9: 80},
          ),
        },
        chatThreadPagesByOffset: {},
      );
      final subject = _controllerFor(api);
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      subject.store.put(site, threadDetail());

      tracker.deliverPluginMessage('/chat/9/new-messages', {
        'type': 'thread',
        'channel_id': 9,
        'thread_id': 22,
        'message': {
          'id': 41,
          'chat_channel_id': 9,
          'created_at': '2026-08-12T12:00:00.000Z',
          'user': {'id': 2, 'username': 'sam'},
        },
      });
      expect(subject.chat.thread(site, 22)?.tracking.unreadCount, 1);

      await subject.chat.markReadFor(site, target, 41);
      tracker.deliverPluginMessage(
        '/chat/user-tracking-state/7',
        threadReadEcho(41),
      );
      expect(subject.chat.thread(site, 22)?.tracking, ChatTracking.none);

      // Core leaves a read thread out of the page's tracking map.
      api.chatThreadPagesByOffset[0] = ChatThreadPage.fromJson(const {
        'threads': [
          {
            'id': 22,
            'channel_id': 9,
            'status': 'open',
            'reply_count': 4,
            'current_user_membership': {
              'thread_id': 22,
              'notification_level': 2,
              'last_read_message_id': 41,
            },
          },
        ],
        'tracking': <String, dynamic>{},
      }, site);
      await subject.chat.loadMyThreads(site, force: true);

      expect(subject.chat.myThreads(site).map((thread) => thread.id), [22]);
      expect(subject.chat.thread(site, 22)?.tracking, ChatTracking.none);
    },
  );

  test('a sent thread event inserts only into the thread stream', () async {
    final api = _AdversarialThreadApi(
      detail: threadDetail(),
      pages: {
        'thread-9-22': threadPage([20]),
      },
    );
    final store = Store()..put(site, threadDetail());
    final subject = _controllerFor(api, store: store);
    final tracker = attachTracker(subject.chat);
    final view = subject.chat.beginViewingThread(site, target);
    addTearDown(() => subject.chat.endViewingThread(site, target, view));
    await subject.chat.openThread(site, target);

    tracker.deliverPluginMessage('/chat/9/thread/22', threadSentEvent(30));

    expect(subject.chat.streamFor(site, target).messageIds, [20, 30]);
    expect(subject.chat.stream(site, target.channelId).messageIds, isEmpty);
    expect(subject.store.read<ChatMessage>(site, 30)?.threadId, 22);
  });

  test(
    'a viewed thread pages forward past replies its trimmed backlog dropped',
    () async {
      var now = DateTime.utc(2026, 8, 12, 12);
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        pages: {
          'thread-9-22': threadPage([20, 21]),
          'thread-9-22~future~21': threadPage([22, 23]),
        },
      );
      final store = Store()..put(site, threadDetail());
      final subject = _controllerFor(api, store: store, clock: () => now);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingThread(site, target);
      addTearDown(() => subject.chat.endViewingThread(site, target, view));
      await subject.chat.openThread(site, target);
      final opened = subject.chat.streamFor(site, target);

      subject.chat.setForeground(false);
      now = now.add(ChatController.resumeResyncThreshold);
      subject.chat.setForeground(true);
      // 22 fell out of the thread channel's backlog; only 23 is replayed.
      tracker.deliverPluginMessage('/chat/9/thread/22', threadSentEvent(23));
      expect(subject.chat.streamFor(site, target).messageIds, [20, 21]);
      await pumpEventQueue();

      final stream = subject.chat.streamFor(site, target);
      expect(api.chatThreadMessagesRequested.last.after, 21);
      expect(stream.messageIds, [20, 21, 22, 23]);
      expect(stream.atPresent, isTrue);
      expect(stream.fetches, opened.fetches);
    },
  );

  test(
    'a replayed thread reply waits for the page that establishes the window',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        holdDetail: true,
        holdMessages: true,
        pages: {
          'thread-9-22': threadPage([20, 30]),
        },
      );
      // Opening from My threads subscribes at the listed record's cursor, so
      // the bus replays replies published since the list loaded.
      final store = Store()..put(site, threadDetail());
      final subject = _controllerFor(api, store: store);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingThread(site, target);
      addTearDown(() => subject.chat.endViewingThread(site, target, view));

      final opening = subject.chat.openThread(site, target);
      await api.detailStarted!.future;
      tracker.deliverPluginMessage('/chat/9/thread/22', threadSentEvent(30));
      expect(subject.chat.streamFor(site, target).messageIds, isEmpty);

      api.detailGate!.complete();
      await api.messagesStarted!.future;
      tracker.deliverPluginMessage('/chat/9/thread/22', threadSentEvent(31));
      final loading = subject.chat.streamFor(site, target);
      expect(loading.loading, isTrue);
      expect(loading.messageIds, isEmpty);
      expect(loading.pendingNewMessages, 0);

      api.messagesGate!.complete();
      await opening;

      final stream = subject.chat.streamFor(site, target);
      expect(stream.messageIds, [20, 30, 31]);
      expect(stream.atPresent, isTrue);
    },
  );

  test(
    'a failed thread page is not hidden by a reply replayed during it',
    () async {
      final api = _AdversarialThreadApi(
        detail: threadDetail(),
        holdMessages: true,
      );
      final store = Store()..put(site, threadDetail());
      final subject = _controllerFor(api, store: store);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingThread(site, target);
      addTearDown(() => subject.chat.endViewingThread(site, target, view));

      final opening = subject.chat.openThread(site, target);
      await api.messagesStarted!.future;
      tracker.deliverPluginMessage('/chat/9/thread/22', threadSentEvent(30));
      api.messagesGate!.complete();
      await opening;

      final stream = subject.chat.streamFor(site, target);
      expect(stream.messageIds, isEmpty);
      expect(stream.error, 'Could not load this thread.');
    },
  );

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
        participantCount: 2,
        participantUsers: [
          ChatMessageAuthor(id: 2, username: 'sam'),
          ChatMessageAuthor(id: 3, username: 'lee'),
        ],
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
    'a stream listener can refresh detail during its initial publication',
    () async {
      final api = _SequencedDetailApi();
      final subject = _controllerFor(api);
      final stream = subject.chat.streamListenableFor(site, target);
      final failed = subject.chat.refreshThreadDetail(site, target);
      await waitUntil(() => api.calls == 1);
      api.responses[0].completeError(
        const SiteLookupException(
          SiteLookupFailure.unreachable,
          site,
          statusCode: 404,
        ),
      );
      await failed;
      Future<ChatThread?>? reentrant;
      Object? reentrantError;
      var joined = false;
      void refreshOnce() {
        if (joined) return;
        joined = true;
        try {
          reentrant = subject.chat.refreshThreadDetail(site, target);
        } catch (error) {
          reentrantError = error;
        }
      }

      stream.addListener(refreshOnce);
      addTearDown(() => stream.removeListener(refreshOnce));
      final refreshing = subject.chat.refreshThreadDetail(site, target);
      await waitUntil(() => api.calls == 2);
      api.responses[1].complete(threadDetail(title: 'Current'));
      await refreshing;
      await reentrant;

      expect(joined, isTrue);
      expect(reentrantError, isNull);
      expect(subject.chat.thread(site, 22)?.title, 'Current');
    },
  );

  test(
    'a title write dirties an older detail without losing its waiters',
    () async {
      final api = _SequencedDetailApi();
      final store = Store()
        ..put(site, threadDetail(title: 'Before', originalAuthorId: 7));
      final subject = _controllerFor(api, store: store);

      final refreshing = subject.chat.refreshThreadDetail(site, target);
      await waitUntil(() => api.calls == 1);
      expect(
        await subject.chat.updateThreadTitle(site, target, 'After'),
        isTrue,
      );
      api.responses[0].complete(threadDetail(title: 'Before'));
      await waitUntil(() => api.calls == 2);
      expect(subject.chat.thread(site, 22)?.title, 'After');
      api.responses[1].complete(threadDetail(title: 'After'));

      expect((await refreshing)?.title, 'After');
      expect(subject.chat.thread(site, 22)?.title, 'After');
    },
  );

  test(
    'a forgotten title completion cannot clear its replacement write',
    () async {
      final api = _SequencedTitleApi();
      final credentials = FakeApiCredentialReader()..keys[site] = 'key';
      final requests = FakePluginRequestHost(credentials: credentials);
      final store = Store()
        ..put(site, threadDetail(title: 'Old account', originalAuthorId: 7));
      final subject = _controllerFor(api, store: store, requests: requests);

      final old = subject.chat.updateThreadTitle(site, target, 'Old title');
      await waitUntil(() => api.responses.length == 1);
      requests.lifecycle.invalidate(site);
      subject.chat.forget(site);
      store.put(
        site,
        threadDetail(title: 'Replacement account', originalAuthorId: 7),
      );
      final replacement = subject.chat.updateThreadTitle(
        site,
        target,
        'Replacement title',
      );
      await waitUntil(() => api.responses.length == 2);
      api.responses[0].complete();

      expect(await old, isFalse);
      expect(subject.chat.thread(site, 22)?.title, 'Replacement account');
      expect(
        await subject.chat.updateThreadTitle(site, target, 'Overlapping title'),
        isFalse,
      );
      expect(api.chatThreadTitlesUpdated, hasLength(2));
      api.responses[1].complete();
      expect(await replacement, isTrue);
      expect(subject.chat.thread(site, 22)?.title, 'Replacement title');

      final next = subject.chat.updateThreadTitle(site, target, 'Next title');
      await waitUntil(() => api.responses.length == 3);
      api.responses[2].complete();
      expect(await next, isTrue);
      expect(subject.chat.thread(site, 22)?.title, 'Next title');
    },
  );

  test(
    'a forgotten detail completion cannot clear its replacement request',
    () async {
      final api = _SequencedDetailApi();
      final credentials = FakeApiCredentialReader()..keys[site] = 'key';
      final requests = FakePluginRequestHost(credentials: credentials);
      final subject = _controllerFor(api, requests: requests);

      final old = subject.chat.refreshThreadDetail(site, target);
      await waitUntil(() => api.calls == 1);
      requests.lifecycle.invalidate(site);
      subject.chat.forget(site);
      final replacement = subject.chat.refreshThreadDetail(site, target);
      await waitUntil(() => api.calls == 2);
      api.responses[0].complete(threadDetail(title: 'Old account'));
      expect(await old, isNull);
      final joined = subject.chat.refreshThreadDetail(site, target);
      expect(identical(joined, replacement), isTrue);
      api.responses[1].complete(threadDetail(title: 'Dirty replacement'));
      await waitUntil(() => api.calls == 3);
      api.responses[2].complete(threadDetail(title: 'Current account'));

      expect((await replacement)?.title, 'Current account');
      expect(subject.chat.thread(site, 22)?.title, 'Current account');
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
    'notification queues let independent threads finish separately',
    () async {
      final api = _SequencedNotificationApi();
      const otherTarget = ChatThreadTarget(channelId: 9, threadId: 23);
      final store = Store()
        ..put(site, threadDetail())
        ..put(
          site,
          listedThread(
            23,
            membership: const ChatThreadMembership(
              threadId: 23,
              notificationLevel: ChatThreadNotificationLevel.tracking,
              lastReadMessageId: 230,
            ),
          ),
        );
      final subject = _controllerFor(api, store: store);

      final first = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.watching,
      );
      await waitUntil(() => api.pending.length == 1);
      final queued = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.muted,
      );
      final other = subject.chat.updateThreadNotificationLevel(
        site,
        otherTarget,
        ChatThreadNotificationLevel.normal,
      );
      await waitUntil(() => api.pending.length == 2);
      expect(
        api.chatThreadNotificationLevelsUpdated.map(
          (request) => request.threadId,
        ),
        [22, 23],
      );
      api.pending[1].response.complete(
        const ChatThreadMembership(
          threadId: 23,
          notificationLevel: ChatThreadNotificationLevel.normal,
          lastReadMessageId: 230,
        ),
      );

      expect(await other, isTrue);
      expect(
        subject.chat.thread(site, 23)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.normal,
      );
      expect(
        subject.chat.thread(site, 22)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.muted,
      );
      api.pending[0].response.complete(
        const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.watching,
          lastReadMessageId: 17,
        ),
      );
      await waitUntil(() => api.pending.length == 3);
      api.pending[2].response.complete(
        const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.muted,
          lastReadMessageId: 17,
        ),
      );

      expect(await first, isTrue);
      expect(await queued, isTrue);
      expect(
        subject.chat.thread(site, 22)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.muted,
      );
      expect(
        subject.chat.thread(site, 23)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.normal,
      );
      expect(
        api.chatThreadNotificationLevelsUpdated.map(
          (request) => request.threadId,
        ),
        [22, 23, 22],
      );
    },
  );

  test(
    'notification rollback keeps a read cursor moved backward by deletion',
    () async {
      final api = _SequencedNotificationApi();
      final detail = threadDetail(lastMessageId: 30).copyWith(
        membership: const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.tracking,
          lastReadMessageId: 30,
        ),
      );
      final store = Store()
        ..put(site, detail)
        ..put(site, threadMessage(30));
      final subject = _controllerFor(api, store: store);
      final tracker = attachTracker(subject.chat);
      final view = subject.chat.beginViewingThread(site, target);
      addTearDown(() => subject.chat.endViewingThread(site, target, view));

      final updating = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.muted,
      );
      await waitUntil(() => api.pending.length == 1);
      tracker.deliverPluginMessage('/chat/9/thread/22', {
        'type': 'delete',
        'deleted_id': 30,
        'deleted_at': '2026-08-12T12:01:00.000Z',
        'latest_not_deleted_message_id': 29,
      });
      expect(subject.chat.thread(site, 22)?.membership?.lastReadMessageId, 29);
      api.pending.single.response.completeError(
        const WriteException(WriteFailure.unreachable),
      );

      expect(await updating, isFalse);
      final membership = subject.chat.thread(site, 22)?.membership;
      expect(
        membership?.notificationLevel,
        ChatThreadNotificationLevel.tracking,
      );
      expect(membership?.lastReadMessageId, 29);
      expect(subject.chat.thread(site, 22)?.lastMessageId, 29);
      expect(subject.store.read<ChatMessage>(site, 30), isNull);
    },
  );

  test(
    'a queued notification rollback keeps the earlier success and newer read',
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
      final skipped = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.normal,
      );
      final latest = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.muted,
      );
      await subject.chat.markReadFor(site, target, 40);
      api.pending[0].response.complete(
        const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.watching,
          lastReadMessageId: 17,
        ),
      );
      await waitUntil(() => api.pending.length == 2);
      expect(await skipped, isFalse);
      expect(api.pending.last.level, ChatThreadNotificationLevel.muted);
      api.pending.last.response.completeError(
        const WriteException(WriteFailure.unreachable),
      );

      expect(await first, isTrue);
      expect(await latest, isFalse);
      final membership = subject.chat.thread(site, 22)?.membership;
      expect(
        membership?.notificationLevel,
        ChatThreadNotificationLevel.watching,
      );
      expect(membership?.lastReadMessageId, 40);
    },
  );

  test(
    'a forgotten notification completion cannot clear its replacement queue',
    () async {
      final api = _SequencedNotificationApi();
      final credentials = FakeApiCredentialReader()..keys[site] = 'key';
      final requests = FakePluginRequestHost(credentials: credentials);
      final store = Store()..put(site, threadDetail());
      final subject = _controllerFor(api, store: store, requests: requests);

      final old = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.watching,
      );
      await waitUntil(() => api.pending.length == 1);
      requests.lifecycle.invalidate(site);
      subject.chat.forget(site);
      store.put(site, threadDetail());
      final replacement = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.muted,
      );
      await waitUntil(() => api.pending.length == 2);
      api.pending[0].response.complete(
        const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.watching,
        ),
      );
      expect(await old, isFalse);
      final latest = subject.chat.updateThreadNotificationLevel(
        site,
        target,
        ChatThreadNotificationLevel.normal,
      );
      await Future<void>.delayed(Duration.zero);
      expect(api.pending, hasLength(2));
      api.pending[1].response.complete(
        const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.muted,
        ),
      );
      await waitUntil(() => api.pending.length == 3);
      api.pending[2].response.completeError(
        const WriteException(WriteFailure.unreachable),
      );

      expect(await replacement, isTrue);
      expect(await latest, isFalse);
      expect(
        subject.chat.thread(site, 22)?.membership?.notificationLevel,
        ChatThreadNotificationLevel.muted,
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
      expect(subject.chat.channel(site, 9)?.unreadThreadOverview, {
        22: DateTime.utc(2026, 8, 12, 12),
      });
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

final class _HeldTitleCredentials extends FakeApiCredentialReader {
  final started = Completer<void>();
  final key = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    started.complete();
    return key.future;
  }
}
