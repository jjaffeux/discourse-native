import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const String site = 'https://meta.discourse.org';
const String other = 'https://other.example';

ChatMessage message(
  int id, {
  int second = 0,
  int minute = 0,
  List<ChatReaction> reactions = const [],
}) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>$id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: DateTime.utc(2026, 5, 5, 10, minute, second),
  reactions: reactions,
);

ChatMessagePage page(
  List<ChatMessage> messages, {
  bool canLoadMorePast = false,
  bool canLoadMoreFuture = false,
}) => (
  messages: messages,
  canLoadMorePast: canLoadMorePast,
  canLoadMoreFuture: canLoadMoreFuture,
  targetMessageId: null,
);

/// Followed by default, which is the only kind `/chat/api/me/channels` returns.
ChatChannel channel(
  int id, {
  String title = 'Bugs',
  ChatChannelKind kind = ChatChannelKind.category,
  bool following = true,
  bool muted = false,
  bool starred = false,
  int? lastRead,
  int unread = 0,
  int mentions = 0,
  int watchedThreads = 0,
  int unreadThreads = 0,
  bool threadingEnabled = false,
  DateTime? lastViewedAt,
  Map<int, DateTime>? unreadThreadOverview,
  int? lastMessageId,
  DateTime? lastMessageAt,
}) => ChatChannel(
  id: id,
  title: title,
  kind: kind,
  membership: ChatMembership(
    following: following,
    muted: muted,
    starred: starred,
    lastReadMessageId: lastRead,
    lastViewedAt: lastViewedAt,
  ),
  tracking: ChatTracking(
    unreadCount: unread,
    mentionCount: mentions,
    watchedThreadsUnreadCount: watchedThreads,
  ),
  unreadThreadOverview:
      unreadThreadOverview ??
      {
        for (var index = 0; index < unreadThreads; index++)
          index + 1: DateTime.utc(2026, 8, 8, 9, index),
      },
  threadingEnabled: threadingEnabled || unreadThreads > 0,
  lastMessageId: lastMessageId,
  lastMessageAt: lastMessageAt,
);

/// A controller wired to a fake site the reader is already signed in to.
({ChatController chat, FakeDiscourseApi api, Store store}) build({
  Map<String, ChatChannels> channels = const {},
  Map<String, ChatMessagePage> messages = const {},
  Completer<void>? channelGate,
  Completer<void>? messageGate,
  WriteException? readFailure,
  WriteException? sendFailure,
  Completer<void>? sendGate,
  int? sentMessageId = 1,
  WriteException? reactionFailure,
  Completer<void>? reactionGate,
  Map<String, ChatMessageReactors> chatReactors = const {},
  Completer<void>? reactorReadGate,
  FakeApiCredentialReader? credentialReader,
  DiscourseUser? currentUser,
  ChatNotificationsDelta? onChatNotificationsDelta,
  void Function(String)? onSiteUnreachable,
  Duration minimumWindowRefreshInterval = const Duration(seconds: 30),
  DateTime Function()? clock,
}) {
  final api = FakeDiscourseApi(
    chatChannelsBySite: channels,
    chatChannelGate: channelGate,
    chatMessagesByKey: messages,
    chatMessageGate: messageGate,
    chatReadFailure: readFailure,
    chatSendFailure: sendFailure,
    chatSendGate: sendGate,
    chatSentMessageId: sentMessageId,
    chatReactionFailure: reactionFailure,
    chatReactionGate: reactionGate,
    chatReactorsById: chatReactors,
    chatReactorGate: reactorReadGate,
  );
  final credentials = credentialReader ?? FakeApiCredentialReader();
  credentials.keys[site] = 'key';
  final store = Store();
  return (
    chat: ChatController(
      api: api,
      credentials: credentials,
      store: store,
      currentUserFor: (_) => currentUser,
      onChatNotificationsDelta: onChatNotificationsDelta,
      onSiteUnreachable: onSiteUnreachable,
      minimumWindowRefreshInterval: minimumWindowRefreshInterval,
      clock: clock,
    ),
    api: api,
    store: store,
  );
}

final class _GatedCredentials extends FakeApiCredentialReader {
  _GatedCredentials(this.gate);

  final Completer<void> gate;
  final started = Completer<void>();

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (!started.isCompleted) started.complete();
    await gate.future;
    return keys[siteUrl];
  }
}

final class _ControllableCredentials extends FakeApiCredentialReader {
  Completer<void>? _apiKeyGate;
  Completer<void>? _clientIdGate;
  Completer<void>? _apiKeyStarted;
  Completer<void>? _clientIdStarted;

  int apiKeyCalls = 0;
  int clientIdCalls = 0;

  Future<void> blockApiKey() {
    _apiKeyGate = Completer<void>();
    _apiKeyStarted = Completer<void>();
    return _apiKeyStarted!.future;
  }

  Future<void> blockClientId() {
    _clientIdGate = Completer<void>();
    _clientIdStarted = Completer<void>();
    return _clientIdStarted!.future;
  }

  void releaseApiKey() {
    _apiKeyGate?.complete();
    _apiKeyGate = null;
  }

  void releaseClientId() {
    _clientIdGate?.complete();
    _clientIdGate = null;
  }

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    apiKeyCalls++;
    final gate = _apiKeyGate;
    if (gate != null) {
      if (!(_apiKeyStarted?.isCompleted ?? true)) _apiKeyStarted!.complete();
      await gate.future;
    }
    return keys[siteUrl];
  }

  @override
  Future<String> clientId() async {
    clientIdCalls++;
    final gate = _clientIdGate;
    if (gate != null) {
      if (!(_clientIdStarted?.isCompleted ?? true)) {
        _clientIdStarted!.complete();
      }
      await gate.future;
    }
    return super.clientId();
  }
}

String key(int channelId, {int? before, int? after}) =>
    FakeDiscourseApi.chatMessagesKey(channelId, before: before, after: after);

String latestKey(int channelId) =>
    FakeDiscourseApi.chatMessagesLatestKey(channelId);

const DiscourseUser currentUser = DiscourseUser(
  id: 7,
  username: 'reader',
  name: 'Reader',
  avatarUrl: 'https://meta.discourse.org/avatar.png',
);

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

Map<String, dynamic> sentEvent({
  required String stagedId,
  int serverId = 42,
  String cooked = '<p>hello chat</p>',
}) => {
  'type': 'sent',
  'staged_id': stagedId,
  'chat_message': {
    'id': serverId,
    'chat_channel_id': 9,
    'cooked': cooked,
    'created_at': '2026-05-05T10:01:00.000Z',
    'user': {
      'id': currentUser.id,
      'username': currentUser.username,
      'name': currentUser.name,
      'avatar_template': '/avatar/{size}.png',
    },
  },
};

Map<String, dynamic> newMessageEvent({
  required int channelId,
  required int messageId,
  required int authorId,
  required String createdAt,
  String authorUsername = 'author',
  String type = 'channel',
  int? threadId,
}) => {
  'type': type,
  'channel_id': channelId,
  'thread_id': ?threadId,
  'message': {
    'id': messageId,
    'chat_channel_id': channelId,
    'cooked': '<p>new</p>',
    'created_at': createdAt,
    'user': {'id': authorId, 'username': authorUsername},
  },
};

Map<String, dynamic> newDirectChannelEvent({
  required int channelId,
  required int messageId,
  required int newMessagesLastId,
  String title = 'New conversation',
  String createdAt = '2026-08-08T13:00:00.000Z',
}) => {
  'channel': {
    'id': channelId,
    'title': title,
    'chatable_type': 'DirectMessage',
    'chatable': {
      'group': false,
      'users': [
        {'id': 2, 'username': 'hawk'},
      ],
    },
    'current_user_membership': {
      'following': true,
      'muted': false,
      'starred': false,
    },
    'last_message': {'id': messageId, 'created_at': createdAt},
    'meta': {
      'message_bus_last_ids': {'new_messages': newMessagesLastId},
    },
  },
};

void main() {
  // The controller uses frame-safe notifiers, whose scheduler-phase check needs
  // a binding even in these non-widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loading a site’s channels', () {
    test(
      'puts the channels in the store and keeps the order it was given',
      () async {
        final subject = build(
          channels: {
            site: ChatChannels(
              public: [channel(9), channel(4)],
              direct: [channel(12)],
            ),
          },
        );

        await subject.chat.loadChannels(site);

        expect(subject.chat.publicChannels(site).map((c) => c.id), [9, 4]);
        expect(subject.chat.directChannels(site).map((c) => c.id), [12]);
        expect(subject.store.read<ChatChannel>(site, 9)!.title, 'Bugs');
      },
    );

    test(
      'groups starred channels without dropping them from aggregate reads',
      () async {
        final subject = build(
          channels: {
            site: ChatChannels(
              public: [
                channel(9, title: 'Alpha', starred: true),
                channel(4, title: 'Beta'),
              ],
              direct: [
                channel(12, title: 'Zoe', starred: true),
                channel(13, title: 'Alice', starred: true),
                channel(14, title: 'Sam'),
              ],
            ),
          },
        );

        await subject.chat.loadChannels(site);

        expect(subject.chat.starredChannels(site).map((c) => c.id), [
          9,
          13,
          12,
        ]);
        expect(subject.chat.unstarredPublicChannels(site).map((c) => c.id), [
          4,
        ]);
        expect(subject.chat.unstarredDirectChannels(site).map((c) => c.id), [
          14,
        ]);
        expect(subject.chat.publicChannels(site).map((c) => c.id), [9, 4]);
        expect(subject.chat.directChannels(site).map((c) => c.id), [
          12,
          13,
          14,
        ]);
      },
    );

    test('sorts unstarred direct messages like the web sidebar', () async {
      final subject = build(
        channels: {
          site: ChatChannels(
            direct: [
              channel(
                12,
                title: 'Recent read',
                kind: ChatChannelKind.directMessage,
                lastMessageId: 50,
                lastMessageAt: DateTime.utc(2026, 8, 8, 12),
              ),
              channel(
                13,
                title: 'Older urgent',
                kind: ChatChannelKind.directMessage,
                unread: 1,
                lastMessageId: 40,
                lastMessageAt: DateTime.utc(2026, 8, 8, 10),
              ),
              channel(14, title: 'Empty', kind: ChatChannelKind.directMessage),
            ],
          ),
        },
      );

      await subject.chat.loadChannels(site);

      expect(subject.chat.unstarredDirectChannels(site).map((c) => c.id), [
        13,
        12,
        14,
      ]);
    });

    test(
      'uses unread thread dates after the membership last-viewed time',
      () async {
        final subject = build(
          channels: {
            site: ChatChannels(
              direct: [
                channel(
                  12,
                  kind: ChatChannelKind.directMessage,
                  threadingEnabled: true,
                  lastViewedAt: DateTime.utc(2026, 8, 8, 11),
                  unreadThreadOverview: {31: DateTime.utc(2026, 8, 8, 12)},
                  lastMessageId: 40,
                  lastMessageAt: DateTime.utc(2026, 8, 8, 10),
                ),
                channel(
                  13,
                  kind: ChatChannelKind.directMessage,
                  threadingEnabled: true,
                  lastViewedAt: DateTime.utc(2026, 8, 8, 11),
                  unreadThreadOverview: {32: DateTime.utc(2026, 8, 8, 13)},
                  lastMessageId: 41,
                  lastMessageAt: DateTime.utc(2026, 8, 8, 9),
                ),
                channel(
                  14,
                  kind: ChatChannelKind.directMessage,
                  threadingEnabled: true,
                  lastViewedAt: DateTime.utc(2026, 8, 8, 11),
                  unreadThreadOverview: {33: DateTime.utc(2026, 8, 8, 10)},
                  lastMessageId: 42,
                  lastMessageAt: DateTime.utc(2026, 8, 8, 14),
                ),
              ],
            ),
          },
        );

        await subject.chat.loadChannels(site);

        expect(subject.chat.unstarredDirectChannels(site).map((c) => c.id), [
          13,
          12,
          14,
        ]);
      },
    );

    test(
      'keeps every direct message available without the web browse page',
      () async {
        final subject = build(
          channels: {
            site: ChatChannels(
              direct: [
                for (var id = 1; id <= 75; id++)
                  channel(
                    id,
                    kind: ChatChannelKind.directMessage,
                    title: 'DM $id',
                  ),
              ],
            ),
          },
        );

        await subject.chat.loadChannels(site);

        expect(subject.chat.unstarredDirectChannels(site), hasLength(75));
      },
    );

    test('reorders direct messages when a new-message event arrives', () async {
      final deltas = <int>[];
      final subject = build(
        currentUser: currentUser,
        onChatNotificationsDelta: (_, delta) => deltas.add(delta),
        channels: {
          site: ChatChannels(
            direct: [
              channel(
                12,
                title: 'First',
                kind: ChatChannelKind.directMessage,
                lastMessageId: 50,
                lastMessageAt: DateTime.utc(2026, 8, 8, 12),
              ),
              channel(
                13,
                title: 'Second',
                kind: ChatChannelKind.directMessage,
                lastMessageId: 40,
                lastMessageAt: DateTime.utc(2026, 8, 8, 10),
              ),
            ],
            newMessageBusLastIds: const {12: 71, 13: 72},
          ),
        },
      );
      final tracker = attachTracker(subject.chat);

      await subject.chat.loadChannels(site);

      expect(tracker.pluginChannelLastIds['/chat/12/new-messages'], 71);
      expect(tracker.pluginChannelLastIds['/chat/13/new-messages'], 72);
      tracker.deliverPluginMessage(
        '/chat/13/new-messages',
        newMessageEvent(
          channelId: 13,
          messageId: 60,
          authorId: 2,
          createdAt: '2026-08-08T13:00:00.000Z',
        ),
      );

      expect(subject.chat.unstarredDirectChannels(site).map((c) => c.id), [
        13,
        12,
      ]);
      expect(subject.chat.channel(site, 13)?.tracking.unreadCount, 1);
      expect(subject.chat.channel(site, 13)?.lastMessageId, 60);
      expect(deltas, [1]);

      // MessageBus replay and out-of-order delivery must not double-count.
      tracker.deliverPluginMessage(
        '/chat/13/new-messages',
        newMessageEvent(
          channelId: 13,
          messageId: 60,
          authorId: 2,
          createdAt: '2026-08-08T13:00:00.000Z',
        ),
      );
      expect(subject.chat.channel(site, 13)?.tracking.unreadCount, 1);
      expect(deltas, [1]);

      // A message sent from another client updates activity without becoming
      // unread. The older urgent conversation therefore remains above it;
      // this is intentionally not a blind "move the event to the front".
      tracker.deliverPluginMessage(
        '/chat/12/new-messages',
        newMessageEvent(
          channelId: 12,
          messageId: 70,
          authorId: currentUser.id!,
          createdAt: '2026-08-08T14:00:00.000Z',
        ),
      );
      expect(subject.chat.unstarredDirectChannels(site).map((c) => c.id), [
        13,
        12,
      ]);
      expect(subject.chat.channel(site, 12)?.tracking.unreadCount, 0);
      expect(subject.chat.channel(site, 12)?.membership.lastReadMessageId, 70);
      expect(deltas, [1]);

      subject.chat.forget(site);
      expect(tracker.pluginChannelCallbacks['/chat/12/new-messages'], isEmpty);
      expect(tracker.pluginChannelCallbacks['/chat/13/new-messages'], isEmpty);
    });

    test('adds a live message to a channel window at the present', () async {
      final subject = build(
        currentUser: currentUser,
        channels: {
          site: ChatChannels(
            public: [
              channel(
                9,
                lastRead: 3,
                lastMessageId: 3,
                lastMessageAt: DateTime.utc(2026, 8, 8, 12),
              ),
            ],
            newMessageBusLastIds: const {9: 70},
          ),
        },
        messages: {
          key(9): page([
            message(1),
            message(2, minute: 1),
            message(3, minute: 2),
          ]),
        },
      );
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      await subject.chat.openChannel(site, 9);

      tracker.deliverPluginMessage(
        '/chat/9/new-messages',
        newMessageEvent(
          channelId: 9,
          messageId: 4,
          authorId: 2,
          createdAt: '2026-08-08T13:00:00.000Z',
        ),
      );

      expect(subject.chat.stream(site, 9).messageIds, [1, 2, 3, 4]);
      expect(subject.chat.messages(site, 9).last.id, 4);
      expect(subject.chat.channel(site, 9)?.badge.dot, isTrue);

      await subject.chat.markRead(site, 9, 4);

      expect(subject.chat.channel(site, 9)?.badge.isVisible, isFalse);
      expect(subject.api.chatReadsMarked, [(channelId: 9, messageId: 4)]);
    });

    test(
      'subscribes after either half arrives and skips muted channels',
      () async {
        final subject = build(
          channels: {
            site: ChatChannels(
              public: [channel(9, muted: true)],
              direct: [channel(12, kind: ChatChannelKind.directMessage)],
              newMessageBusLastIds: const {9: 70, 12: 71},
            ),
          },
        );

        await subject.chat.loadChannels(site);
        final tracker = attachTracker(subject.chat);

        expect(
          tracker.pluginChannelCallbacks,
          contains('/chat/12/new-messages'),
        );
        expect(
          tracker.pluginChannelCallbacks,
          isNot(contains('/chat/9/new-messages')),
        );
      },
    );

    test('does not make an ignored author urgent', () async {
      const user = DiscourseUser(
        username: 'sam',
        id: 1,
        ignoredUsernames: ['hawk'],
      );
      final subject = build(
        currentUser: user,
        channels: {
          site: ChatChannels(
            direct: [
              channel(
                12,
                kind: ChatChannelKind.directMessage,
                lastMessageId: 40,
                lastMessageAt: DateTime.utc(2026, 8, 8, 10),
              ),
            ],
            newMessageBusLastIds: const {12: 71},
          ),
        },
      );
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);

      tracker.deliverPluginMessage(
        '/chat/12/new-messages',
        newMessageEvent(
          channelId: 12,
          messageId: 50,
          authorId: 2,
          authorUsername: 'hawk',
          createdAt: '2026-08-08T13:00:00.000Z',
        ),
      );

      expect(subject.chat.channel(site, 12)?.tracking.unreadCount, 0);
      expect(subject.chat.channel(site, 12)?.membership.lastReadMessageId, 50);
    });

    test('uses live DM thread replies in the activity ordering', () async {
      final subject = build(
        currentUser: currentUser,
        channels: {
          site: ChatChannels(
            direct: [
              channel(
                12,
                kind: ChatChannelKind.directMessage,
                threadingEnabled: true,
                lastViewedAt: DateTime.utc(2026, 8, 8, 11),
                lastMessageId: 50,
                lastMessageAt: DateTime.utc(2026, 8, 8, 12),
              ),
              channel(
                13,
                kind: ChatChannelKind.directMessage,
                threadingEnabled: true,
                lastViewedAt: DateTime.utc(2026, 8, 8, 11),
                lastMessageId: 40,
                lastMessageAt: DateTime.utc(2026, 8, 8, 10),
              ),
            ],
            newMessageBusLastIds: const {12: 70, 13: 71},
          ),
        },
      );
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);

      tracker.deliverPluginMessage(
        '/chat/13/new-messages',
        newMessageEvent(
          channelId: 13,
          messageId: 60,
          authorId: 2,
          createdAt: '2026-08-08T13:00:00.000Z',
          type: 'thread',
          threadId: 31,
        ),
      );

      expect(subject.chat.unstarredDirectChannels(site).map((c) => c.id), [
        13,
        12,
      ]);
      expect(subject.chat.channel(site, 13)?.tracking.unreadCount, 0);
      expect(subject.chat.channel(site, 13)?.unreadThreadOverview, {
        31: DateTime.utc(2026, 8, 8, 13),
      });

      tracker.deliverPluginMessage(
        '/chat/13/new-messages',
        newMessageEvent(
          channelId: 13,
          messageId: 61,
          authorId: currentUser.id!,
          createdAt: '2026-08-08T14:00:00.000Z',
          type: 'thread',
          threadId: 31,
        ),
      );
      expect(subject.chat.channel(site, 13)?.unreadThreadOverview, isEmpty);

      // A channel-shaped event can still name a thread when the server could
      // not publish the reply to the thread stream. Core treats it as both
      // channel unread and unread-thread activity.
      tracker.deliverPluginMessage(
        '/chat/13/new-messages',
        newMessageEvent(
          channelId: 13,
          messageId: 62,
          authorId: 2,
          createdAt: '2026-08-08T15:00:00.000Z',
          threadId: 32,
        ),
      );
      expect(subject.chat.channel(site, 13)?.tracking.unreadCount, 1);
      expect(subject.chat.channel(site, 13)?.unreadThreadOverview, {
        32: DateTime.utc(2026, 8, 8, 15),
      });
    });

    test(
      'keeps thread activity quiet while its channel pane is active',
      () async {
        var now = DateTime.utc(2026, 8, 8, 12, 30);
        final subject = build(
          currentUser: currentUser,
          clock: () => now,
          channels: {
            site: ChatChannels(
              direct: [
                channel(
                  12,
                  title: 'Viewed',
                  kind: ChatChannelKind.directMessage,
                  threadingEnabled: true,
                  lastViewedAt: DateTime.utc(2026, 8, 8, 10),
                  unreadThreadOverview: {30: DateTime.utc(2026, 8, 8, 11)},
                  lastMessageId: 50,
                  lastMessageAt: DateTime.utc(2026, 8, 8, 10),
                ),
                channel(
                  13,
                  title: 'Other',
                  kind: ChatChannelKind.directMessage,
                  lastMessageId: 80,
                  lastMessageAt: DateTime.utc(2026, 8, 8, 16),
                ),
              ],
              newMessageBusLastIds: const {12: 70, 13: 71},
            ),
          },
        );
        final tracker = attachTracker(subject.chat);

        // The pane can mount before the channel snapshot arrives. Its token is
        // retained and the snapshot is marked viewed when it lands.
        final oldView = subject.chat.beginViewingChannel(site, 12);
        await subject.chat.loadChannels(site);
        expect(subject.chat.channel(site, 12)?.membership.lastViewedAt, now);
        expect(
          subject.chat.channel(site, 12)?.unreadThreadsCountSinceLastViewed,
          0,
        );
        expect(subject.chat.channel(site, 12)?.badge.isVisible, isFalse);

        // A replacement pane owns a new generation. Releasing the overlapping
        // old pane must not deactivate it.
        now = DateTime.utc(2026, 8, 8, 12, 45);
        final currentView = subject.chat.beginViewingChannel(site, 12);
        subject.chat.endViewingChannel(site, 12, oldView);

        now = DateTime.utc(2026, 8, 8, 13, 1);
        tracker.deliverPluginMessage(
          '/chat/12/new-messages',
          newMessageEvent(
            channelId: 12,
            messageId: 60,
            authorId: 2,
            createdAt: '2026-08-08T13:00:00.000Z',
            type: 'thread',
            threadId: 31,
          ),
        );

        final active = subject.chat.channel(site, 12)!;
        expect(active.unreadThreadOverview, {
          30: DateTime.utc(2026, 8, 8, 11),
          31: DateTime.utc(2026, 8, 8, 13),
        });
        expect(active.membership.lastViewedAt, now);
        expect(active.unreadThreadsCountSinceLastViewed, 0);
        expect(active.badge.isVisible, isFalse);
        expect(subject.chat.unstarredDirectChannels(site).map((c) => c.id), [
          13,
          12,
        ]);

        subject.chat.endViewingChannel(site, 12, currentView);
        now = DateTime.utc(2026, 8, 8, 15, 1);
        tracker.deliverPluginMessage(
          '/chat/12/new-messages',
          newMessageEvent(
            channelId: 12,
            messageId: 70,
            authorId: 2,
            createdAt: '2026-08-08T15:00:00.000Z',
            type: 'thread',
            threadId: 31,
          ),
        );

        final inactive = subject.chat.channel(site, 12)!;
        expect(
          inactive.membership.lastViewedAt,
          DateTime.utc(2026, 8, 8, 13, 1),
        );
        expect(inactive.unreadThreadsCountSinceLastViewed, 1);
        expect(inactive.badge.dot, isTrue);
        expect(inactive.badge.urgent, isFalse);
        expect(subject.chat.unstarredDirectChannels(site).map((c) => c.id), [
          12,
          13,
        ]);
      },
    );

    test('adds a newly followed DM before its first message event', () async {
      final subject = build(
        currentUser: currentUser,
        channels: {site: const ChatChannels(newChannelBusLastId: 80)},
      );
      // Store rows outlive sidebar membership across a refresh. Discovery is
      // about whether the id is listed, not whether an old record still exists.
      subject.store.put(
        site,
        channel(
          13,
          kind: ChatChannelKind.directMessage,
          lastMessageId: 20,
          lastMessageAt: DateTime.utc(2026, 8, 7, 10),
        ),
      );
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);

      expect(tracker.pluginChannelLastIds['/chat/new-channel'], 80);
      tracker.deliverPluginMessage(
        '/chat/new-channel',
        newDirectChannelEvent(
          channelId: 13,
          messageId: 60,
          newMessagesLastId: 81,
        ),
      );

      expect(subject.chat.directChannels(site).map((c) => c.id), [13]);
      expect(tracker.pluginChannelLastIds['/chat/13/new-messages'], 81);

      // The channel snapshot already contains this message, but its cursor is
      // from immediately before publication. Accept the matching event once
      // so its unread projection is not lost.
      tracker.deliverPluginMessage(
        '/chat/13/new-messages',
        newMessageEvent(
          channelId: 13,
          messageId: 60,
          authorId: 2,
          createdAt: '2026-08-08T13:00:00.000Z',
        ),
      );
      expect(subject.chat.channel(site, 13)?.tracking.unreadCount, 1);
    });

    test(
      'tracker replacement rebinds and safely replays live channels',
      () async {
        final subject = build(
          currentUser: currentUser,
          channels: {
            site: ChatChannels(
              direct: [
                channel(
                  12,
                  kind: ChatChannelKind.directMessage,
                  lastMessageId: 50,
                  lastMessageAt: DateTime.utc(2026, 8, 8, 12),
                ),
              ],
              presence: const ChatPresence(lastMessageId: 47),
              newMessageBusLastIds: const {12: 70},
              newChannelBusLastId: 80,
              userTrackingBusLastId: 81,
            ),
          },
        );
        final first = attachTracker(subject.chat);
        await subject.chat.loadChannels(site);
        first.deliverPluginMessage(
          '/chat/12/new-messages',
          newMessageEvent(
            channelId: 12,
            messageId: 60,
            authorId: 2,
            createdAt: '2026-08-08T13:00:00.000Z',
          ),
        );
        expect(subject.chat.channel(site, 12)?.tracking.unreadCount, 1);

        final replacement = attachTracker(subject.chat);

        expect(first.pluginChannelCallbacks['/presence/chat/online'], isEmpty);
        expect(first.pluginChannelCallbacks['/chat/12/new-messages'], isEmpty);
        expect(replacement.pluginChannelLastIds['/presence/chat/online'], 47);
        expect(replacement.pluginChannelLastIds['/chat/12/new-messages'], 70);
        expect(replacement.pluginChannelLastIds['/chat/new-channel'], 80);

        // A replacement starts from the HTTP cursor, so creation and message
        // events can replay. Neither may regress activity or double-count.
        replacement.deliverPluginMessage(
          '/chat/new-channel',
          newDirectChannelEvent(
            channelId: 12,
            messageId: 50,
            newMessagesLastId: 70,
            title: 'First',
            createdAt: '2026-08-08T12:00:00.000Z',
          ),
        );
        replacement.deliverPluginMessage(
          '/chat/12/new-messages',
          newMessageEvent(
            channelId: 12,
            messageId: 60,
            authorId: 2,
            createdAt: '2026-08-08T13:00:00.000Z',
          ),
        );
        expect(subject.chat.channel(site, 12)?.lastMessageId, 60);
        expect(subject.chat.channel(site, 12)?.tracking.unreadCount, 1);

        replacement.deliverPluginMessage('/presence/chat/online', {
          'entering_users': [
            {'id': 2, 'username': 'hawk'},
          ],
        });
        expect(subject.chat.isOnline(site, 2), isTrue);
      },
    );

    test('reconciles single and bulk user tracking snapshots', () async {
      final deltas = <int>[];
      final subject = build(
        currentUser: currentUser,
        onChatNotificationsDelta: (_, delta) => deltas.add(delta),
        channels: {
          site: ChatChannels(
            direct: [
              channel(
                12,
                kind: ChatChannelKind.directMessage,
                unread: 2,
                lastRead: 40,
              ),
              channel(
                13,
                kind: ChatChannelKind.directMessage,
                unread: 3,
                lastRead: 41,
              ),
            ],
            userTrackingBusLastId: 90,
          ),
        },
      );
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);

      expect(tracker.pluginChannelLastIds['/chat/user-tracking-state/7'], 90);
      expect(
        tracker.pluginChannelLastIds['/chat/bulk-user-tracking-state/7'],
        90,
      );
      tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
        'channel_id': 12,
        'last_read_message_id': 50,
        'unread_count': 0,
        'mention_count': 0,
        'watched_threads_unread_count': 0,
      });
      tracker.deliverPluginMessage('/chat/bulk-user-tracking-state/7', {
        '13': {
          'last_read_message_id': 51,
          'unread_count': 0,
          'mention_count': 0,
          'watched_threads_unread_count': 0,
        },
      });

      expect(subject.chat.channel(site, 12)?.membership.lastReadMessageId, 50);
      expect(subject.chat.channel(site, 12)?.tracking, ChatTracking.none);
      expect(subject.chat.channel(site, 13)?.membership.lastReadMessageId, 51);
      expect(subject.chat.channel(site, 13)?.tracking, ChatTracking.none);
      expect(deltas, [-2, -3]);
    });

    test(
      'reconciles notification totals on a forced channel refresh',
      () async {
        final deltas = <int>[];
        final channels = <String, ChatChannels>{
          site: ChatChannels(
            public: [channel(9, unread: 8, mentions: 2)],
            direct: [
              channel(12, kind: ChatChannelKind.directMessage, unread: 3),
            ],
          ),
        };
        final subject = build(
          channels: channels,
          onChatNotificationsDelta: (_, delta) => deltas.add(delta),
        );
        await subject.chat.loadChannels(site);

        channels[site] = ChatChannels(
          public: [channel(9, unread: 8, mentions: 1)],
          direct: [channel(12, kind: ChatChannelKind.directMessage)],
        );
        await subject.chat.loadChannels(site, force: true);

        // Public chat contributes mentions; direct messages contribute unread
        // messages, matching Chat::ChannelFetcher#unreads_total.
        expect(deltas, [-4]);
      },
    );

    test('asks a site once rather than once per caller', () async {
      final subject = build(
        channels: {
          site: ChatChannels(public: [channel(9)], direct: const []),
        },
      );

      await subject.chat.loadChannels(site);
      await subject.chat.loadChannels(site);

      expect(subject.api.chatChannelsRequested, [site]);
    });

    test('resumes global presence at the channel snapshot cursor', () async {
      final subject = build(
        channels: {
          site: ChatChannels(
            public: [channel(9)],
            presence: const ChatPresence(userIds: {2}, lastMessageId: 47),
          ),
        },
      );
      final tracker = FakeSiteTracker(
        siteUrl: site,
        onIncomingTopics: () {},
        onNotifications: (_) {},
        onReviewableCounts: (_) {},
      );
      subject.chat.attachTracker(site, tracker);

      await subject.chat.loadChannels(site);

      expect(tracker.pluginChannelLastIds['/presence/chat/online'], 47);
      expect(subject.chat.isOnline(site, 2), isTrue);
      expect(subject.chat.onlineUserIdsListenable(site).value, {2});

      tracker.deliverPluginMessage('/presence/chat/online', {
        'entering_users': [
          {'id': 3, 'username': 'kris'},
        ],
        'leaving_user_ids': [2],
      });

      expect(subject.chat.isOnline(site, 2), isFalse);
      expect(subject.chat.isOnline(site, 3), isTrue);
      expect(subject.chat.onlineUserIdsListenable(site).value, {3});
    });

    test('stops applying presence after the site is forgotten', () async {
      final subject = build(
        channels: {
          site: const ChatChannels(
            presence: ChatPresence(userIds: {2}, lastMessageId: 47),
          ),
        },
      );
      final tracker = FakeSiteTracker(
        siteUrl: site,
        onIncomingTopics: () {},
        onNotifications: (_) {},
        onReviewableCounts: (_) {},
      );
      subject.chat.attachTracker(site, tracker);
      await subject.chat.loadChannels(site);
      final online = subject.chat.onlineUserIdsListenable(site);

      subject.chat.forget(site);
      tracker.deliverPluginMessage('/presence/chat/online', {
        'entering_users': [
          {'id': 3},
        ],
      });

      expect(online.value, isEmpty);
      expect(tracker.pluginChannelCallbacks['/presence/chat/online'], isEmpty);
    });

    test(
      'collapses two callers arriving before the first answer into one ask',
      () async {
        final gate = Completer<void>();
        final subject = build(
          channels: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          channelGate: gate,
        );

        final first = subject.chat.loadChannels(site);
        final second = subject.chat.loadChannels(site);
        gate.complete();
        await Future.wait([first, second]);

        expect(subject.api.chatChannelsRequested, [site]);
      },
    );

    test(
      'a forgotten credential-gated load never reaches the channel API',
      () async {
        final api = FakeDiscourseApi();
        final credentials = _ControllableCredentials()..keys[site] = 'key';
        final chat = ChatController(
          api: api,
          credentials: credentials,
          store: Store(),
        );
        addTearDown(chat.dispose);
        final credentialsStarted = credentials.blockApiKey();

        final loading = chat.loadChannels(site);
        await credentialsStarted;
        chat.forget(site);
        credentials.releaseApiKey();
        await loading;

        expect(api.chatChannelsRequested, isEmpty);
        expect(credentials.clientIdCalls, 0);
      },
    );

    test(
      'draws nothing for a site that will not answer, and says why',
      () async {
        final subject = build();

        await subject.chat.loadChannels(site);

        expect(subject.chat.publicChannels(site), isEmpty);
        expect(subject.chat.channelsError(site), isNotNull);
      },
    );

    test('a site that will not answer is given up on, not hammered', () async {
      final subject = build();

      for (var i = 0; i < 10; i++) {
        await subject.chat.loadChannels(site);
      }

      expect(
        subject.api.chatChannelsRequested.length,
        ChatController.maxChannelAttempts,
      );
    });

    test('keeps each site’s channels apart', () async {
      final subject = build(
        channels: {
          site: ChatChannels(public: [channel(9)], direct: const []),
        },
      );

      await subject.chat.loadChannels(site);
      await subject.chat.loadChannels(other);

      expect(subject.chat.publicChannels(site), hasLength(1));
      expect(subject.chat.publicChannels(other), isEmpty);
    });

    test('builds the same aggregate header indicators as core', () async {
      final subject = build(
        channels: {
          site: ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Bugs',
                kind: ChatChannelKind.category,
                tracking: const ChatTracking(
                  unreadCount: 7,
                  mentionCount: 2,
                  watchedThreadsUnreadCount: 1,
                ),
              ),
            ],
            direct: [
              ChatChannel(
                id: 12,
                title: 'hawk',
                kind: ChatChannelKind.directMessage,
                tracking: const ChatTracking(
                  unreadCount: 100,
                  watchedThreadsUnreadCount: 2,
                ),
              ),
            ],
          ),
        },
      );
      await subject.chat.loadChannels(site);

      final all = subject.chat.headerIndicator(
        site,
        ChatHeaderIndicatorPreference.allNew,
      );
      expect(all.urgentCount, 105);
      expect(all.label, '99+');
      expect(
        subject.chat
            .headerIndicator(
              site,
              ChatHeaderIndicatorPreference.directMessagesAndMentions,
            )
            .urgentCount,
        105,
      );
      expect(
        subject.chat
            .headerIndicator(site, ChatHeaderIndicatorPreference.onlyMentions)
            .urgentCount,
        2,
      );
      expect(
        subject.chat
            .headerIndicator(site, ChatHeaderIndicatorPreference.never)
            .isVisible,
        isFalse,
      );
    });

    test('uses a dot for ordinary public-channel unread activity', () async {
      final subject = build(
        channels: {
          site: ChatChannels(
            public: [channel(9, unread: 42)],
            direct: const [],
          ),
        },
      );
      await subject.chat.loadChannels(site);

      expect(
        subject.chat
            .headerIndicator(site, ChatHeaderIndicatorPreference.allNew)
            .unread,
        isTrue,
      );
      expect(
        subject.chat
            .headerIndicator(
              site,
              ChatHeaderIndicatorPreference.directMessagesAndMentions,
            )
            .isVisible,
        isFalse,
      );
    });

    test('uses a dot for an ordinary unread thread', () async {
      final subject = build(
        channels: {
          site: ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Bugs',
                kind: ChatChannelKind.category,
                unreadThreadOverview: {31: DateTime.utc(2026, 8, 8, 10)},
                threadingEnabled: true,
              ),
            ],
            direct: const [],
          ),
        },
      );
      await subject.chat.loadChannels(site);

      expect(
        subject.chat
            .headerIndicator(site, ChatHeaderIndicatorPreference.allNew)
            .unread,
        isTrue,
      );
    });

    test('the shortcut prefers the server’s last channel', () async {
      final subject = build(
        channels: {
          site: ChatChannels(
            public: [channel(9)],
            direct: [
              const ChatChannel(
                id: 12,
                title: 'hawk',
                kind: ChatChannelKind.directMessage,
              ),
            ],
          ),
        },
      );
      await subject.chat.loadChannels(site);

      expect(subject.chat.shortcutChannel(site, lastChannelId: 9)?.id, 9);
      expect(subject.chat.shortcutChannel(site, lastChannelId: 404)?.id, 12);
    });

    test('the shortcut remembers a channel opened in this client', () async {
      final subject = build(
        channels: {
          site: ChatChannels(
            public: [channel(9)],
            direct: [
              const ChatChannel(
                id: 12,
                title: 'hawk',
                kind: ChatChannelKind.directMessage,
              ),
            ],
          ),
        },
        messages: {key(12): page(const [])},
      );
      await subject.chat.loadChannels(site);
      await subject.chat.openChannel(site, 12);

      expect(subject.chat.shortcutChannel(site, lastChannelId: 9)?.id, 12);
    });
  });

  group('opening a channel', () {
    test(
      'reuses a recently attempted window unless refresh is forced',
      () async {
        var now = DateTime.utc(2026, 8, 11, 10);
        final subject = build(
          messages: {
            key(9): page([message(1)]),
          },
          clock: () => now,
        );

        await subject.chat.openChannel(site, 9);
        now = now.add(const Duration(seconds: 29));
        await subject.chat.openChannel(site, 9);

        expect(subject.api.chatMessagesRequested, hasLength(1));
        expect(subject.chat.stream(site, 9).fetches, 1);

        await subject.chat.openChannel(site, 9, force: true);

        expect(subject.api.chatMessagesRequested, hasLength(2));
        expect(subject.chat.stream(site, 9).fetches, 2);
      },
    );

    test('retries an attempted window when its cooldown expires', () async {
      var now = DateTime.utc(2026, 8, 11, 10);
      final subject = build(clock: () => now);

      // Failures are attempts too. Rapid remounts must not turn an unavailable
      // or rate-limited endpoint into a retry loop.
      await subject.chat.openChannel(site, 9);
      await subject.chat.openChannel(site, 9);
      expect(subject.api.chatMessagesRequested, hasLength(1));

      now = now.add(const Duration(seconds: 30));
      await subject.chat.openChannel(site, 9);

      expect(subject.api.chatMessagesRequested, hasLength(2));
    });

    test(
      'a disposed credential-gated window never reaches the message API',
      () async {
        final api = FakeDiscourseApi();
        final credentials = _ControllableCredentials()..keys[site] = 'key';
        final chat = ChatController(
          api: api,
          credentials: credentials,
          store: Store(),
        );
        final clientIdStarted = credentials.blockClientId();

        final opening = chat.openChannel(site, 9);
        await clientIdStarted;
        chat.dispose();
        credentials.releaseClientId();
        await opening;

        expect(api.chatMessagesRequested, isEmpty);
      },
    );

    test('notifies only the stream that changed', () async {
      final subject = build(
        messages: {
          key(4): page([message(40)]),
          key(9): page([message(90)]),
        },
      );
      final active = subject.chat.streamListenable(site, 9);
      var streamNotifications = 0;
      var controllerNotifications = 0;
      active.addListener(() => streamNotifications++);
      subject.chat.addListener(() => controllerNotifications++);

      await subject.chat.openChannel(site, 4);
      expect(streamNotifications, 0);
      expect(controllerNotifications, 0);

      await subject.chat.openChannel(site, 9);
      expect(streamNotifications, greaterThan(0));
      expect(active.value.messageIds, [90]);
      expect(controllerNotifications, 0);
    });

    test(
      'asks from where the reader left off and holds it oldest first',
      () async {
        // The site resolves the anchor from the membership, so this asks for it
        // by name rather than naming a message. A reader who has never opened
        // the channel is answered with the newest page by the same request.
        final subject = build(
          messages: {
            key(9): page([message(1), message(2, minute: 1)]),
          },
        );

        await subject.chat.openChannel(site, 9);

        expect(subject.api.chatMessagesRequested.single.fromLastRead, isTrue);
        expect(subject.chat.stream(site, 9).messageIds, [1, 2]);
        expect(subject.chat.stream(site, 9).fetchedOnce, isTrue);
      },
    );

    test(
      'reads a channel nobody has written in as empty rather than as unread',
      () async {
        final subject = build(messages: {key(9): page([])});

        await subject.chat.openChannel(site, 9);

        expect(subject.chat.stream(site, 9).isEmpty, isTrue);
        expect(subject.chat.stream(site, 9).error, isNull);
      },
    );

    test('says nothing is loaded until the site has answered', () async {
      final subject = build(messages: {key(9): page([])});

      expect(subject.chat.stream(site, 9).fetchedOnce, isFalse);
      expect(subject.chat.stream(site, 9).isEmpty, isFalse);
    });

    test('shows loading only where there is nothing behind it', () async {
      final gate = Completer<void>();
      final subject = build(
        messages: {
          key(9): page([message(1)]),
        },
        messageGate: gate,
      );

      final first = subject.chat.openChannel(site, 9);
      expect(subject.chat.stream(site, 9).loading, isTrue);
      gate.complete();
      await first;

      // A forced refresh works underneath what is already there rather than
      // replacing a conversation with a loading placeholder.
      final second = subject.chat.openChannel(site, 9, force: true);
      expect(subject.chat.stream(site, 9).loading, isFalse);
      await second;
    });

    test(
      'replaces rather than merges, because a hole would break paging',
      () async {
        // The reader scrolled back, then re-opened. Merging the newest page into
        // history would leave a gap in the middle that nothing could ever fill,
        // since loadOlder only ever pages before the oldest message held.
        final subject = build(
          messages: {
            key(9): page([message(9, minute: 9)], canLoadMorePast: true),
            key(9, before: 5): page([message(1), message(2, minute: 1)]),
          },
        );

        await subject.chat.openChannel(site, 9);
        subject.store.putAll(site, [message(5, minute: 5)]);
        await subject.chat.openChannel(site, 9, force: true);

        expect(subject.chat.stream(site, 9).messageIds, [9]);
      },
    );

    test('keeps what is on screen when a refresh fails', () async {
      // The fake answers from a map it reads at call time, so taking the page
      // back out between the two opens is how a site that answered once and
      // then would not is written down.
      final pages = {
        key(9): page([message(1)]),
      };
      final subject = build(messages: pages);
      await subject.chat.openChannel(site, 9);

      pages.remove(key(9));
      await subject.chat.openChannel(site, 9, force: true);

      // A conversation that was true a moment ago beats an error where it was;
      // an explicit reconciliation can still ask again during the cooldown.
      expect(subject.chat.stream(site, 9).messageIds, [1]);
      expect(subject.chat.stream(site, 9).error, isNull);
      expect(subject.api.chatMessagesRequested, hasLength(2));
    });

    test(
      'says so when the first ask fails and there is nothing to fall back on',
      () async {
        final unreachable = <String>[];
        final subject = build(onSiteUnreachable: unreachable.add);

        await subject.chat.openChannel(site, 9);

        expect(subject.chat.stream(site, 9).error, isNotNull);
        expect(subject.chat.stream(site, 9).fetchedOnce, isTrue);
        expect(unreachable, [site]);
      },
    );
  });

  group('sending a message', () {
    test('stages the local row before credentials can answer', () async {
      final credentialsGate = Completer<void>();
      final credentials = _GatedCredentials(credentialsGate);
      final now = DateTime.utc(2026, 5, 5, 10, 1);
      final subject = build(
        credentialReader: credentials,
        currentUser: currentUser,
        clock: () => now,
      );
      addTearDown(subject.chat.dispose);

      final sending = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('  hello chat  '),
      )!;

      final window = subject.chat.stream(site, 9);
      expect(window.messageIds, isEmpty);
      expect(window.localMessageIds, [-1]);
      final local = subject.store.read<ChatMessage>(site, -1)!;
      expect(local.optimisticRaw, '  hello chat  ');
      expect(local.stagedId, 'native-${now.microsecondsSinceEpoch}-0');
      expect(local.delivery, ChatMessageDelivery.sending);
      expect(local.preview, isA<ProjectedPreview>());
      expect(local.author.username, currentUser.username);
      expect(subject.api.chatMessagesSent, isEmpty);

      await credentials.started.future;
      expect(subject.chat.stream(site, 9).localMessageIds, [-1]);
      expect(subject.api.chatMessagesSent, isEmpty);

      credentialsGate.complete();
      expect(await sending.settled, ChatSendResult.sent);
    });

    test('stages a FIFO batch before credentials resolve', () async {
      final credentialsGate = Completer<void>();
      final credentials = _GatedCredentials(credentialsGate);
      final subject = build(
        credentialReader: credentials,
        currentUser: currentUser,
      );
      addTearDown(subject.chat.dispose);

      final first = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('first'),
      )!;
      final second = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('second'),
      )!;
      await credentials.started.future;

      expect(subject.chat.stream(site, 9).localMessageIds, [-1, -2]);
      expect(subject.api.chatMessagesSent, isEmpty);

      credentialsGate.complete();
      expect(await first.settled, ChatSendResult.sent);
      expect(await second.settled, ChatSendResult.sent);
      expect(subject.api.chatMessagesSent.map((call) => call.message), [
        'first',
        'second',
      ]);
    });

    test(
      'preserves source, correlates, serializes, and performs no message GET',
      () async {
        final gate = Completer<void>();
        final now = DateTime.utc(2026, 5, 5, 10, 2);
        final subject = build(
          sendGate: gate,
          currentUser: currentUser,
          clock: () => now,
        );
        addTearDown(subject.chat.dispose);

        final first = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('  hello chat  '),
        )!;
        final second = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('hello again'),
        )!;
        await Future<void>.delayed(Duration.zero);

        expect(subject.api.chatMessagesSent, [
          (
            siteUrl: site,
            channelId: 9,
            message: '  hello chat  ',
            threadId: null,
            stagedId: 'native-${now.microsecondsSinceEpoch}-0',
            clientCreatedAt: now,
          ),
        ]);
        expect(subject.api.chatMessagesRequested, isEmpty);
        expect(subject.chat.stream(site, 9).messageIds, isEmpty);
        expect(subject.chat.stream(site, 9).localMessageIds, [-1, -2]);

        gate.complete();
        expect(await first.settled, ChatSendResult.sent);
        expect(await second.settled, ChatSendResult.sent);
        expect(subject.api.chatMessagesSent.map((call) => call.message), [
          '  hello chat  ',
          'hello again',
        ]);
        expect(subject.api.chatMessagesRequested, isEmpty);
        expect(
          subject.store.read<ChatMessage>(site, -1)?.delivery,
          ChatMessageDelivery.sent,
        );
        expect(first.localId, -1);
        expect(second.localId, -2);
        expect(first.stagedId, isNot(second.stagedId));
      },
    );

    test('different channels send concurrently', () async {
      final gate = Completer<void>();
      final subject = build(sendGate: gate, currentUser: currentUser);
      addTearDown(subject.chat.dispose);

      final first = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('nine'),
      )!;
      final second = subject.chat.sendMessage(
        site,
        10,
        OutgoingChatMessage.text('ten'),
      )!;
      await Future<void>.delayed(Duration.zero);

      expect(
        subject.api.chatMessagesSent.map((call) => call.channelId).toSet(),
        {9, 10},
      );

      gate.complete();
      expect(await first.settled, ChatSendResult.sent);
      expect(await second.settled, ChatSendResult.sent);
    });

    test('a failed request does not stop its channel queue', () async {
      const refusal = WriteException(WriteFailure.validation);
      final subject = build(sendFailure: refusal, currentUser: currentUser);
      addTearDown(subject.chat.dispose);

      final first = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('first'),
      )!;
      final second = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('second'),
      )!;

      expect(await first.settled, ChatSendResult.failed);
      expect(await second.settled, ChatSendResult.failed);
      expect(subject.api.chatMessagesSent.map((call) => call.message), [
        'first',
        'second',
      ]);
    });

    test(
      'forget cancels active and queued messages without throwing',
      () async {
        final credentialsGate = Completer<void>();
        final credentials = _GatedCredentials(credentialsGate);
        final subject = build(
          credentialReader: credentials,
          currentUser: currentUser,
        );
        addTearDown(subject.chat.dispose);

        final first = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('first'),
        )!;
        final second = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('second'),
        )!;
        await credentials.started.future;

        subject.chat.forget(site);

        expect(await first.settled, ChatSendResult.cancelled);
        expect(await second.settled, ChatSendResult.cancelled);
        credentialsGate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(subject.api.chatMessagesSent, isEmpty);
      },
    );

    test('dispose cancels accepted messages', () async {
      final credentialsGate = Completer<void>();
      final credentials = _GatedCredentials(credentialsGate);
      final subject = build(
        credentialReader: credentials,
        currentUser: currentUser,
      );

      final handle = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('hello'),
      )!;
      await credentials.started.future;
      subject.chat.dispose();

      expect(await handle.settled, ChatSendResult.cancelled);
      credentialsGate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(subject.api.chatMessagesSent, isEmpty);
    });

    test('rejects blank input and messages after disposal synchronously', () {
      final subject = build(currentUser: currentUser);

      expect(
        subject.chat.sendMessage(site, 9, OutgoingChatMessage.text('   ')),
        isNull,
      );
      subject.chat.dispose();
      expect(
        subject.chat.sendMessage(site, 9, OutgoingChatMessage.text('hello')),
        isNull,
      );
    });

    test(
      'keeps an optimistic row outside an anchored canonical window',
      () async {
        final gate = Completer<void>();
        final subject = build(
          messages: {
            key(9): page([message(5, minute: 5)], canLoadMoreFuture: true),
          },
          sendGate: gate,
          currentUser: currentUser,
        );
        addTearDown(subject.chat.dispose);
        await subject.chat.openChannel(site, 9);

        final sending = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('from the past'),
        )!;

        final window = subject.chat.stream(site, 9);
        expect(window.messageIds, [5]);
        expect(window.localMessageIds, [-1]);
        expect(window.canLoadMoreFuture, isTrue);
        expect(subject.chat.messages(site, 9).map((message) => message.id), [
          5,
          -1,
        ]);
        expect(subject.api.chatMessagesRequested, hasLength(1));

        gate.complete();
        await sending.settled;
        expect(subject.api.chatMessagesRequested, hasLength(1));
      },
    );

    test('a matching sent event canonicalizes the same local row', () async {
      final subject = build(sentMessageId: 42, currentUser: currentUser);
      addTearDown(subject.chat.dispose);
      final tracker = attachTracker(subject.chat);

      final handle = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('hello chat'),
      )!;
      await handle.settled;
      final localId = subject.chat.stream(site, 9).localMessageIds.single;
      final stagedId = subject.store
          .read<ChatMessage>(site, localId)!
          .stagedId!;

      tracker.deliverPluginMessage('/chat/9', sentEvent(stagedId: stagedId));

      final window = subject.chat.stream(site, 9);
      final local = subject.store.read<ChatMessage>(site, localId)!;
      expect(localId, isNegative);
      expect(window.messageIds, isEmpty);
      expect(window.localMessageIds, [localId]);
      expect(local.id, localId);
      expect(local.serverId, 42);
      expect(local.cooked, '<p>hello chat</p>');
      expect(local.delivery, ChatMessageDelivery.sent);
      expect(subject.chat.messages(site, 9).map((message) => message.id), [
        localId,
      ]);
      expect(subject.store.read<ChatMessage>(site, 42), isNotNull);
      expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
    });

    test('tracker replacement rebinds an in-flight send echo', () async {
      final gate = Completer<void>();
      final subject = build(
        sendGate: gate,
        sentMessageId: 42,
        currentUser: currentUser,
      );
      addTearDown(subject.chat.dispose);
      final first = attachTracker(subject.chat);

      final sending = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('hello chat'),
      )!;
      final localId = subject.chat.stream(site, 9).localMessageIds.single;
      final stagedId = subject.store
          .read<ChatMessage>(site, localId)!
          .stagedId!;
      expect(first.pluginChannelCallbacks['/chat/9'], isNotEmpty);

      final replacement = attachTracker(subject.chat);

      expect(first.pluginChannelCallbacks['/chat/9'], isEmpty);
      expect(replacement.pluginChannelCallbacks['/chat/9'], isNotEmpty);
      replacement.deliverPluginMessage(
        '/chat/9',
        sentEvent(stagedId: stagedId),
      );
      expect(subject.store.read<ChatMessage>(site, localId)?.serverId, 42);

      gate.complete();
      expect(await sending.settled, ChatSendResult.sent);
    });

    test(
      'a sent event that beats the POST response remains one local row',
      () async {
        final gate = Completer<void>();
        final subject = build(
          sendGate: gate,
          sentMessageId: 42,
          currentUser: currentUser,
        );
        addTearDown(subject.chat.dispose);
        final tracker = attachTracker(subject.chat);

        final sending = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('hello chat'),
        )!;
        await Future<void>.delayed(Duration.zero);
        final localId = subject.chat.stream(site, 9).localMessageIds.single;
        final stagedId = subject.store
            .read<ChatMessage>(site, localId)!
            .stagedId!;

        tracker.deliverPluginMessage('/chat/9', sentEvent(stagedId: stagedId));
        expect(subject.chat.messages(site, 9), hasLength(1));
        expect(
          subject.store.read<ChatMessage>(site, localId)?.cooked,
          '<p>hello chat</p>',
        );

        gate.complete();
        expect(await sending.settled, ChatSendResult.sent);

        final window = subject.chat.stream(site, 9);
        final local = subject.store.read<ChatMessage>(site, localId)!;
        expect(window.messageIds, isEmpty);
        expect(window.localMessageIds, [localId]);
        expect(subject.chat.messages(site, 9), hasLength(1));
        expect(local.serverId, 42);
        expect(local.cooked, '<p>hello chat</p>');
        expect(local.delivery, ChatMessageDelivery.sent);
        expect(subject.api.chatMessagesRequested, isEmpty);
        expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      },
    );

    test(
      'a definitive refusal marks the local row failed without retry',
      () async {
        const refusal = WriteException(
          WriteFailure.validation,
          errors: ['That message is not allowed.'],
        );
        final subject = build(sendFailure: refusal, currentUser: currentUser);
        addTearDown(subject.chat.dispose);
        final tracker = attachTracker(subject.chat);

        final handle = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('hello'),
        )!;
        expect(await handle.settled, ChatSendResult.failed);

        expect(subject.api.chatMessagesSent, hasLength(1));
        expect(subject.api.chatMessagesRequested, isEmpty);
        final window = subject.chat.stream(site, 9);
        final local = subject.store.read<ChatMessage>(
          site,
          window.localMessageIds.single,
        )!;
        expect(window.messageIds, isEmpty);
        expect(local.delivery, ChatMessageDelivery.failed);
        expect(local.sendError, refusal.message);
        expect(local.deliveryUncertain, isFalse);
        expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      },
    );

    test(
      'an unreachable send leaves only that local row delivery uncertain',
      () async {
        const outage = WriteException(WriteFailure.unreachable);
        final subject = build(sendFailure: outage, currentUser: currentUser);
        addTearDown(subject.chat.dispose);
        final tracker = attachTracker(subject.chat);

        final handle = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('hello'),
        )!;
        expect(await handle.settled, ChatSendResult.failed);

        final window = subject.chat.stream(site, 9);
        final local = subject.store.read<ChatMessage>(
          site,
          window.localMessageIds.single,
        )!;
        expect(window.messageIds, isEmpty);
        expect(window.localMessageIds, [-1]);
        expect(local.delivery, ChatMessageDelivery.failed);
        expect(local.sendError, outage.message);
        expect(local.deliveryUncertain, isTrue);
        expect(local.canonicalReceived, isFalse);
        expect(tracker.pluginChannelCallbacks['/chat/9'], hasLength(1));

        tracker.deliverPluginMessage(
          '/chat/9',
          sentEvent(stagedId: local.stagedId!, cooked: ''),
        );

        final reconciled = subject.store.read<ChatMessage>(site, local.id)!;
        expect(reconciled.delivery, ChatMessageDelivery.sent);
        expect(reconciled.deliveryUncertain, isFalse);
        expect(reconciled.cooked, isEmpty);
        expect(reconciled.canonicalReceived, isTrue);
        expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      },
    );

    test('read receipts ignore a local negative message id', () async {
      final subject = build(currentUser: currentUser);
      addTearDown(subject.chat.dispose);
      subject.store.put(site, channel(9, lastRead: 3));
      final handle = subject.chat.sendMessage(
        site,
        9,
        OutgoingChatMessage.text('hello'),
      )!;
      await handle.settled;
      final localId = subject.chat.stream(site, 9).localMessageIds.single;

      await subject.chat.markRead(site, 9, localId);

      expect(localId, isNegative);
      expect(subject.api.chatReadsMarked, isEmpty);
      expect(
        subject.store.read<ChatChannel>(site, 9)?.membership.lastReadMessageId,
        3,
      );
    });

    test(
      'a later canonical page retires its local overlay without a duplicate',
      () async {
        final subject = build(
          messages: {
            key(9): page([message(42, minute: 2)]),
          },
          sentMessageId: 42,
          currentUser: currentUser,
        );
        addTearDown(subject.chat.dispose);
        final handle = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('hello'),
        )!;
        await handle.settled;
        final localId = subject.chat.stream(site, 9).localMessageIds.single;
        expect(subject.store.read<ChatMessage>(site, localId)?.serverId, 42);

        await subject.chat.openChannel(site, 9);

        final window = subject.chat.stream(site, 9);
        expect(window.messageIds, [42]);
        expect(window.localMessageIds, isEmpty);
        expect(subject.store.read<ChatMessage>(site, localId), isNull);
        expect(subject.chat.messages(site, 9).map((message) => message.id), [
          42,
        ]);
        expect(subject.api.chatMessagesRequested, hasLength(1));
      },
    );

    test(
      'a re-entry page that beats the send response retires the local row',
      () async {
        final sendGate = Completer<void>();
        final createdAt = DateTime.utc(2026, 5, 5, 10, 1, 0, 123, 456);
        final canonical = ChatMessage(
          id: 42,
          channelId: 9,
          cooked: '<p>hello</p>',
          author: const ChatMessageAuthor(id: 7, username: 'reader'),
          // Discourse serializes dates to milliseconds even though the client
          // timestamp sent with the message can contain microseconds.
          createdAt: DateTime.utc(2026, 5, 5, 10, 1, 0, 123),
        );
        final pages = <String, ChatMessagePage>{key(9): page([])};
        final subject = build(
          messages: pages,
          sendGate: sendGate,
          sentMessageId: 42,
          currentUser: currentUser,
          clock: () => createdAt,
        );
        addTearDown(subject.chat.dispose);
        await subject.chat.openChannel(site, 9);

        final sending = subject.chat.sendMessage(
          site,
          9,
          OutgoingChatMessage.text('hello'),
        )!;
        await Future<void>.delayed(Duration.zero);
        expect(subject.chat.stream(site, 9).localMessageIds, [-1]);

        // Returning to the channel can finish its GET after the server has
        // committed the POST but before this client's POST response arrives.
        pages[key(9)] = page([canonical]);
        await subject.chat.openChannel(site, 9, force: true);

        final window = subject.chat.stream(site, 9);
        expect(window.messageIds, [42]);
        expect(window.localMessageIds, isEmpty);
        expect(subject.store.read<ChatMessage>(site, -1), isNull);
        expect(subject.chat.messages(site, 9), [canonical]);

        sendGate.complete();
        expect(await sending.settled, ChatSendResult.sent);
        expect(subject.chat.messages(site, 9), [canonical]);
      },
    );
  });

  group('reacting to a message', () {
    test('loads the people behind one emoji through chat', () async {
      final subject = build(
        chatReactors: {
          ChatMessageReactors.key(9, 1, 'clap'): const ChatMessageReactors(
            channelId: 9,
            messageId: 1,
            filter: 'clap',
            total: 2,
            reactors: [
              PostReactor(id: 3, username: 'sam', reaction: 'clap'),
              PostReactor(id: 4, username: 'ada', reaction: 'clap'),
            ],
          ),
        },
      );

      await subject.chat.loadMessageReactors(
        siteUrl: site,
        channelId: 9,
        messageId: 1,
        filter: 'clap',
      );

      expect(subject.api.chatReactorsRequested, [
        (channelId: 9, messageId: 1, filter: 'clap'),
      ]);
      expect(
        subject.chat
            .messageReactors(site, 9, 1, filter: 'clap')
            ?.reactors
            .map((reactor) => reactor.username),
        ['sam', 'ada'],
      );
      expect(
        subject.chat.messageReactorsError(site, 9, 1, filter: 'clap'),
        isNull,
      );
    });

    test(
      'a reactor read failure is retained for the shared retry UI',
      () async {
        final subject = build();

        await subject.chat.loadMessageReactors(
          siteUrl: site,
          channelId: 9,
          messageId: 1,
          filter: 'clap',
        );

        expect(
          subject.chat.messageReactorsError(site, 9, 1, filter: 'clap'),
          'Could not find out who reacted.',
        );
      },
    );

    test(
      'forgetting a credential-gated reactor read sends no API call',
      () async {
        final credentialGate = Completer<void>();
        final credentials = _GatedCredentials(credentialGate)
          ..keys[site] = 'key';
        final subject = build(credentialReader: credentials);

        final loading = subject.chat.loadMessageReactors(
          siteUrl: site,
          channelId: 9,
          messageId: 1,
          filter: 'clap',
        );
        await credentials.started.future;
        subject.chat.forget(site);
        credentialGate.complete();
        await loading;

        expect(subject.api.chatReactorsRequested, isEmpty);
        expect(
          subject.chat.messageReactorsError(site, 9, 1, filter: 'clap'),
          isNull,
        );
      },
    );

    test(
      'optimistically adds an independent reaction and keeps it on success',
      () async {
        final subject = build(
          messages: {
            key(9): page([
              message(
                1,
                reactions: const [
                  ChatReaction(emoji: 'heart', count: 2, reacted: true),
                  ChatReaction(emoji: 'clap', count: 1),
                ],
              ),
            ]),
          },
        );
        await subject.chat.openChannel(site, 9);

        final writing = subject.chat.toggleMessageReaction(site, 1, 'clap');
        final optimistic = subject.store.read<ChatMessage>(site, 1)!;

        expect(optimistic.reactions, const [
          ChatReaction(emoji: 'heart', count: 2, reacted: true),
          ChatReaction(emoji: 'clap', count: 2, reacted: true),
        ]);
        expect(await writing, isNull);
        expect(
          subject.api.chatReactionsSet.single.action,
          ChatReactionAction.add,
        );
        expect(subject.store.read<ChatMessage>(site, 1), optimistic);
      },
    );

    test(
      'does not count the current user live echo after an optimistic add',
      () async {
        final gate = Completer<void>();
        final subject = build(
          currentUser: currentUser,
          messages: {
            key(9): page([
              message(
                1,
                reactions: const [ChatReaction(emoji: 'clap', count: 1)],
              ),
            ]),
          },
          reactionGate: gate,
        );
        final tracker = attachTracker(subject.chat);
        await subject.chat.openChannel(site, 9);
        final view = subject.chat.beginViewingChannel(site, 9);
        addTearDown(() => subject.chat.endViewingChannel(site, 9, view));

        final writing = subject.chat.toggleMessageReaction(site, 1, 'clap');
        await Future<void>.delayed(Duration.zero);
        tracker.deliverPluginMessage('/chat/9', {
          'type': 'reaction',
          'chat_message_id': 1,
          'emoji': 'clap',
          'action': 'add',
          'user': {'id': currentUser.id, 'username': currentUser.username},
        });
        gate.complete();
        await writing;

        expect(
          subject.store.read<ChatMessage>(site, 1)!.reactions.single,
          const ChatReaction(emoji: 'clap', count: 2, reacted: true),
        );
      },
    );

    test(
      'removes this reader and drops the row when its count reaches zero',
      () async {
        final subject = build(
          messages: {
            key(9): page([
              message(
                1,
                reactions: const [
                  ChatReaction(emoji: 'heart', count: 1, reacted: true),
                ],
              ),
            ]),
          },
        );
        await subject.chat.openChannel(site, 9);

        expect(
          await subject.chat.toggleMessageReaction(site, 1, 'heart'),
          isNull,
        );

        expect(subject.store.read<ChatMessage>(site, 1)!.reactions, isEmpty);
        expect(
          subject.api.chatReactionsSet.single.action,
          ChatReactionAction.remove,
        );
      },
    );

    test('rolls a refused write back and returns the site message', () async {
      final subject = build(
        messages: {
          key(9): page([
            message(
              1,
              reactions: const [ChatReaction(emoji: 'clap', count: 2)],
            ),
          ]),
        },
        reactionFailure: const WriteException(
          WriteFailure.validation,
          errors: ['That emoji is unavailable.'],
        ),
      );
      await subject.chat.openChannel(site, 9);

      final error = await subject.chat.toggleMessageReaction(site, 1, 'clap');

      expect(error, 'That emoji is unavailable.');
      expect(
        subject.store.read<ChatMessage>(site, 1)!.reactions.single,
        const ChatReaction(emoji: 'clap', count: 2),
      );
    });

    test(
      'suppresses a conflicting second tap while the first is unresolved',
      () async {
        final gate = Completer<void>();
        final subject = build(
          messages: {
            key(9): page([
              message(
                1,
                reactions: const [ChatReaction(emoji: 'clap', count: 2)],
              ),
            ]),
          },
          reactionGate: gate,
        );
        await subject.chat.openChannel(site, 9);

        final first = subject.chat.toggleMessageReaction(site, 1, 'clap');
        await Future<void>.delayed(Duration.zero);
        final second = subject.chat.toggleMessageReaction(site, 1, 'clap');
        gate.complete();

        await Future.wait([first, second]);
        expect(subject.api.chatReactionsSet, hasLength(1));
        expect(
          subject.store.read<ChatMessage>(site, 1)!.reactions.single,
          const ChatReaction(emoji: 'clap', count: 3, reacted: true),
        );
      },
    );

    test(
      'successful write reapplies the reader state over a concurrent refresh',
      () async {
        final gate = Completer<void>();
        final original = message(
          1,
          reactions: const [ChatReaction(emoji: 'clap', count: 2)],
        );
        final subject = build(
          messages: {
            key(9): page([original]),
          },
          reactionGate: gate,
        );
        await subject.chat.openChannel(site, 9);

        final writing = subject.chat.toggleMessageReaction(site, 1, 'clap');
        subject.store.put(site, original);
        gate.complete();
        await writing;

        expect(
          subject.store.read<ChatMessage>(site, 1)!.reactions.single,
          const ChatReaction(emoji: 'clap', count: 3, reacted: true),
        );
      },
    );

    test(
      'a forgotten credential-gated reaction never reaches the API',
      () async {
        final credentialGate = Completer<void>();
        final credentials = _GatedCredentials(credentialGate)
          ..keys[site] = 'key';
        final subject = build(credentialReader: credentials);
        subject.store.put(
          site,
          message(1, reactions: const [ChatReaction(emoji: 'clap', count: 2)]),
        );

        final writing = subject.chat.toggleMessageReaction(site, 1, 'clap');
        await credentials.started.future;
        subject.chat.forget(site);
        credentialGate.complete();
        await writing;

        expect(subject.api.chatReactionsSet, isEmpty);
      },
    );
  });

  group('paging towards the present', () {
    /// A window anchored behind the present, which is the only shape that has
    /// anything in front of it to fetch.
    ({ChatController chat, FakeDiscourseApi api, Store store}) anchored({
      Map<String, ChatMessagePage> extra = const {},
    }) => build(
      messages: {
        key(9): page([message(5, minute: 5)], canLoadMoreFuture: true),
        ...extra,
      },
    );

    test('reads what the site said is still in front of the window', () async {
      final subject = anchored();

      await subject.chat.openChannel(site, 9);

      expect(subject.chat.stream(site, 9).canLoadMoreFuture, isTrue);
      expect(subject.chat.stream(site, 9).atPresent, isFalse);
    });

    test('appends the page after the newest message it holds', () async {
      final subject = anchored(
        extra: {
          key(9, after: 5): page([
            message(6, minute: 6),
            message(7, minute: 7),
          ]),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadNewer(site, 9);

      expect(subject.api.chatMessagesRequested.last.after, 5);
      expect(subject.chat.stream(site, 9).messageIds, [5, 6, 7]);
      // The site answered without saying there was more, so the window now
      // runs to the present and the jump-to-now affordance has nothing to do.
      expect(subject.chat.stream(site, 9).atPresent, isTrue);
    });

    test(
      'an invalidated lease stops a newer page before client-id and API work',
      () async {
        final api = FakeDiscourseApi(
          chatMessagesByKey: {
            key(9): page([message(5)], canLoadMoreFuture: true),
            key(9, after: 5): page([message(6, minute: 1)]),
          },
        );
        final credentials = _ControllableCredentials()..keys[site] = 'key';
        final lifecycle = SiteLifecycle();
        final chat = ChatController(
          api: api,
          credentials: credentials,
          store: Store(),
          lifecycle: lifecycle,
        );
        addTearDown(chat.dispose);
        await chat.openChannel(site, 9);
        final initialClientIdCalls = credentials.clientIdCalls;
        final credentialsStarted = credentials.blockApiKey();

        final loading = chat.loadNewer(site, 9);
        await credentialsStarted;
        lifecycle.invalidate(site);
        credentials.releaseApiKey();
        await loading;

        expect(api.chatMessagesRequested, hasLength(1));
        expect(credentials.clientIdCalls, initialClientIdCalls);
      },
    );

    test('does not ask at all from a window already at the present', () async {
      // Which is every window fetched at the live edge, so this is the common
      // case rather than an edge one.
      final subject = build(
        messages: {
          key(9): page([message(5)]),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadNewer(site, 9);

      expect(subject.api.chatMessagesRequested, hasLength(1));
    });

    test('stops asking when a page arrives with nothing new in it', () async {
      final subject = anchored(
        extra: {
          key(9, after: 5): page([
            message(5, minute: 5),
          ], canLoadMoreFuture: true),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadNewer(site, 9);

      expect(subject.chat.stream(site, 9).atPresent, isTrue);
      expect(subject.chat.stream(site, 9).messageIds, [5]);
    });

    test('keeps the messages on screen when a page fails', () async {
      final subject = anchored();

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadNewer(site, 9);

      expect(subject.chat.stream(site, 9).messageIds, [5]);
      expect(subject.chat.stream(site, 9).error, isNull);
    });
  });

  group('jumping to the present', () {
    test('asks for the newest page rather than the anchored one', () async {
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMoreFuture: true),
          latestKey(9): page([message(9, minute: 9)]),
        },
      );
      await subject.chat.openChannel(site, 9);

      await subject.chat.showLatest(site, 9);

      expect(subject.api.chatMessagesRequested.last.fromLastRead, isFalse);
      expect(subject.chat.stream(site, 9).messageIds, [9]);
      expect(subject.chat.stream(site, 9).atPresent, isTrue);
    });

    test(
      'is a scroll rather than a fetch when the present is already held',
      () async {
        final subject = build(
          messages: {
            key(9): page([message(5)]),
          },
        );
        await subject.chat.openChannel(site, 9);

        await subject.chat.showLatest(site, 9);

        expect(subject.api.chatMessagesRequested, hasLength(1));
      },
    );

    test('tells the view to reposition, which paging does not', () async {
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMorePast: true),
          key(9, before: 5): page([message(1)]),
        },
      );

      await subject.chat.openChannel(site, 9);
      final opened = subject.chat.stream(site, 9).fetches;

      await subject.chat.loadOlder(site, 9);
      expect(subject.chat.stream(site, 9).fetches, opened);

      await subject.chat.openChannel(site, 9, force: true);
      expect(subject.chat.stream(site, 9).fetches, opened + 1);
    });

    test('an old page cannot merge into a replacement window', () async {
      final api = _PagingRaceApi();
      final store = Store();
      final credentials = FakeApiCredentialReader()..keys[site] = 'key';
      final chat = ChatController(
        api: api,
        credentials: credentials,
        store: store,
      );
      addTearDown(chat.dispose);

      await chat.openChannel(site, 9);
      final oldPage = chat.loadOlder(site, 9);
      await api.oldPageStarted.future;

      await chat.showLatest(site, 9);
      final newPage = chat.loadOlder(site, 9);
      await api.newPageStarted.future;

      api.oldPage.complete(page([message(1, minute: 1)]));
      await oldPage;
      expect(chat.stream(site, 9).messageIds, [9]);
      expect(chat.stream(site, 9).loadingOlder, isTrue);
      expect(store.read<ChatMessage>(site, 1), isNull);

      api.newPage.complete(page([message(8, minute: 8)]));
      await newPage;
      expect(chat.stream(site, 9).messageIds, [8, 9]);
      expect(chat.stream(site, 9).loadingOlder, isFalse);
    });

    test(
      'a replacement window stops an older page after client-id lookup',
      () async {
        final api = FakeDiscourseApi(
          chatMessagesByKey: {
            key(9): page([message(5)], canLoadMorePast: true),
            key(9, before: 5): page([message(1)]),
          },
        );
        final credentials = _ControllableCredentials()..keys[site] = 'key';
        final chat = ChatController(
          api: api,
          credentials: credentials,
          store: Store(),
        );
        addTearDown(chat.dispose);
        await chat.openChannel(site, 9);
        final clientIdStarted = credentials.blockClientId();

        final oldPage = chat.loadOlder(site, 9);
        await clientIdStarted;
        final replacement = chat.openChannel(site, 9, force: true);
        credentials.releaseClientId();
        await Future.wait([oldPage, replacement]);

        expect(
          api.chatMessagesRequested.where((request) => request.before == 5),
          isEmpty,
        );
        expect(api.chatMessagesRequested, hasLength(2));
      },
    );
  });

  group('paging into the past', () {
    test('pages before the oldest message it holds', () async {
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMorePast: true),
          key(9, before: 5): page([message(1), message(2, minute: 1)]),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadOlder(site, 9);

      expect(subject.api.chatMessagesRequested.last.before, 5);
      expect(subject.chat.stream(site, 9).messageIds, [1, 2, 5]);
    });

    test(
      'does not ask at all once the site says there is nothing older',
      () async {
        final subject = build(
          messages: {
            key(9): page([message(5)]),
          },
        );

        await subject.chat.openChannel(site, 9);
        await subject.chat.loadOlder(site, 9);

        expect(subject.api.chatMessagesRequested, hasLength(1));
      },
    );

    test('stops asking when a page arrives with nothing new in it', () async {
      // A cursor the site keeps answering the same page for would otherwise
      // spin the fill-pane fallback forever.
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMorePast: true),
          key(9, before: 5): page([
            message(5, minute: 5),
          ], canLoadMorePast: true),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadOlder(site, 9);

      expect(subject.chat.stream(site, 9).canLoadMorePast, isFalse);
      expect(subject.chat.stream(site, 9).messageIds, [5]);
    });

    test('collapses two scroll-driven asks into one request', () async {
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMorePast: true),
          key(9, before: 5): page([message(1)]),
        },
      );
      await subject.chat.openChannel(site, 9);

      // The list asks both from a scroll notification and from its last
      // itemBuilder, so a double call is the ordinary case rather than a bug.
      final first = subject.chat.loadOlder(site, 9);
      final second = subject.chat.loadOlder(site, 9);
      await Future.wait([first, second]);

      // One open plus one page of history, not two.
      expect(subject.api.chatMessagesRequested, hasLength(2));
    });

    test('keeps the messages on screen when a page of history fails', () async {
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMorePast: true),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadOlder(site, 9);

      expect(subject.chat.stream(site, 9).messageIds, [5]);
      // History that would not load is not worth an error state: what is on
      // screen is still true, and scrolling up again asks again.
      expect(subject.chat.stream(site, 9).error, isNull);
      expect(subject.chat.stream(site, 9).loadingOlder, isFalse);
    });

    test('has nothing to page from on an empty channel', () async {
      final subject = build(
        messages: {key(9): page([], canLoadMorePast: true)},
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadOlder(site, 9);

      expect(subject.api.chatMessagesRequested, hasLength(1));
    });
  });

  group('ordering the stream', () {
    test('drops a duplicate rather than naming a message twice', () async {
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMorePast: true),
          key(9, before: 5): page([
            message(3, minute: 3),
            message(5, minute: 5),
          ]),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadOlder(site, 9);

      expect(subject.chat.stream(site, 9).messageIds, [3, 5]);
    });

    test('orders two messages written in the same second by id', () async {
      // iso8601 carries seconds, so those two have equal dates on the wire, and
      // Dart's sort is unstable — without the tiebreak they swap places every
      // time a page is merged and the list reshuffles under the reader.
      final subject = build(
        messages: {
          key(9): page([
            message(7, second: 30),
            message(6, second: 30),
            message(8, second: 31),
          ]),
        },
      );

      await subject.chat.openChannel(site, 9);

      expect(subject.chat.stream(site, 9).messageIds, [6, 7, 8]);
    });

    test(
      'puts an older page before what it already held, whatever the ids say',
      () async {
        final subject = build(
          messages: {
            key(9): page([message(2, minute: 5)], canLoadMorePast: true),
            // A higher id but an earlier date: the site orders by date first and
            // so does this, because that is what keeps its cursors meaningful.
            key(9, before: 2): page([message(30, minute: 1)]),
          },
        );

        await subject.chat.openChannel(site, 9);
        await subject.chat.loadOlder(site, 9);

        expect(subject.chat.stream(site, 9).messageIds, [30, 2]);
      },
    );
  });

  group('forgetting a disconnected site', () {
    test('drops its channels, its streams and what was being asked', () async {
      final subject = build(
        channels: {
          site: ChatChannels(public: [channel(9)], direct: const []),
        },
        messages: {
          key(9): page([message(1)]),
        },
      );
      await subject.chat.loadChannels(site);
      await subject.chat.openChannel(site, 9);
      final stream = subject.chat.streamListenable(site, 9);

      subject.chat.forget(site);

      expect(subject.chat.publicChannels(site), isEmpty);
      expect(subject.chat.stream(site, 9).messageIds, isEmpty);
      expect(stream.value.messageIds, isEmpty);
      final reconnectedStream = subject.chat.streamListenable(site, 9);
      expect(reconnectedStream, isNot(same(stream)));
      expect(subject.chat.channelsError(site), isNull);

      await subject.chat.openChannel(site, 9);
      expect(stream.value.messageIds, isEmpty);
      expect(reconnectedStream.value.messageIds, [1]);
    });

    test(
      'puts nothing back after the site it was fetched for went away',
      () async {
        final gate = Completer<void>();
        final subject = build(
          messages: {
            key(9): page([message(1)]),
          },
          messageGate: gate,
        );

        final open = subject.chat.openChannel(site, 9);
        subject.chat.lifecycle.invalidate(site);
        subject.chat.forget(site);
        gate.complete();
        await open;

        expect(subject.chat.stream(site, 9).messageIds, isEmpty);
      },
    );

    test('lets a site connected again ask afresh', () async {
      final subject = build(
        channels: {
          site: ChatChannels(public: [channel(9)], direct: const []),
        },
      );
      await subject.chat.loadChannels(site);
      subject.chat.forget(site);

      await subject.chat.loadChannels(site);

      expect(subject.api.chatChannelsRequested, [site, site]);
      expect(subject.chat.publicChannels(site), hasLength(1));
    });
  });

  test(
    'disposed chat entry points complete without touching dependencies',
    () async {
      final subject = build();
      subject.chat.dispose();

      await subject.chat.loadChannels(site, force: true);
      await subject.chat.openChannel(site, 9, force: true);
      await subject.chat.showLatest(site, 9);
      await subject.chat.loadOlder(site, 9);
      await subject.chat.loadNewer(site, 9);

      expect(subject.api.chatChannelsRequested, isEmpty);
      expect(subject.api.chatMessagesRequested, isEmpty);
    },
  );

  group('crediting the reader with what they have seen', () {
    /// A site with one three-message channel, already open.
    Future<({ChatController chat, FakeDiscourseApi api, Store store})> reading({
      ChatChannel? held,
      WriteException? readFailure,
    }) async {
      final subject = build(
        channels: {
          site: ChatChannels(public: [held ?? channel(9)], direct: const []),
        },
        messages: {
          key(9): page([
            message(1),
            message(2, minute: 1),
            message(3, minute: 2),
          ]),
        },
        readFailure: readFailure,
      );
      await subject.chat.loadChannels(site);
      await subject.chat.openChannel(site, 9);
      return subject;
    }

    ChatChannel? held(Store store) => store.read<ChatChannel>(site, 9);

    test(
      'tells the site the newest message the reader has had on screen',
      () async {
        final subject = await reading(held: channel(9, lastRead: 1));

        await subject.chat.markRead(site, 9, 3);

        expect(subject.api.chatReadsMarked, [(channelId: 9, messageId: 3)]);
        expect(held(subject.store)?.membership.lastReadMessageId, 3);
      },
    );

    test('does not send an old read receipt with a new account key', () async {
      final gate = Completer<void>();
      final credentials = _GatedCredentials(gate)..keys[site] = 'account-a';
      final api = FakeDiscourseApi();
      final store = Store()..put(site, channel(9, lastRead: 1));
      final lifecycle = SiteLifecycle();
      final chat = ChatController(
        api: api,
        credentials: credentials,
        store: store,
        lifecycle: lifecycle,
      );
      addTearDown(chat.dispose);

      final marking = chat.markRead(site, 9, 3);
      await credentials.started.future;
      lifecycle.invalidate(site);
      credentials.keys[site] = 'account-b';
      gate.complete();
      await marking;

      expect(api.chatReadsMarked, isEmpty);
    });

    test(
      'forgetting a credential-gated read receipt delegates no write',
      () async {
        final api = FakeDiscourseApi();
        final credentials = _ControllableCredentials()..keys[site] = 'key';
        final store = Store()..put(site, channel(9, lastRead: 1));
        final chat = ChatController(
          api: api,
          credentials: credentials,
          store: store,
        );
        addTearDown(chat.dispose);
        final credentialsStarted = credentials.blockApiKey();

        final marking = chat.markRead(site, 9, 3);
        await credentialsStarted;
        chat.forget(site);
        credentials.releaseApiKey();
        await marking;

        expect(api.chatReadsMarked, isEmpty);
        expect(credentials.clientIdCalls, 0);
      },
    );

    test(
      'empties the counts on reaching the newest message there is',
      () async {
        final subject = await reading(
          held: channel(9, lastRead: 1, unread: 2, mentions: 1),
        );

        await subject.chat.markRead(site, 9, 3);

        expect(held(subject.store)?.tracking, ChatTracking.none);
        expect(held(subject.store)?.badge.isVisible, isFalse);
      },
    );

    test(
      'clears a DM when a newer thread reply is absent from the root stream',
      () async {
        final deltas = <(String, int)>[];
        final subject = build(
          onChatNotificationsDelta: (siteUrl, delta) {
            deltas.add((siteUrl, delta));
          },
          channels: {
            site: ChatChannels(
              direct: [
                channel(
                  9,
                  kind: ChatChannelKind.directMessage,
                  lastRead: 1,
                  unread: 6,
                  threadingEnabled: true,
                  // The channel serializer includes thread replies here, but
                  // the root message endpoint intentionally does not.
                  lastMessageId: 40,
                ),
              ],
            ),
          },
          messages: {
            key(9): page([
              message(1),
              message(2, minute: 1),
              message(3, minute: 2),
            ]),
          },
        );

        await subject.chat.loadChannels(site);
        await subject.chat.openChannel(site, 9);
        expect(
          subject.chat
              .headerIndicator(
                site,
                ChatHeaderIndicatorPreference.directMessagesAndMentions,
              )
              .urgentCount,
          6,
        );

        await subject.chat.markRead(site, 9, 3);

        expect(subject.chat.channel(site, 9)?.tracking, ChatTracking.none);
        expect(
          subject.chat
              .headerIndicator(
                site,
                ChatHeaderIndicatorPreference.directMessagesAndMentions,
              )
              .isVisible,
          isFalse,
        );
        expect(deltas, [(site, -6)]);
        expect(subject.api.chatReadsMarked, [(channelId: 9, messageId: 3)]);
      },
    );

    test(
      'does not restore unread state from an older tracking event',
      () async {
        final subject = build(
          currentUser: currentUser,
          channels: {
            site: ChatChannels(
              public: [channel(9, lastRead: 1, unread: 2, mentions: 1)],
              userTrackingBusLastId: 90,
            ),
          },
          messages: {
            key(9): page([
              message(1),
              message(2, minute: 1),
              message(3, minute: 2),
            ]),
          },
        );
        final tracker = attachTracker(subject.chat);
        await subject.chat.loadChannels(site);
        await subject.chat.openChannel(site, 9);

        await subject.chat.markRead(site, 9, 3);
        tracker.deliverPluginMessage('/chat/user-tracking-state/7', {
          'channel_id': 9,
          'last_read_message_id': 1,
          'unread_count': 2,
          'mention_count': 1,
          'watched_threads_unread_count': 0,
        });

        expect(held(subject.store)?.membership.lastReadMessageId, 3);
        expect(held(subject.store)?.tracking, ChatTracking.none);
        expect(held(subject.store)?.badge.isVisible, isFalse);
      },
    );

    test('keeps thread state when the main channel is read', () async {
      var now = DateTime.utc(2026, 8, 8, 12);
      final subject = build(
        currentUser: currentUser,
        clock: () => now,
        channels: {
          site: ChatChannels(
            public: [
              channel(
                9,
                lastRead: 1,
                unread: 2,
                mentions: 1,
                watchedThreads: 1,
                threadingEnabled: true,
                unreadThreadOverview: {31: DateTime.utc(2026, 8, 8, 11)},
                lastMessageId: 3,
                lastMessageAt: DateTime.utc(2026, 5, 5, 10, 2),
              ),
            ],
            newMessageBusLastIds: const {9: 70},
          ),
        },
        messages: {
          key(9): page([
            message(1),
            message(2, minute: 1),
            message(3, minute: 2),
          ]),
        },
      );
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      await subject.chat.openChannel(site, 9);

      await subject.chat.markRead(site, 9, 3);

      final read = subject.chat.channel(site, 9)!;
      expect(read.membership.lastViewedAt, now);
      expect(read.tracking.unreadCount, 0);
      expect(read.tracking.mentionCount, 0);
      expect(read.tracking.watchedThreadsUnreadCount, 1);
      expect(read.unreadThreadOverview, {31: DateTime.utc(2026, 8, 8, 11)});
      expect(read.unreadThreadsCountSinceLastViewed, 0);

      // Once the pane is gone, a later reply to that tracked public thread
      // can update the retained overview and become sidebar unread again.
      now = DateTime.utc(2026, 8, 8, 13, 1);
      tracker.deliverPluginMessage(
        '/chat/9/new-messages',
        newMessageEvent(
          channelId: 9,
          messageId: 4,
          authorId: 2,
          createdAt: '2026-08-08T13:00:00.000Z',
          type: 'thread',
          threadId: 31,
        ),
      );

      final replied = subject.chat.channel(site, 9)!;
      expect(replied.unreadThreadOverview, {31: DateTime.utc(2026, 8, 8, 13)});
      expect(replied.unreadThreadsCountSinceLastViewed, 1);
      expect(replied.badge.dot, isTrue);
    });

    test('an old visible edge cannot clear a newly arrived message', () async {
      final subject = build(
        currentUser: currentUser,
        channels: {
          site: ChatChannels(
            public: [
              channel(
                9,
                lastRead: 1,
                lastMessageId: 3,
                lastMessageAt: DateTime.utc(2026, 5, 5, 10, 2),
              ),
            ],
            newMessageBusLastIds: const {9: 70},
          ),
        },
        messages: {
          key(9): page([
            message(1),
            message(2, minute: 1),
            message(3, minute: 2),
          ]),
        },
      );
      final tracker = attachTracker(subject.chat);
      await subject.chat.loadChannels(site);
      await subject.chat.openChannel(site, 9);

      tracker.deliverPluginMessage(
        '/chat/9/new-messages',
        newMessageEvent(
          channelId: 9,
          messageId: 4,
          authorId: 2,
          createdAt: '2026-05-05T10:03:00.000Z',
        ),
      );
      await subject.chat.markRead(site, 9, 3);

      expect(held(subject.store)?.membership.lastReadMessageId, 3);
      expect(held(subject.store)?.tracking.unreadCount, 1);
      expect(held(subject.store)?.lastMessageId, 4);
    });

    test(
      'leaves the counts alone in the middle, where it cannot know',
      () async {
        // What is unread above the reader is a sum of mentions, watched threads
        // and plain messages counted over rows this app never fetched. The site
        // says; this does not guess.
        final subject = await reading(
          held: channel(9, lastRead: 1, unread: 2, mentions: 1),
        );

        await subject.chat.markRead(site, 9, 2);

        expect(held(subject.store)?.tracking.unreadCount, 2);
        expect(held(subject.store)?.tracking.mentionCount, 1);
        expect(held(subject.store)?.membership.lastReadMessageId, 2);
      },
    );

    test('keeps the counts while there is still a backlog in front', () async {
      // The last message *held* is not the last message there is when the
      // window is anchored behind the present, and emptying the counts there
      // would say the reader had caught up with messages they have not been
      // sent yet.
      final subject = build(
        channels: {
          site: ChatChannels(
            public: [channel(9, lastRead: 1, unread: 9)],
            direct: const [],
          ),
        },
        messages: {
          key(9): page([
            message(1),
            message(2, minute: 1),
            message(3, minute: 2),
          ], canLoadMoreFuture: true),
        },
      );
      await subject.chat.loadChannels(site);
      await subject.chat.openChannel(site, 9);

      await subject.chat.markRead(site, 9, 3);

      expect(held(subject.store)?.membership.lastReadMessageId, 3);
      expect(held(subject.store)?.tracking.unreadCount, 9);
    });

    test('never moves the reader backwards into the past', () async {
      // Which is also the site's rule — `ensure_message_id_recency` — and the
      // reader's: paging up must not undo what they have already read.
      final subject = await reading(held: channel(9, lastRead: 3));

      await subject.chat.markRead(site, 9, 1);

      expect(subject.api.chatReadsMarked, isEmpty);
      expect(held(subject.store)?.membership.lastReadMessageId, 3);
    });

    test('writes once for a message it has already recorded', () async {
      // The optimistic update is the whole of the de-duplication: a second
      // scroll tick that sees the same message reads back its own answer.
      final subject = await reading(held: channel(9, lastRead: 1));

      await subject.chat.markRead(site, 9, 3);
      await subject.chat.markRead(site, 9, 3);

      expect(subject.api.chatReadsMarked, hasLength(1));
    });

    test(
      'serializes read receipts and keeps only the newest queued one',
      () async {
        final api = _GatedChatReadApi();
        final credentials = FakeApiCredentialReader()..keys[site] = 'key';
        final store = Store()..put(site, channel(9, lastRead: 1));
        final chat = ChatController(
          api: api,
          credentials: credentials,
          store: store,
        );
        addTearDown(chat.dispose);

        final first = chat.markRead(site, 9, 2);
        await api.firstReadStarted.future;
        final superseded = chat.markRead(site, 9, 3);
        final newest = chat.markRead(site, 9, 4);
        await Future<void>.delayed(Duration.zero);

        expect(api.chatReadsMarked, [(channelId: 9, messageId: 2)]);

        api.firstReadGate.complete();
        await Future.wait([first, superseded, newest]);

        expect(api.chatReadsMarked, [
          (channelId: 9, messageId: 2),
          (channelId: 9, messageId: 4),
        ]);
      },
    );

    test('an old session cannot dequeue a new session read receipt', () async {
      final api = _SessionReadRaceApi();
      final credentials = FakeApiCredentialReader()..keys[site] = 'account-a';
      final lifecycle = SiteLifecycle();
      final store = Store()..put(site, channel(9, lastRead: 1));
      final chat = ChatController(
        api: api,
        credentials: credentials,
        store: store,
        lifecycle: lifecycle,
      );
      addTearDown(chat.dispose);

      final old = chat.markRead(site, 9, 2);
      await api.firstReadStarted.future;

      lifecycle.invalidate(site);
      chat.forget(site);
      credentials.keys[site] = 'account-b';
      store.put(site, channel(9, lastRead: 1));

      final current = chat.markRead(site, 9, 3);
      await api.secondReadStarted.future;
      final queued = chat.markRead(site, 9, 4);

      api.firstReadGate.complete();
      await old;
      await Future<void>.delayed(Duration.zero);

      expect(api.chatReadsMarked, [
        (channelId: 9, messageId: 2),
        (channelId: 9, messageId: 3),
      ]);

      api.secondReadGate.complete();
      await Future.wait([current, queued]);
      expect(api.chatReadsMarked, [
        (channelId: 9, messageId: 2),
        (channelId: 9, messageId: 3),
        (channelId: 9, messageId: 4),
      ]);
    });

    test('says nothing about a channel the reader does not follow', () async {
      // There is no membership row to move, and the site answers 404.
      final subject = await reading(held: channel(9, following: false));

      await subject.chat.markRead(site, 9, 3);

      expect(subject.api.chatReadsMarked, isEmpty);
    });

    test('says nothing about a channel it has never heard of', () async {
      final subject = build();

      await subject.chat.markRead(site, 404, 3);

      expect(subject.api.chatReadsMarked, isEmpty);
    });

    test('keeps the guess when the site refuses the write', () async {
      // Nobody asked for this and nobody is waiting on it, so there is nothing
      // to tell and nothing to put back. The next channel list corrects it.
      final subject = await reading(
        held: channel(9, lastRead: 1, unread: 2),
        readFailure: const WriteException(WriteFailure.unreachable),
      );

      await subject.chat.markRead(site, 9, 3);

      expect(held(subject.store)?.membership.lastReadMessageId, 3);
      expect(held(subject.store)?.tracking, ChatTracking.none);
    });

    test('pins the unread divider to where the reader was on opening', () async {
      // Otherwise the line slides down the screen ahead of the reader and then
      // vanishes, which is the reason Discourse snapshots it too.
      final subject = await reading(held: channel(9, lastRead: 1));

      await subject.chat.markRead(site, 9, 3);

      expect(subject.chat.stream(site, 9).lastReadOnOpen, 1);
    });

    test('moves the divider when the channel is explicitly reopened', () async {
      final subject = await reading(held: channel(9, lastRead: 1));
      await subject.chat.markRead(site, 9, 3);

      await subject.chat.openChannel(site, 9, force: true);

      expect(subject.chat.stream(site, 9).lastReadOnOpen, 3);
    });
  });
}

final class _GatedChatReadApi extends FakeDiscourseApi {
  final Completer<void> firstReadStarted = Completer<void>();
  final Completer<void> firstReadGate = Completer<void>();

  @override
  Future<void> markChatChannelRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    chatReadsMarked.add((channelId: channelId, messageId: messageId));
    if (!firstReadStarted.isCompleted) {
      firstReadStarted.complete();
      await firstReadGate.future;
    }
  }
}

final class _SessionReadRaceApi extends FakeDiscourseApi {
  final Completer<void> firstReadStarted = Completer<void>();
  final Completer<void> firstReadGate = Completer<void>();
  final Completer<void> secondReadStarted = Completer<void>();
  final Completer<void> secondReadGate = Completer<void>();

  @override
  Future<void> markChatChannelRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    chatReadsMarked.add((channelId: channelId, messageId: messageId));
    if (!firstReadStarted.isCompleted) {
      firstReadStarted.complete();
      await firstReadGate.future;
      return;
    }
    if (!secondReadStarted.isCompleted) {
      secondReadStarted.complete();
      await secondReadGate.future;
    }
  }
}

final class _PagingRaceApi extends FakeDiscourseApi {
  final Completer<ChatMessagePage> oldPage = Completer<ChatMessagePage>();
  final Completer<ChatMessagePage> newPage = Completer<ChatMessagePage>();
  final Completer<void> oldPageStarted = Completer<void>();
  final Completer<void> newPageStarted = Completer<void>();

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
  }) {
    if (fromLastRead) {
      return Future.value(
        page(
          [message(5, minute: 5)],
          canLoadMorePast: true,
          canLoadMoreFuture: true,
        ),
      );
    }
    if (before == null) {
      return Future.value(page([message(9, minute: 9)], canLoadMorePast: true));
    }
    if (before == 5) {
      oldPageStarted.complete();
      return oldPage.future;
    }
    if (before == 9) {
      newPageStarted.complete();
      return newPage.future;
    }
    throw StateError('Unexpected chat page before $before');
  }
}
