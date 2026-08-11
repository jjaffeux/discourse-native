import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const String site = 'https://meta.discourse.org';
const String other = 'https://other.example';

ChatMessage message(int id, {int second = 0, int minute = 0}) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>$id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: DateTime.utc(2026, 5, 5, 10, minute, second),
);

ChatMessagePage page(
  List<ChatMessage> messages, {
  bool canLoadMorePast = false,
  bool canLoadMoreFuture = false,
}) => (
  messages: messages,
  canLoadMorePast: canLoadMorePast,
  canLoadMoreFuture: canLoadMoreFuture,
);

/// Followed by default, which is the only kind `/chat/api/me/channels` returns.
ChatChannel channel(
  int id, {
  String title = 'Bugs',
  bool following = true,
  bool starred = false,
  int? lastRead,
  int unread = 0,
  int mentions = 0,
}) => ChatChannel(
  id: id,
  title: title,
  kind: ChatChannelKind.category,
  membership: ChatMembership(
    following: following,
    starred: starred,
    lastReadMessageId: lastRead,
  ),
  tracking: ChatTracking(unreadCount: unread, mentionCount: mentions),
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
  FakeApiCredentialReader? credentialReader,
  DiscourseUser? currentUser,
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
            public: const [
              ChatChannel(
                id: 9,
                title: 'Bugs',
                kind: ChatChannelKind.category,
                unreadThreadCount: 1,
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

    test('shows a spinner only where there is nothing behind it', () async {
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
      // replacing a conversation with a spinner.
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
        final subject = build();

        await subject.chat.openChannel(site, 9);

        expect(subject.chat.stream(site, 9).error, isNotNull);
        expect(subject.chat.stream(site, 9).fetchedOnce, isTrue);
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
