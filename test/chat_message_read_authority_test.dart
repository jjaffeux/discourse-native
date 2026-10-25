import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_pin.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;
import 'support/fakes.dart';

void main() {
  const user = DiscourseUser(id: 2, username: 'sam');

  test(
    'an old channel read preserves accepted edit content and preview',
    () async {
      final api = _SnapshotApi(fixtures.message(12, raw: 'Original text'));
      final subject = fixtures.build(api: api, currentUser: user);
      addTearDown(subject.chat.dispose);
      await subject.chat.loadChannels(fixtures.site);
      await subject.chat.openChannel(fixtures.site, 9);

      api.snapshot = fixtures.message(12, raw: 'Original text', pinned: true);
      final delayed = api.delayNextRead();
      addTearDown(delayed.complete);
      final refresh = subject.chat.openChannel(fixtures.site, 9, force: true);
      await delayed.started.future;
      expect(
        await subject.chat.editMessage(fixtures.site, 12, 'Accepted new text'),
        isNull,
      );
      expect(api.chatMessagesEdited.single.message, 'Accepted new text');
      expect(subject.chat.message(fixtures.site, 12)?.raw, 'Accepted new text');
      delayed.release.complete();
      await refresh;

      final message = subject.chat.message(fixtures.site, 12)!;
      expect(message.raw, 'Accepted new text');
      expect(message.canonicalReceived, isFalse);
      expect(message.pinned, isTrue);
      expect(
        subject.chat.channel(fixtures.site, 9)?.lastMessagePreview,
        'Accepted new text',
      );

      api.snapshot = fixtures.message(12, raw: 'Later server text');
      await subject.chat.openChannel(fixtures.site, 9, force: true);
      expect(subject.chat.message(fixtures.site, 12)?.raw, 'Later server text');
      expect(
        subject.chat.message(fixtures.site, 12)?.canonicalReceived,
        isTrue,
      );
    },
  );

  test('an old channel read cannot resurrect an accepted deletion', () async {
    final api = _SnapshotApi(fixtures.message(12, raw: 'Original text'));
    final subject = fixtures.build(api: api, currentUser: user);
    addTearDown(subject.chat.dispose);
    await subject.chat.loadChannels(fixtures.site);
    await subject.chat.openChannel(fixtures.site, 9);

    final delayed = api.delayNextRead();
    addTearDown(delayed.complete);
    final refresh = subject.chat.openChannel(fixtures.site, 9, force: true);
    await delayed.started.future;
    expect(await subject.chat.deleteMessage(fixtures.site, 12), isNull);
    expect(api.chatMessagesDeleted, [(channelId: 9, messageId: 12)]);
    expect(subject.chat.message(fixtures.site, 12)?.isDeleted, isTrue);
    delayed.release.complete();
    await refresh;
    expect(subject.chat.message(fixtures.site, 12)?.isDeleted, isTrue);
    expect(subject.chat.message(fixtures.site, 12)?.deletedById, user.id);

    await subject.chat.openChannel(fixtures.site, 9, force: true);
    expect(subject.chat.message(fixtures.site, 12)?.isDeleted, isFalse);
  });

  test('an old channel read cannot undo an accepted restore', () async {
    final api = _SnapshotApi(
      fixtures.message(
        12,
        raw: 'Original text',
        deletedAt: DateTime.utc(2026, 10, 24),
        deletedById: user.id,
      ),
    );
    final subject = fixtures.build(api: api, currentUser: user);
    addTearDown(subject.chat.dispose);
    await subject.chat.loadChannels(fixtures.site);
    await subject.chat.openChannel(fixtures.site, 9);

    final delayed = api.delayNextRead();
    addTearDown(delayed.complete);
    final refresh = subject.chat.openChannel(fixtures.site, 9, force: true);
    await delayed.started.future;
    expect(await subject.chat.restoreMessage(fixtures.site, 12), isNull);
    expect(api.chatMessagesRestored, [(channelId: 9, messageId: 12)]);
    delayed.release.complete();
    await refresh;
    expect(subject.chat.message(fixtures.site, 12)?.isDeleted, isFalse);
    expect(subject.chat.message(fixtures.site, 12)?.deletedById, isNull);

    await subject.chat.openChannel(fixtures.site, 9, force: true);
    expect(subject.chat.message(fixtures.site, 12)?.isDeleted, isTrue);
  });

  test('an old channel read preserves accepted bulk deletion', () async {
    final api = _SnapshotApi(fixtures.message(12, raw: 'Original text'));
    final subject = fixtures.build(api: api, currentUser: user);
    addTearDown(subject.chat.dispose);
    await subject.chat.loadChannels(fixtures.site);
    await subject.chat.openChannel(fixtures.site, 9);

    final delayed = api.delayNextRead();
    addTearDown(delayed.complete);
    final refresh = subject.chat.openChannel(fixtures.site, 9, force: true);
    await delayed.started.future;
    expect(await subject.chat.deleteMessages(fixtures.site, 9, [12]), isNull);
    expect(api.chatMessageBatchesDeleted.single.messageIds, [12]);
    delayed.release.complete();
    await refresh;
    expect(subject.chat.message(fixtures.site, 12)?.isDeleted, isTrue);
  });

  for (final refused in [false, true]) {
    test(
      'a read during a pending edit preserves content until ${refused ? 'rollback' : 'acceptance'}',
      () async {
        final editGate = Completer<void>();
        addTearDown(() {
          if (!editGate.isCompleted) editGate.complete();
        });
        final api = _SnapshotApi(
          fixtures.message(12, raw: 'Original text'),
          editGate: editGate,
          editFailure: refused
              ? const WriteException(WriteFailure.forbidden)
              : null,
        );
        final subject = fixtures.build(api: api, currentUser: user);
        addTearDown(subject.chat.dispose);
        await subject.chat.loadChannels(fixtures.site);
        await subject.chat.openChannel(fixtures.site, 9);

        final edit = subject.chat.editMessage(
          fixtures.site,
          12,
          'Pending text',
        );
        await api.editStarted.future;
        api.snapshot = fixtures.message(12, raw: 'Original text', pinned: true);
        await subject.chat.openChannel(fixtures.site, 9, force: true);
        expect(subject.chat.message(fixtures.site, 12)?.raw, 'Pending text');
        expect(
          subject.chat.message(fixtures.site, 12)?.canonicalReceived,
          isFalse,
        );
        editGate.complete();
        expect(await edit, refused ? isNotNull : isNull);
        expect(
          subject.chat.message(fixtures.site, 12)?.raw,
          refused ? 'Original text' : 'Pending text',
        );
        expect(subject.chat.message(fixtures.site, 12)?.pinned, isTrue);
      },
    );
  }

  for (final older in [true, false]) {
    test(
      'an old ${older ? 'older' : 'newer'} page preserves an accepted edit from another retained message read',
      () async {
        final api = _SnapshotApi(fixtures.message(older ? 14 : 10))
          ..canLoadMorePast = older
          ..canLoadMoreFuture = !older;
        final subject = fixtures.build(api: api, currentUser: user);
        addTearDown(subject.chat.dispose);
        await subject.chat.loadChannels(fixtures.site);
        await subject.chat.openChannel(fixtures.site, 9);

        api.snapshot = fixtures.message(12, raw: 'Original text');
        final delayed = api.delayNextRead();
        addTearDown(delayed.complete);
        final load = older
            ? subject.chat.loadOlder(fixtures.site, 9)
            : subject.chat.loadNewer(fixtures.site, 9);
        await delayed.started.future;
        await subject.chat.resolveBookmarkMessage(
          fixtures.site,
          ChatLink(route: ChatRoute.channel(9), messageId: 12),
        );
        expect(subject.chat.message(fixtures.site, 12)?.raw, 'Original text');
        expect(
          await subject.chat.editMessage(
            fixtures.site,
            12,
            'Accepted page text',
          ),
          isNull,
        );
        delayed.complete();
        await load;
        expect(
          subject.chat.message(fixtures.site, 12)?.raw,
          'Accepted page text',
        );
        expect(subject.chat.stream(fixtures.site, 9).messageIds, contains(12));
      },
    );
  }

  test('an old thread window preserves an accepted edit', () async {
    final api = _SnapshotApi(fixtures.threadRoot());
    final subject = fixtures.build(api: api, currentUser: user);
    addTearDown(subject.chat.dispose);
    const target = ChatThreadTarget(channelId: 9, threadId: 3);
    await subject.chat.loadChannels(fixtures.site);
    await subject.chat.openThread(fixtures.site, target);
    expect(subject.chat.message(fixtures.site, 1)?.raw, '1');

    final delayed = api.delayNextRead();
    addTearDown(delayed.complete);
    final refresh = subject.chat.openThread(fixtures.site, target, force: true);
    await delayed.started.future;
    expect(
      await subject.chat.editMessage(fixtures.site, 1, 'Accepted thread text'),
      isNull,
    );
    delayed.complete();
    await refresh;
    expect(subject.chat.message(fixtures.site, 1)?.raw, 'Accepted thread text');
  });

  test('an old pinned-message read preserves an accepted edit', () async {
    final api = _SnapshotApi(fixtures.message(12, raw: 'Original text'));
    final subject = fixtures.build(api: api, currentUser: user);
    addTearDown(subject.chat.dispose);
    await subject.chat.loadChannels(fixtures.site);
    await subject.chat.openChannel(fixtures.site, 9);

    final delayed = api.delayNextRead();
    addTearDown(delayed.complete);
    final load = subject.chat.loadPinnedMessages(fixtures.site, 9);
    await delayed.started.future;
    expect(
      await subject.chat.editMessage(fixtures.site, 12, 'Accepted pin text'),
      isNull,
    );
    delayed.complete();
    await load;
    expect(subject.chat.message(fixtures.site, 12)?.raw, 'Accepted pin text');
    expect(subject.chat.message(fixtures.site, 12)?.pinned, isTrue);
    final acceptedPin = subject.chat
        .pinsListenable(fixtures.site, 9)
        .value
        .pins
        .single;
    expect(
      acceptedPin.excerpt.isEmpty
          ? acceptedPin.message.raw
          : acceptedPin.excerpt,
      'Accepted pin text',
    );
    expect(
      subject.chat
          .pinsListenable(fixtures.site, 9)
          .value
          .pins
          .single
          .message
          .raw,
      'Accepted pin text',
    );
  });

  test('an old bookmark message read preserves an accepted edit', () async {
    final api = _SnapshotApi(fixtures.message(12, raw: 'Original text'));
    final subject = fixtures.build(api: api, currentUser: user);
    addTearDown(subject.chat.dispose);
    await subject.chat.loadChannels(fixtures.site);
    await subject.chat.openChannel(fixtures.site, 9);

    final delayed = api.delayNextRead();
    addTearDown(delayed.complete);
    final load = subject.chat.resolveBookmarkMessage(
      fixtures.site,
      ChatLink(route: ChatRoute.channel(9), messageId: 12),
    );
    await delayed.started.future;
    expect(
      await subject.chat.editMessage(
        fixtures.site,
        12,
        'Accepted bookmark text',
      ),
      isNull,
    );
    delayed.complete();
    final resolved = await load;
    expect(resolved?.raw, 'Accepted bookmark text');
    expect(
      subject.chat.message(fixtures.site, 12)?.raw,
      'Accepted bookmark text',
    );
  });

  for (final detail in [true, false]) {
    test(
      'an old thread ${detail ? 'detail' : 'list'} read preserves accepted root deletion',
      () async {
        final api = _SnapshotApi(fixtures.threadRoot());
        final subject = fixtures.build(api: api, currentUser: user);
        addTearDown(subject.chat.dispose);
        const target = ChatThreadTarget(channelId: 9, threadId: 3);
        await subject.chat.loadChannels(fixtures.site);
        await subject.chat.openChannel(fixtures.site, 9);
        await subject.chat.loadMyThreads(fixtures.site);
        expect(
          subject.chat.thread(fixtures.site, 3)?.originalMessage?.deletedAt,
          isNull,
        );

        final delayed = api.delayNextThreadRead();
        addTearDown(delayed.complete);
        final load = detail
            ? subject.chat.refreshThreadDetail(fixtures.site, target)
            : subject.chat.loadMyThreads(fixtures.site, force: true);
        await delayed.started.future;
        expect(await subject.chat.deleteMessage(fixtures.site, 1), isNull);
        expect(
          subject.chat.thread(fixtures.site, 3)?.originalMessage?.deletedAt,
          isNotNull,
        );
        delayed.complete();
        await load;
        expect(
          subject.chat.thread(fixtures.site, 3)?.originalMessage?.deletedAt,
          isNotNull,
        );

        if (detail) {
          await subject.chat.refreshThreadDetail(fixtures.site, target);
        } else {
          await subject.chat.loadMyThreads(fixtures.site, force: true);
        }
        expect(
          subject.chat.thread(fixtures.site, 3)?.originalMessage?.deletedAt,
          isNull,
        );
      },
    );
  }

  test(
    'a matching canonical HTTP echo settles a pending edit despite a refused response',
    () async {
      final editGate = Completer<void>();
      addTearDown(() {
        if (!editGate.isCompleted) editGate.complete();
      });
      final before = fixtures.message(12, raw: 'Original text');
      final api = _SnapshotApi(
        before,
        editGate: editGate,
        editFailure: const WriteException(WriteFailure.forbidden),
      );
      final subject = fixtures.build(api: api, currentUser: user);
      addTearDown(subject.chat.dispose);
      await subject.chat.loadChannels(fixtures.site);
      await subject.chat.openChannel(fixtures.site, 9);
      const replacement = ChatUpload(
        id: 44,
        url: '/uploads/new.png',
        originalFilename: 'new.png',
        kind: ChatUploadKind.image,
      );

      final edit = subject.chat.editMessage(
        fixtures.site,
        12,
        'Accepted canonical text',
        uploads: const [replacement],
      );
      await api.editStarted.future;
      api.snapshot = ChatMessage(
        id: 12,
        channelId: 9,
        raw: 'Accepted canonical text',
        cooked: '<p>Canonical server cook</p>',
        author: before.author,
        createdAt: before.createdAt,
        uploads: const [replacement],
      );
      await subject.chat.openChannel(fixtures.site, 9, force: true);
      expect(
        subject.chat.message(fixtures.site, 12)?.canonicalReceived,
        isTrue,
      );
      expect(
        subject.chat.message(fixtures.site, 12)?.cooked,
        '<p>Canonical server cook</p>',
      );
      editGate.complete();
      expect(await edit, isNull);
      final settled = subject.chat.message(fixtures.site, 12)!;
      expect(settled.raw, 'Accepted canonical text');
      expect(settled.cooked, '<p>Canonical server cook</p>');
      expect(settled.uploads, const [replacement]);
      expect(settled.canonicalReceived, isTrue);
    },
  );

  test(
    'an old read cannot resurrect a message hidden by an actual live delete',
    () async {
      final api = _SnapshotApi(
        fixtures.message(12, raw: 'Original text'),
        canModerate: false,
      );
      final subject = fixtures.build(
        api: api,
        currentUser: fixtures.currentUser,
      );
      addTearDown(subject.chat.dispose);
      final tracker = fixtures.attachTracker(subject.chat);
      await subject.chat.loadChannels(fixtures.site);
      await subject.chat.openChannel(fixtures.site, 9);
      final view = subject.chat.beginViewingChannel(fixtures.site, 9);
      addTearDown(() => subject.chat.endViewingChannel(fixtures.site, 9, view));

      final delayed = api.delayNextRead();
      addTearDown(delayed.complete);
      final refresh = subject.chat.openChannel(fixtures.site, 9, force: true);
      await delayed.started.future;
      tracker.deliverPluginMessage('/chat/9', {
        'type': 'delete',
        'deleted_id': 12,
        'deleted_at': '2026-10-25T10:00:00.000Z',
      });
      expect(subject.chat.message(fixtures.site, 12), isNull);
      delayed.complete();
      await refresh;
      expect(subject.chat.message(fixtures.site, 12), isNull);
      expect(subject.chat.messages(fixtures.site, 9), isEmpty);
    },
  );

  for (final action in ['delete', 'restore', 'bulk delete']) {
    test(
      'an old read preserves accepted $action after cache eviction',
      () async {
        final mutationGate = Completer<void>();
        addTearDown(() {
          if (!mutationGate.isCompleted) mutationGate.complete();
        });
        final restoring = action == 'restore';
        final original = fixtures.message(
          12,
          raw: 'Original text',
          deletedAt: restoring ? DateTime.utc(2026, 10, 24) : null,
          deletedById: restoring ? user.id : null,
        );
        final api = _SnapshotApi(original, mutationGate: mutationGate);
        final subject = fixtures.build(
          api: api,
          currentUser: user,
          store: Store(
            policy: const StorePolicy(
              maxEntries: 64,
              maxEntriesPerSiteAndType: 1,
            ),
          ),
        );
        addTearDown(subject.chat.dispose);
        await subject.chat.loadChannels(fixtures.site);
        await subject.chat.openChannel(fixtures.site, 9);
        final delayed = api.delayNextRead();
        addTearDown(delayed.complete);
        final refresh = subject.chat.openChannel(fixtures.site, 9, force: true);
        await delayed.started.future;
        final mutation = switch (action) {
          'restore' => subject.chat.restoreMessage(fixtures.site, 12),
          'bulk delete' => subject.chat.deleteMessages(fixtures.site, 9, [12]),
          _ => subject.chat.deleteMessage(fixtures.site, 12),
        };
        await api.mutationStarted.future;
        api.snapshot = fixtures.message(13);
        expect(
          await subject.chat.resolveBookmarkMessage(
            fixtures.site,
            ChatLink(route: ChatRoute.channel(9), messageId: 13),
          ),
          isNotNull,
        );
        expect(subject.chat.message(fixtures.site, 12), isNull);
        mutationGate.complete();
        expect(await mutation, isNull);
        expect(subject.chat.message(fixtures.site, 12), isNull);
        delayed.complete();
        await refresh;
        expect(subject.chat.message(fixtures.site, 12)?.isDeleted, !restoring);
        expect(
          subject.chat.message(fixtures.site, 12)?.deletedById,
          restoring ? isNull : user.id,
        );
      },
    );
  }

  test(
    'an old read cannot revive a refused edit after cache eviction',
    () async {
      final editGate = Completer<void>();
      addTearDown(() {
        if (!editGate.isCompleted) editGate.complete();
      });
      final api = _SnapshotApi(
        fixtures.message(12, raw: 'Original text'),
        editGate: editGate,
        editFailure: const WriteException(WriteFailure.forbidden),
      );
      final subject = fixtures.build(
        api: api,
        currentUser: user,
        store: Store(
          policy: const StorePolicy(
            maxEntries: 64,
            maxEntriesPerSiteAndType: 1,
          ),
        ),
      );
      addTearDown(subject.chat.dispose);
      await subject.chat.loadChannels(fixtures.site);
      await subject.chat.openChannel(fixtures.site, 9);
      final delayed = api.delayNextRead();
      addTearDown(delayed.complete);
      final refresh = subject.chat.openChannel(fixtures.site, 9, force: true);
      await delayed.started.future;
      final edit = subject.chat.editMessage(fixtures.site, 12, 'Refused text');
      await api.editStarted.future;
      api.snapshot = fixtures.message(13);
      await subject.chat.resolveBookmarkMessage(
        fixtures.site,
        ChatLink(route: ChatRoute.channel(9), messageId: 13),
      );
      expect(subject.chat.message(fixtures.site, 12), isNull);
      editGate.complete();
      expect(await edit, isNotNull);
      expect(subject.chat.message(fixtures.site, 12), isNull);
      delayed.complete();
      await refresh;
      expect(subject.chat.message(fixtures.site, 12)?.raw, 'Original text');
    },
  );

  test(
    'a read admitted after pending edit eviction retains its submitted content',
    () async {
      final editGate = Completer<void>();
      addTearDown(() {
        if (!editGate.isCompleted) editGate.complete();
      });
      final original = fixtures.message(12, raw: 'Original text');
      final api = _SnapshotApi(original, editGate: editGate);
      final subject = fixtures.build(
        api: api,
        currentUser: user,
        store: Store(
          policy: const StorePolicy(
            maxEntries: 64,
            maxEntriesPerSiteAndType: 1,
          ),
        ),
      );
      addTearDown(subject.chat.dispose);
      await subject.chat.loadChannels(fixtures.site);
      await subject.chat.openChannel(fixtures.site, 9);
      final edit = subject.chat.editMessage(fixtures.site, 12, 'Accepted text');
      await api.editStarted.future;
      api.snapshot = fixtures.message(13);
      await subject.chat.resolveBookmarkMessage(
        fixtures.site,
        ChatLink(route: ChatRoute.channel(9), messageId: 13),
      );
      expect(subject.chat.message(fixtures.site, 12), isNull);
      api.snapshot = original;
      await subject.chat.openChannel(fixtures.site, 9, force: true);
      expect(subject.chat.message(fixtures.site, 12)?.raw, 'Accepted text');
      expect(
        subject.chat.message(fixtures.site, 12)?.canonicalReceived,
        isFalse,
      );
      editGate.complete();
      expect(await edit, isNull);
    },
  );

  test('a refused edit permits later authoritative content', () async {
    final api = _SnapshotApi(
      fixtures.message(12, raw: 'Original text'),
      editFailure: const WriteException(WriteFailure.forbidden),
    );
    final subject = fixtures.build(api: api, currentUser: user);
    addTearDown(subject.chat.dispose);
    await subject.chat.loadChannels(fixtures.site);
    await subject.chat.openChannel(fixtures.site, 9);

    expect(
      await subject.chat.editMessage(fixtures.site, 12, 'Refused text'),
      isNotNull,
    );
    expect(subject.chat.message(fixtures.site, 12)?.raw, 'Original text');
    api.snapshot = fixtures.message(12, raw: 'Another author accepted text');
    await subject.chat.openChannel(fixtures.site, 9, force: true);
    expect(
      subject.chat.message(fixtures.site, 12)?.raw,
      'Another author accepted text',
    );
  });
}

final class _DelayedRead {
  final started = Completer<void>();
  final release = Completer<void>();

  void complete() {
    if (!release.isCompleted) release.complete();
  }
}

final class _SnapshotApi extends FakeDiscourseApi {
  _SnapshotApi(
    this.snapshot, {
    WriteException? editFailure,
    Completer<void>? editGate,
    Completer<void>? mutationGate,
    bool canModerate = true,
  }) : super(
         chatEditFailure: editFailure,
         chatEditGate: editGate,
         chatMessageMutationGate: mutationGate,
         chatChannelsBySite: {
           fixtures.site: ChatChannels(
             public: [
               fixtures.channel(
                 9,
                 canDeleteSelf: true,
                 canModerate: canModerate,
                 lastMessageId: 12,
               ),
             ],
           ),
         },
       );

  ChatMessage snapshot;
  bool canLoadMorePast = false;
  bool canLoadMoreFuture = false;
  final editStarted = Completer<void>();
  final mutationStarted = Completer<void>();
  _DelayedRead? _nextRead;
  _DelayedRead? _nextThreadRead;

  _DelayedRead delayNextRead() => _nextRead = _DelayedRead();

  _DelayedRead delayNextThreadRead() => _nextThreadRead = _DelayedRead();

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
    final response = fixtures.page(
      [snapshot],
      canLoadMorePast: canLoadMorePast,
      canLoadMoreFuture: canLoadMoreFuture,
    );
    final delayed = _nextRead;
    _nextRead = null;
    if (delayed != null) {
      delayed.started.complete();
      await delayed.release.future;
    }
    return response;
  }

  @override
  Future<void> editChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String message,
    List<int> uploadIds = const [],
    String? clientId,
  }) {
    if (!editStarted.isCompleted) editStarted.complete();
    return super.editChatMessage(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      messageId: messageId,
      message: message,
      uploadIds: uploadIds,
      clientId: clientId,
    );
  }

  @override
  Future<void> deleteChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) {
    if (!mutationStarted.isCompleted) mutationStarted.complete();
    return super.deleteChatMessage(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      messageId: messageId,
      clientId: clientId,
    );
  }

  @override
  Future<void> restoreChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) {
    if (!mutationStarted.isCompleted) mutationStarted.complete();
    return super.restoreChatMessage(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      messageId: messageId,
      clientId: clientId,
    );
  }

  @override
  Future<void> deleteChatMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required List<int> messageIds,
    String? clientId,
  }) {
    if (!mutationStarted.isCompleted) mutationStarted.complete();
    return super.deleteChatMessages(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      messageIds: messageIds,
      clientId: clientId,
    );
  }

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) => _readThread();

  @override
  Future<ChatThreadPage> chatThreads({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) async => ChatThreadPage(threads: [await _readThread()]);

  Future<ChatThread> _readThread() async {
    final response = ChatThread(
      id: 3,
      channelId: 9,
      status: 'open',
      replyCount: 1,
      originalMessage: ChatThreadOriginalMessage(
        id: snapshot.id,
        channelId: snapshot.channelId,
        author: snapshot.author,
        message: snapshot.raw,
        cooked: snapshot.cooked,
        deletedAt: snapshot.deletedAt,
      ),
    );
    final delayed = _nextThreadRead;
    _nextThreadRead = null;
    if (delayed != null) {
      delayed.started.complete();
      await delayed.release.future;
    }
    return response;
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
  }) => chatMessages(
    siteUrl: siteUrl,
    channelId: channelId,
    before: before,
    after: after,
    targetMessageId: targetMessageId,
    pageSize: pageSize,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<ChatPins> chatPinnedMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    final page = await chatMessages(
      siteUrl: siteUrl,
      channelId: channelId,
      apiKey: apiKey,
      clientId: clientId,
    );
    final message = page.messages.single;
    return (
      pins: [
        ChatPin(
          id: 1,
          messageId: message.id,
          message: message.withPinned(true),
          pinnedBy: message.author,
          excerpt: message.raw,
        ),
      ],
      membership: null,
    );
  }
}
