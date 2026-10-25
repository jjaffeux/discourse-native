import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_read_receipt_owner.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://chat.example';
const _channel = ChatChannel(
  id: 9,
  title: 'Chat',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true, lastReadMessageId: 1),
);
const _thread = ChatThread(
  id: 22,
  channelId: 9,
  status: 'open',
  replyCount: 3,
  membership: ChatThreadMembership(threadId: 22, lastReadMessageId: 1),
);

ChatReadReceiptSnapshot _snapshot(
  PluginSiteLease lease, {
  ChatChannel channel = _channel,
  bool isLocalMessage = false,
  bool atPresent = true,
}) => ChatReadReceiptSnapshot(
  lease: lease,
  channel: channel,
  thread: _thread,
  isLocalMessage: isLocalMessage,
  atPresent: atPresent,
  newestMessageId: 3,
);

void main() {
  test(
    'stale root counts project without delivery or moving viewed time back',
    () async {
      final requests = FakePluginRequestHost();
      final api = _ReadApi();
      final viewedAt = DateTime.utc(2026, 10, 24, 12);
      var held = ChatChannel(
        id: 9,
        title: 'Chat',
        kind: ChatChannelKind.category,
        membership: ChatMembership(
          following: true,
          lastReadMessageId: 3,
          lastViewedAt: viewedAt,
        ),
        tracking: const ChatTracking(unreadCount: 2, mentionCount: 1),
      );
      final admission = ChatReadReceiptOwner.admit(
        const ChatChannelTarget(9),
        3,
        _snapshot(requests.capture(_site), channel: held),
      )!;
      final owner = ChatReadReceiptOwner(
        siteUrl: _site,
        target: const ChatChannelTarget(9),
        api: api,
        requests: requests,
        retries: ChatReadReceiptRetries(),
        clock: () => viewedAt.subtract(const Duration(hours: 1)),
        isCurrent: () => true,
        publish: (read, at) {
          held = (read as ChatChannelRead).project(held, at)!;
        },
      );

      await owner.markRead(admission);

      expect(held.tracking, ChatTracking.none);
      expect(held.membership.lastReadMessageId, 3);
      expect(held.membership.lastViewedAt, viewedAt);
      expect(api.chatReadsMarked, isEmpty);
      expect(owner.preventsEviction, isFalse);
    },
  );

  test('stale root counts re-admit only the newest row at the present', () {
    final lease = FakePluginRequestHost().capture(_site);
    const mentioned = ChatChannel(
      id: 9,
      title: 'Chat',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true, lastReadMessageId: 3),
      tracking: ChatTracking(mentionCount: 1),
    );
    ChatReadAdmission? admit(int messageId, {bool atPresent = true}) =>
        ChatReadReceiptOwner.admit(
          const ChatChannelTarget(9),
          messageId,
          _snapshot(lease, channel: mentioned, atPresent: atPresent),
        );

    final read = admit(3)! as ChatChannelRead;
    expect(read.shouldDeliver, isFalse);
    expect(
      read.project(mentioned, DateTime.utc(2026))!.tracking,
      ChatTracking.none,
    );
    expect(admit(3, atPresent: false), isNull);
    expect(admit(2), isNull);
  });

  test('an unfollowed channel admits no read', () {
    expect(
      ChatReadReceiptOwner.admit(
        const ChatChannelTarget(9),
        3,
        _snapshot(
          FakePluginRequestHost().capture(_site),
          channel: const ChatChannel(
            id: 9,
            title: 'Chat',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: false, lastReadMessageId: 1),
          ),
        ),
      ),
      isNull,
    );
  });

  test('retry debt is isolated by site and full target', () async {
    final retries = ChatReadReceiptRetries();
    final channel = _ReadFixture(const ChatChannelTarget(9), retries: retries)
      ..api.readFailure = const WriteException(WriteFailure.unreachable);
    final thread =
        _ReadFixture(
            const ChatThreadTarget(channelId: 9, threadId: 22),
            retries: retries,
          )
          ..thread = _thread.copyWith(
            membership: _thread.membership!.withLastReadMessageId(3),
          );
    final otherSite = _ReadFixture(
      const ChatChannelTarget(9),
      siteUrl: 'https://other.example',
      retries: retries,
    )..channel = _channel.withLastRead(3, caughtUp: true);
    await channel.observe(3);

    await thread.observe(3);
    await otherSite.observe(3);
    expect(thread.api.attempts, isEmpty);
    expect(otherSite.api.attempts, isEmpty);

    channel.api.readFailure = null;
    await channel.observe(3);
    expect(channel.api.attempts, [3, 3]);
  });

  for (final target in <ChatStreamTarget>[
    const ChatChannelTarget(9),
    const ChatThreadTarget(channelId: 9, threadId: 22),
  ]) {
    test(
      '${target.storageKey} excludes positive local IDs and duplicate cursors',
      () {
        final lease = FakePluginRequestHost().capture(_site);
        expect(
          ChatReadReceiptOwner.admit(
            target,
            3,
            _snapshot(lease, isLocalMessage: true),
          ),
          isNull,
        );
        expect(ChatReadReceiptOwner.admit(target, 1, _snapshot(lease)), isNull);
      },
    );

    test(
      '${target.storageKey} excludes non-positive IDs from an unset cursor',
      () {
        final unread = ChatReadReceiptSnapshot(
          lease: FakePluginRequestHost().capture(_site),
          channel: const ChatChannel(
            id: 9,
            title: 'Chat',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
          ),
          thread: const ChatThread(
            id: 22,
            channelId: 9,
            status: 'open',
            replyCount: 3,
            membership: ChatThreadMembership(threadId: 22),
          ),
          isLocalMessage: false,
          atPresent: true,
          newestMessageId: 3,
        );

        expect(ChatReadReceiptOwner.admit(target, 0, unread), isNull);
        expect(ChatReadReceiptOwner.admit(target, -1, unread), isNull);
        expect(ChatReadReceiptOwner.admit(target, 1, unread), isNotNull);
      },
    );

    test(
      '${target.storageKey} admission captured before an account change publishes nothing',
      () async {
        final fixture = _ReadFixture(target);
        final admission = ChatReadReceiptOwner.admit(
          target,
          3,
          _snapshot(fixture.requests.capture(fixture.siteUrl)),
        )!;
        fixture.requests.lifecycle.invalidate(fixture.siteUrl);

        await fixture.owner.markRead(admission);

        expect(fixture.publications, 0);
        expect(fixture.lastRead, 1);
        expect(fixture.api.attempts, isEmpty);
      },
    );

    test(
      '${target.storageKey} retired owner neither publishes nor delivers',
      () async {
        final fixture = _ReadFixture(target);
        fixture.owner.retire();

        await fixture.observe(3);

        expect(fixture.publications, 0);
        expect(fixture.lastRead, 1);
        expect(fixture.api.attempts, isEmpty);
      },
    );

    test(
      '${target.storageKey} newer failure replaces older debt without resending it',
      () async {
        final fixture = _ReadFixture(target)
          ..api.readFailure = const WriteException(WriteFailure.unreachable);
        await fixture.observe(3);
        await fixture.observe(4);
        fixture.api.readFailure = null;

        await fixture.observe(3);
        expect(fixture.api.attempts, [3, 4]);

        await fixture.observe(4);
        expect(fixture.api.attempts, [3, 4, 4]);
      },
    );

    test(
      '${target.storageKey} replaced account delivery leaves new debt',
      () async {
        final fixture = _ReadFixture(target);
        final gate = Completer<void>();
        fixture.api.gates[4] = gate;
        final replaced = fixture.observe(4);
        await fixture.api.started.future;
        fixture.requests.lifecycle.invalidate(fixture.siteUrl);
        fixture.credentials.keys[fixture.siteUrl] = 'account-b';
        fixture.replaceOwner();
        fixture.channel = _channel;
        fixture.thread = _thread;
        fixture.api.failures[3] = const WriteException(
          WriteFailure.unreachable,
        );
        await fixture.observe(3);
        fixture.api.failures.remove(3);

        gate.complete();
        await replaced;
        await fixture.observe(3);

        expect(fixture.api.attempts, [4, 3, 3]);
      },
    );

    for (final failure in [
      const WriteException(WriteFailure.unreachable, notSent: true),
      const WriteException(WriteFailure.unreachable),
    ]) {
      test(
        '${target.storageKey} retries ${failure.notSent ? 'unsent' : 'uncertain'} delivery only on another observation',
        () async {
          final fixture = _ReadFixture(target)..api.readFailure = failure;

          await fixture.observe(3);
          expect(fixture.lastRead, 3);
          expect(fixture.owner.preventsEviction, isFalse);
          await Future<void>.delayed(Duration.zero);
          expect(fixture.api.attempts, [3]);

          fixture.api.readFailure = null;
          await fixture.observe(3);
          await fixture.observe(3);

          expect(fixture.api.attempts, [3, 3]);
          expect(fixture.lastRead, 3);
          expect(fixture.owner.preventsEviction, isFalse);
        },
      );
    }

    test(
      '${target.storageKey} retry preserves newer visible progress',
      () async {
        final fixture = _ReadFixture(target)
          ..api.readFailure = const WriteException(WriteFailure.unreachable);
        await fixture.observe(3);
        final viewedAt = DateTime.utc(3000);
        fixture.channel = fixture.channel
            .withLastRead(5, caughtUp: false)
            .withLastViewedAt(viewedAt);
        fixture.thread = fixture.thread.copyWith(
          membership: fixture.thread.membership!.withLastReadMessageId(5),
        );
        fixture.api.readFailure = null;

        await fixture.observe(3);

        expect(fixture.api.attempts, [3, 3]);
        expect(fixture.lastRead, 5);
        if (!target.isThread) {
          expect(fixture.channel.membership.lastViewedAt, viewedAt);
        }
      },
    );

    test('${target.storageKey} retries after credentials return', () async {
      final fixture = _ReadFixture(target);
      fixture.credentials.keys.clear();

      await fixture.observe(3);
      expect(fixture.lastRead, 3);
      expect(fixture.api.attempts, isEmpty);
      expect(fixture.owner.preventsEviction, isFalse);

      fixture.credentials.keys[fixture.siteUrl] = 'key';
      await fixture.observe(3);
      await fixture.observe(3);

      expect(fixture.api.attempts, [3]);
      expect(fixture.lastRead, 3);
    });

    test('${target.storageKey} advances past an undelivered cursor', () async {
      final fixture = _ReadFixture(target)
        ..api.readFailure = const WriteException(WriteFailure.unreachable);
      await fixture.observe(3);
      await fixture.observe(2);
      expect(fixture.api.attempts, [3]);
      expect(fixture.lastRead, 3);

      fixture.api.readFailure = null;
      await fixture.observe(4);
      await fixture.observe(3);
      await fixture.observe(4);

      expect(fixture.api.attempts, [3, 4]);
      expect(fixture.lastRead, 4);
    });

    test(
      '${target.storageKey} newer queued success settles an older failure',
      () async {
        final fixture = _ReadFixture(target);
        final gate = Completer<void>();
        fixture.api.gates[2] = gate;
        fixture.api.failures[2] = const WriteException(
          WriteFailure.unreachable,
        );
        var firstDone = false;
        var newestDone = false;
        final first = fixture.observe(2).then((_) => firstDone = true);
        await fixture.api.started.future;
        final superseded = fixture.observe(3);
        final newest = fixture.observe(4).then((_) => newestDone = true);
        await fixture.observe(4);
        await fixture.observe(2);
        expect(firstDone, isFalse);
        expect(newestDone, isFalse);
        expect(fixture.lastRead, 4);

        gate.complete();
        await Future.wait([first, superseded, newest]);
        await fixture.observe(4);

        expect(fixture.api.attempts, [2, 4]);
        expect(fixture.lastRead, 4);
        expect(firstDone, isTrue);
        expect(newestDone, isTrue);
      },
    );

    test(
      '${target.storageKey} duplicate retry finishes during delivery',
      () async {
        final fixture = _ReadFixture(target)
          ..api.readFailure = const WriteException(WriteFailure.unreachable);
        await fixture.observe(3);
        fixture.api.readFailure = null;
        final gate = Completer<void>();
        fixture.api.gates[3] = gate;
        var completed = false;
        final retry = fixture.observe(3).then((_) => completed = true);
        await Future<void>.delayed(Duration.zero);
        expect(fixture.api.attempts, [3, 3]);
        final publications = fixture.publications;

        await fixture.observe(3);

        expect(fixture.publications, publications);
        expect(completed, isFalse);
        expect(fixture.api.attempts, [3, 3]);
        gate.complete();
        await retry;
        await fixture.observe(3);
        expect(completed, isTrue);
        expect(fixture.api.attempts, [3, 3]);
      },
    );

    test('${target.storageKey} retries after its owner is evicted', () async {
      final fixture = _ReadFixture(target)
        ..api.readFailure = const WriteException(WriteFailure.unreachable);
      await fixture.observe(3);
      expect(fixture.owner.preventsEviction, isFalse);
      fixture.replaceOwner();

      fixture.api.readFailure = null;
      await fixture.observe(3);
      await fixture.observe(3);

      expect(fixture.api.attempts, [3, 3]);
      expect(fixture.lastRead, 3);
    });

    test(
      '${target.storageKey} discards debt from a replaced account',
      () async {
        final fixture = _ReadFixture(target)
          ..api.readFailure = const WriteException(WriteFailure.unreachable);
        await fixture.observe(3);
        fixture.requests.lifecycle.invalidate(fixture.siteUrl);
        fixture.credentials.keys[fixture.siteUrl] = 'account-b';
        fixture.replaceOwner();
        fixture.api.readFailure = null;

        await fixture.observe(3);

        expect(fixture.api.attempts, [3]);
        fixture.channel = _channel;
        fixture.thread = _thread;
        await fixture.observe(3);
        expect(fixture.api.attempts, [3, 3]);
      },
    );

    test(
      '${target.storageKey} retired delivery cannot record a later failure',
      () async {
        final fixture = _ReadFixture(target);
        final gate = Completer<void>();
        fixture.api.gates[3] = gate;
        fixture.api.readFailure = const WriteException(
          WriteFailure.unreachable,
        );
        final first = fixture.observe(3);
        await fixture.api.started.future;
        fixture.replaceOwner();
        gate.complete();
        await first;
        fixture.api.readFailure = null;

        await fixture.observe(3);

        expect(fixture.api.attempts, [3]);
        expect(fixture.lastRead, 3);
      },
    );

    for (final retire in [false, true]) {
      test(
        '${target.storageKey} disowns credentials after ${retire ? 'retirement' : 'account replacement'}',
        () async {
          final credentials = _HeldCredentials()..keys[_site] = 'account-a';
          final requests = FakePluginRequestHost(credentials: credentials);
          final api = _ReadApi();
          var publications = 0;
          final owner = ChatReadReceiptOwner(
            siteUrl: _site,
            target: target,
            api: api,
            requests: requests,
            retries: ChatReadReceiptRetries(),
            clock: DateTime.now,
            isCurrent: () => true,
            publish: (_, _) => publications++,
          );
          final admission = ChatReadReceiptOwner.admit(
            target,
            3,
            _snapshot(requests.capture(_site)),
          )!;

          var completed = false;
          final reading = owner
              .markRead(admission)
              .then((_) => completed = true);
          await credentials.started.future;
          expect(publications, 1);
          expect(owner.preventsEviction, isTrue);
          if (retire) {
            owner.retire();
            expect(owner.preventsEviction, isFalse);
          } else {
            requests.lifecycle.invalidate(_site);
            credentials.keys[_site] = 'account-b';
          }
          expect(completed, isFalse);
          credentials.release.complete();
          await reading;

          expect(completed, isTrue);
          expect(api.chatReadsMarked, isEmpty);
          expect(api.threadReads, isEmpty);
          expect(publications, 1);
          expect(owner.preventsEviction, isFalse);
        },
      );
    }
  }
}

final class _HeldCredentials extends FakeApiCredentialReader {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    started.complete();
    await release.future;
    return keys[siteUrl];
  }
}

final class _ReadFixture {
  _ReadFixture(
    this.target, {
    ChatReadReceiptRetries? retries,
    this.siteUrl = _site,
  }) : retries = retries ?? ChatReadReceiptRetries() {
    credentials.keys[siteUrl] = 'key';
    requests = FakePluginRequestHost(credentials: credentials);
    owner = _newOwner();
  }

  final ChatStreamTarget target;
  final String siteUrl;
  final ChatReadReceiptRetries retries;
  final credentials = FakeApiCredentialReader();
  final api = _ReadApi();
  late final FakePluginRequestHost requests;
  late ChatReadReceiptOwner owner;
  ChatChannel channel = _channel;
  ChatThread thread = _thread;
  int publications = 0;

  int? get lastRead => target.isThread
      ? thread.membership?.lastReadMessageId
      : channel.membership.lastReadMessageId;

  ChatReadReceiptOwner _newOwner() => ChatReadReceiptOwner(
    siteUrl: siteUrl,
    target: target,
    api: api,
    requests: requests,
    retries: retries,
    clock: DateTime.now,
    isCurrent: () => true,
    publish: (read, at) {
      publications++;
      switch (read) {
        case ChatChannelRead():
          channel = read.project(channel, at)!;
        case ChatThreadRead():
          thread = read.project(thread);
      }
    },
  );

  void replaceOwner() {
    owner.retire();
    owner = _newOwner();
  }

  Future<void> observe(int messageId) {
    final admission = ChatReadReceiptOwner.admit(
      target,
      messageId,
      ChatReadReceiptSnapshot(
        lease: requests.capture(siteUrl),
        channel: channel,
        thread: thread,
        isLocalMessage: false,
        atPresent: true,
        newestMessageId: 3,
      ),
      retryMessageId: retries.pendingMessageId(siteUrl, target),
    );
    return admission == null ? Future.value() : owner.markRead(admission);
  }
}

final class _ReadApi extends FakeDiscourseApi {
  final List<int> threadReads = [];
  final List<int> attempts = [];
  final gates = <int, Completer<void>>{};
  final failures = <int, WriteException>{};
  final started = Completer<void>();
  WriteException? readFailure;

  Future<void> _deliver(int messageId) async {
    attempts.add(messageId);
    if (!started.isCompleted) started.complete();
    await gates[messageId]?.future;
    final error = failures[messageId] ?? readFailure;
    if (error != null) throw error;
  }

  @override
  Future<void> markChatChannelRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    chatReadsMarked.add((channelId: channelId, messageId: messageId));
    await _deliver(messageId);
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
    threadReads.add(messageId);
    await _deliver(messageId);
  }
}
