import 'dart:async';

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_metadata_owner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _target = ChatThreadTarget(channelId: 9, threadId: 22);
const _user = DiscourseUser(id: 7, username: 'author');

ChatThread _detail(String title) => ChatThread(
  id: 22,
  channelId: 9,
  status: 'open',
  replyCount: 2,
  title: title,
  membership: const ChatThreadMembership(
    threadId: 22,
    notificationLevel: ChatThreadNotificationLevel.tracking,
    lastReadMessageId: 17,
  ),
  originalMessage: const ChatThreadOriginalMessage(
    id: 100,
    channelId: 9,
    author: ChatMessageAuthor(id: 7, username: 'author'),
  ),
);

final class _MetadataApi extends FakeDiscourseApi {
  final details = <Completer<ChatThread>>[];
  final notificationResponses = <Completer<ChatThreadMembership>>[];

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) {
    final response = Completer<ChatThread>();
    details.add(response);
    return response.future;
  }

  @override
  Future<ChatThreadMembership> updateChatThreadNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required ChatThreadNotificationLevel notificationLevel,
    String? clientId,
  }) {
    final response = Completer<ChatThreadMembership>();
    notificationResponses.add(response);
    return response.future;
  }
}

final class _MetadataEvents implements ChatThreadMetadataEvents {
  final loading = <ChatThreadTarget>[];
  final stored = <ChatThread>[];
  final failures = <bool>[];
  final subscriptions = <ChatThreadTarget>[];
  final created = <ChatThread>[];
  final changes = <({ChatThread before, ChatThread after})>[];
  final storedTitles = <int>[];

  @override
  void detailLoading(String siteUrl, ChatThreadTarget target) {
    loading.add(target);
  }

  @override
  void detailStored(
    String siteUrl,
    ChatThreadTarget target,
    ChatThread detail,
  ) {
    stored.add(detail);
  }

  @override
  void detailFailed(
    String siteUrl,
    ChatThreadTarget target, {
    required bool terminal,
  }) {
    failures.add(terminal);
  }

  @override
  void ensureThreadSubscription(String siteUrl, ChatThreadTarget target) {
    subscriptions.add(target);
  }

  @override
  void threadCreated(String siteUrl, ChatThread detail, int originalMessageId) {
    created.add(detail);
  }

  void threadTitleStored(String siteUrl, int threadId) {
    storedTitles.add(threadId);
  }

  @override
  void threadChanged(String siteUrl, ChatThread before, ChatThread after) {
    changes.add((before: before, after: after));
  }
}

({ChatThreadMetadataOwner owner, Store store, _MetadataEvents events})
_ownerFor(_MetadataApi api, {ChatThread? held}) {
  final store = Store();
  if (held != null) store.put(_site, held);
  final events = _MetadataEvents();
  final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
  final owner = ChatThreadMetadataOwner(
    api: api,
    requests: FakePluginRequestHost(credentials: credentials),
    store: store,
    currentUserFor: (_) => _user,
    channelFor: (_, _) => null,
    events: events,
  );
  addTearDown(owner.dispose);
  return (owner: owner, store: store, events: events);
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true.');
}

void main() {
  test(
    'coalesced detail retains its target until the final response',
    () async {
      final api = _MetadataApi();
      final subject = _ownerFor(api, held: _detail('Held'));
      expect(subject.owner.preventsEviction(_site, _target), isFalse);

      final first = subject.owner.refreshThreadDetail(_site, _target);
      await _waitUntil(() => api.details.length == 1);
      final joined = subject.owner.refreshThreadDetail(_site, _target);
      expect(identical(joined, first), isTrue);
      expect(subject.owner.preventsEviction(_site, _target), isTrue);
      api.details[0].complete(_detail('Superseded'));
      await _waitUntil(() => api.details.length == 2);

      expect(subject.store.read<ChatThread>(_site, 22)?.title, 'Held');
      expect(subject.events.stored, isEmpty);
      expect(subject.owner.preventsEviction(_site, _target), isTrue);
      api.details[1].complete(_detail('Current'));

      expect((await first)?.title, 'Current');
      expect((await joined)?.title, 'Current');
      expect(subject.store.read<ChatThread>(_site, 22)?.title, 'Current');
      expect(subject.owner.preventsEviction(_site, _target), isFalse);
      expect(subject.events.loading, [_target]);
      expect(subject.events.stored.single.title, 'Current');
      expect(subject.events.storedTitles, [22]);
      expect(subject.events.changes, isEmpty);
      expect(subject.events.subscriptions, [_target]);
      expect(subject.events.failures, isEmpty);
    },
  );

  test(
    'a successful title retains dirty metadata until detail refresh',
    () async {
      final api = _MetadataApi();
      final subject = _ownerFor(api, held: _detail('Before'));

      expect(
        await subject.owner.updateThreadTitle(_site, _target, 'After'),
        isTrue,
      );
      expect(subject.store.read<ChatThread>(_site, 22)?.title, 'After');
      expect(subject.events.storedTitles, [22]);
      expect(subject.owner.preventsEviction(_site, _target), isTrue);
      expect(api.chatThreadTitlesUpdated, [
        (channelId: 9, threadId: 22, title: 'After'),
      ]);

      final refreshed = subject.owner.refreshThreadDetail(_site, _target);
      await _waitUntil(() => api.details.length == 1);
      expect(subject.owner.preventsEviction(_site, _target), isTrue);
      api.details.single.complete(_detail('After'));

      expect((await refreshed)?.title, 'After');
      expect(subject.owner.preventsEviction(_site, _target), isFalse);
      expect(subject.events.stored.single.title, 'After');
      expect(subject.events.storedTitles, [22]);
    },
  );

  test(
    'accepted same-value title writes still publish title authority',
    () async {
      final api = _MetadataApi();
      final subject = _ownerFor(api, held: _detail('Before'));

      expect(
        await subject.owner.updateThreadTitle(_site, _target, 'Before'),
        isTrue,
      );
      expect(
        await subject.owner.updateThreadTitle(_site, _target, 'Before'),
        isTrue,
      );

      expect(subject.events.storedTitles, [22, 22]);
      expect(subject.events.changes, isEmpty);
    },
  );

  test(
    'first null detail title publishes authority without personal changes',
    () async {
      final api = _MetadataApi();
      final subject = _ownerFor(api);
      final refreshing = subject.owner.refreshThreadDetail(_site, _target);
      await _waitUntil(() => api.details.length == 1);
      api.details.single.complete(_detail('Before').copyWith(clearTitle: true));

      expect((await refreshing)?.title, isNull);
      expect(subject.events.storedTitles, [22]);
      expect(subject.events.changes, isEmpty);
    },
  );

  test(
    'revoking a channel abandons detail and rejects its late response',
    () async {
      final api = _MetadataApi();
      final subject = _ownerFor(api, held: _detail('Held'));

      final refreshing = subject.owner.refreshThreadDetail(_site, _target);
      await _waitUntil(() => api.details.length == 1);
      expect(subject.owner.preventsEviction(_site, _target), isTrue);
      subject.owner.revokeChannel(_site, 9);
      expect(subject.owner.preventsEviction(_site, _target), isFalse);
      api.details.single.complete(_detail('Revoked response'));

      expect(await refreshing, isNull);
      expect(subject.store.read<ChatThread>(_site, 22)?.title, 'Held');
      expect(subject.events.stored, isEmpty);
      expect(subject.events.storedTitles, isEmpty);
      expect(subject.events.subscriptions, isEmpty);
      expect(subject.events.failures, isEmpty);
      expect(subject.owner.preventsEviction(_site, _target), isFalse);
    },
  );

  test(
    'a notification queue retains metadata until its write settles',
    () async {
      final api = _MetadataApi();
      final subject = _ownerFor(api, held: _detail('Held'));

      final updating = subject.owner.updateThreadNotificationLevel(
        _site,
        _target,
        ChatThreadNotificationLevel.watching,
      );
      expect(subject.owner.preventsEviction(_site, _target), isTrue);
      expect(
        subject.store
            .read<ChatThread>(_site, 22)
            ?.membership
            ?.notificationLevel,
        ChatThreadNotificationLevel.watching,
      );
      await _waitUntil(() => api.notificationResponses.length == 1);
      api.notificationResponses.single.complete(
        const ChatThreadMembership(
          threadId: 22,
          notificationLevel: ChatThreadNotificationLevel.watching,
          lastReadMessageId: 17,
        ),
      );

      expect(await updating, isTrue);
      await _waitUntil(() => !subject.owner.preventsEviction(_site, _target));
      expect(
        subject.store
            .read<ChatThread>(_site, 22)
            ?.membership
            ?.notificationLevel,
        ChatThreadNotificationLevel.watching,
      );
      expect(subject.events.changes, hasLength(2));
      expect(subject.events.stored, isEmpty);
    },
  );
}
