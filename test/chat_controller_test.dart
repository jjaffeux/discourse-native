import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
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
  int? lastRead,
  int unread = 0,
  int mentions = 0,
}) => ChatChannel(
  id: id,
  title: title,
  kind: ChatChannelKind.category,
  membership: ChatMembership(
    following: following,
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
}) {
  final api = FakeDiscourseApi(
    chatChannelsBySite: channels,
    chatChannelGate: channelGate,
    chatMessagesByKey: messages,
    chatMessageGate: messageGate,
    chatReadFailure: readFailure,
  );
  final authenticator = FakeAuthenticator()..keys[site] = 'key';
  final store = Store();
  return (
    chat: ChatController(
      api: api,
      authenticator: authenticator,
      store: store,
    ),
    api: api,
    store: store,
  );
}

String key(int channelId, {int? before, int? after}) =>
    FakeDiscourseApi.chatMessagesKey(channelId, before: before, after: after);

String latestKey(int channelId) =>
    FakeDiscourseApi.chatMessagesLatestKey(channelId);

void main() {
  // No widgets here, but the controller defers a notification raised mid-frame
  // to a post-frame callback — see `ChatController._notify` — and asking the
  // scheduler which phase it is in needs a binding to ask.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loading a site’s channels', () {
    test('puts the channels in the store and keeps the order it was given', () async {
      final subject = build(
        channels: {
          site: (public: [channel(9), channel(4)], direct: [channel(12)]),
        },
      );

      await subject.chat.loadChannels(site);

      expect(subject.chat.publicChannels(site).map((c) => c.id), [9, 4]);
      expect(subject.chat.directChannels(site).map((c) => c.id), [12]);
      expect(subject.store.read<ChatChannel>(site, 9)!.title, 'Bugs');
    });

    test('asks a site once rather than once per caller', () async {
      final subject = build(
        channels: {
          site: (public: [channel(9)], direct: const []),
        },
      );

      await subject.chat.loadChannels(site);
      await subject.chat.loadChannels(site);

      expect(subject.api.chatChannelsRequested, [site]);
    });

    test('collapses two callers arriving before the first answer into one ask', () async {
      final gate = Completer<void>();
      final subject = build(
        channels: {
          site: (public: [channel(9)], direct: const []),
        },
        channelGate: gate,
      );

      final first = subject.chat.loadChannels(site);
      final second = subject.chat.loadChannels(site);
      gate.complete();
      await Future.wait([first, second]);

      expect(subject.api.chatChannelsRequested, [site]);
    });

    test('draws nothing for a site that will not answer, and says why', () async {
      final subject = build();

      await subject.chat.loadChannels(site);

      expect(subject.chat.publicChannels(site), isEmpty);
      expect(subject.chat.channelsError(site), isNotNull);
    });

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
          site: (public: [channel(9)], direct: const []),
        },
      );

      await subject.chat.loadChannels(site);
      await subject.chat.loadChannels(other);

      expect(subject.chat.publicChannels(site), hasLength(1));
      expect(subject.chat.publicChannels(other), isEmpty);
    });
  });

  group('opening a channel', () {
    test('asks from where the reader left off and holds it oldest first', () async {
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
    });

    test('reads a channel nobody has written in as empty rather than as unread', () async {
      final subject = build(messages: {key(9): page([])});

      await subject.chat.openChannel(site, 9);

      expect(subject.chat.stream(site, 9).isEmpty, isTrue);
      expect(subject.chat.stream(site, 9).error, isNull);
    });

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

      // Re-opening refreshes underneath what is already there rather than
      // replacing a conversation with a spinner.
      final second = subject.chat.openChannel(site, 9);
      expect(subject.chat.stream(site, 9).loading, isFalse);
      await second;
    });

    test('replaces rather than merges, because a hole would break paging', () async {
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
      await subject.chat.openChannel(site, 9);

      expect(subject.chat.stream(site, 9).messageIds, [9]);
    });

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
      await subject.chat.openChannel(site, 9);

      // A conversation that was true a moment ago beats an error where it was,
      // and the next open asks again.
      expect(subject.chat.stream(site, 9).messageIds, [1]);
      expect(subject.chat.stream(site, 9).error, isNull);
      expect(subject.api.chatMessagesRequested, hasLength(2));
    });

    test('says so when the first ask fails and there is nothing to fall back on', () async {
      final subject = build();

      await subject.chat.openChannel(site, 9);

      expect(subject.chat.stream(site, 9).error, isNotNull);
      expect(subject.chat.stream(site, 9).fetchedOnce, isTrue);
    });
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
          key(9, after: 5): page([message(6, minute: 6), message(7, minute: 7)]),
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
          key(9, after: 5): page([message(5, minute: 5)], canLoadMoreFuture: true),
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

    test('is a scroll rather than a fetch when the present is already held', () async {
      final subject = build(
        messages: {
          key(9): page([message(5)]),
        },
      );
      await subject.chat.openChannel(site, 9);

      await subject.chat.showLatest(site, 9);

      expect(subject.api.chatMessagesRequested, hasLength(1));
    });

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

      await subject.chat.openChannel(site, 9);
      expect(subject.chat.stream(site, 9).fetches, opened + 1);
    });
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

    test('does not ask at all once the site says there is nothing older', () async {
      final subject = build(
        messages: {
          key(9): page([message(5)]),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadOlder(site, 9);

      expect(subject.api.chatMessagesRequested, hasLength(1));
    });

    test('stops asking when a page arrives with nothing new in it', () async {
      // A cursor the site keeps answering the same page for would otherwise
      // spin the fill-pane fallback forever.
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMorePast: true),
          key(9, before: 5): page([message(5, minute: 5)], canLoadMorePast: true),
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
          key(9, before: 5): page([message(3, minute: 3), message(5, minute: 5)]),
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

    test('puts an older page before what it already held, whatever the ids say', () async {
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
    });
  });

  group('forgetting a disconnected site', () {
    test('drops its channels, its streams and what was being asked', () async {
      final subject = build(
        channels: {
          site: (public: [channel(9)], direct: const []),
        },
        messages: {
          key(9): page([message(1)]),
        },
      );
      await subject.chat.loadChannels(site);
      await subject.chat.openChannel(site, 9);

      subject.chat.forget(site);

      expect(subject.chat.publicChannels(site), isEmpty);
      expect(subject.chat.stream(site, 9).messageIds, isEmpty);
      expect(subject.chat.channelsError(site), isNull);
    });

    test('puts nothing back after the site it was fetched for went away', () async {
      final gate = Completer<void>();
      final subject = build(
        messages: {
          key(9): page([message(1)]),
        },
        messageGate: gate,
      );

      final open = subject.chat.openChannel(site, 9);
      subject.chat.forget(site);
      gate.complete();
      await open;

      expect(subject.chat.stream(site, 9).messageIds, isEmpty);
    });

    test('lets a site connected again ask afresh', () async {
      final subject = build(
        channels: {
          site: (public: [channel(9)], direct: const []),
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
          site: (public: [held ?? channel(9)], direct: const []),
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

    test('tells the site the newest message the reader has had on screen', () async {
      final subject = await reading(held: channel(9, lastRead: 1));

      await subject.chat.markRead(site, 9, 3);

      expect(subject.api.chatReadsMarked, [(channelId: 9, messageId: 3)]);
      expect(held(subject.store)?.membership.lastReadMessageId, 3);
    });

    test('empties the counts on reaching the newest message there is', () async {
      final subject = await reading(
        held: channel(9, lastRead: 1, unread: 2, mentions: 1),
      );

      await subject.chat.markRead(site, 9, 3);

      expect(held(subject.store)?.tracking, ChatTracking.none);
      expect(held(subject.store)?.badge.isVisible, isFalse);
    });

    test('leaves the counts alone in the middle, where it cannot know', () async {
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
    });

    test('keeps the counts while there is still a backlog in front', () async {
      // The last message *held* is not the last message there is when the
      // window is anchored behind the present, and emptying the counts there
      // would say the reader had caught up with messages they have not been
      // sent yet.
      final subject = build(
        channels: {
          site: (
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

    test('moves the divider only when the channel is opened again', () async {
      final subject = await reading(held: channel(9, lastRead: 1));
      await subject.chat.markRead(site, 9, 3);

      await subject.chat.openChannel(site, 9);

      expect(subject.chat.stream(site, 9).lastReadOnOpen, 3);
    });
  });
}
