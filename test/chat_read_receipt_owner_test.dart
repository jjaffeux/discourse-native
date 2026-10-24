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
        expect(
          ChatReadReceiptOwner.admit(target, -1, _snapshot(lease)),
          isNull,
        );
        expect(ChatReadReceiptOwner.admit(target, 1, _snapshot(lease)), isNull);
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

final class _ReadApi extends FakeDiscourseApi {
  final List<int> threadReads = [];

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
  }
}
