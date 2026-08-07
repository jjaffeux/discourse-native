import 'dart:async';

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
}) => (messages: messages, canLoadMorePast: canLoadMorePast);

ChatChannel channel(int id, {String title = 'Bugs'}) =>
    ChatChannel(id: id, title: title, kind: ChatChannelKind.category);

/// A controller wired to a fake site the reader is already signed in to.
({ChatController chat, FakeDiscourseApi api, Store store}) build({
  Map<String, ChatChannels> channels = const {},
  Map<String, ChatMessagePage> messages = const {},
  Completer<void>? channelGate,
  Completer<void>? messageGate,
}) {
  final api = FakeDiscourseApi(
    chatChannelsBySite: channels,
    chatChannelGate: channelGate,
    chatMessagesByKey: messages,
    chatMessageGate: messageGate,
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

String key(int channelId, [int? before]) =>
    FakeDiscourseApi.chatMessagesKey(channelId, before);

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
    test('asks for the newest page and holds it oldest first', () async {
      final subject = build(
        messages: {
          key(9): page([message(1), message(2, minute: 1)]),
        },
      );

      await subject.chat.openChannel(site, 9);

      expect(subject.api.chatMessagesRequested, [(channelId: 9, before: null)]);
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
          key(9, 5): page([message(1), message(2, minute: 1)]),
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

  group('paging into the past', () {
    test('pages before the oldest message it holds', () async {
      final subject = build(
        messages: {
          key(9): page([message(5, minute: 5)], canLoadMorePast: true),
          key(9, 5): page([message(1), message(2, minute: 1)]),
        },
      );

      await subject.chat.openChannel(site, 9);
      await subject.chat.loadOlder(site, 9);

      expect(subject.api.chatMessagesRequested.last, (
        channelId: 9,
        before: 5,
      ));
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
          key(9, 5): page([message(5, minute: 5)], canLoadMorePast: true),
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
          key(9, 5): page([message(1)]),
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
          key(9, 5): page([message(3, minute: 3), message(5, minute: 5)]),
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
          key(9, 2): page([message(30, minute: 1)]),
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
}
