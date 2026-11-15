import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/live_channels.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/write_failure.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_send_coordinator.dart';
import 'package:discourse_native/src/plugins/chat/chat_send_outbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;
import 'support/fakes.dart';

const _site = fixtures.site;
const _offline = WriteException(WriteFailure.unreachable, notSent: true);
const _target = ChatChannelTarget(9);

final class _LiveChannels implements PluginLiveChannelHandle {
  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) => _Subscription();
}

final class _Subscription implements PluginLiveChannelSubscription {
  @override
  void cancel() {}
}

/// One launch of the app over the file every launch shares.
final class _Launch {
  _Launch(
    this.file, {
    WriteException? sendFailure,
    DiscourseUser? user = const DiscourseUser(id: 7, username: 'Reader'),
    DateTime Function()? clock,
  }) : api = FakeDiscourseApi(
         chatChannelsBySite: {
           _site: ChatChannels(public: [fixtures.channel(9)]),
         },
         chatMessagesByKey: {
           '9': fixtures.page([fixtures.message(100)]),
         },
         chatSendFailure: sendFailure,
         chatSentMessageId: 101,
       ) {
    outbox = createChatSendOutbox(
      () => storageFails ? throw const FileSystemException('full') : file,
    );
    final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
    chat = ChatController(
      api: api,
      requests: FakePluginRequestHost(
        credentials: credentials,
        lifecycle: lifecycle,
      ),
      store: store,
      currentUserFor: (_) => user,
      sendOutbox: outbox,
      clock: clock,
    );
  }

  final File file;
  final FakeDiscourseApi api;
  bool storageFails = false;
  late final ChatSendOutbox outbox;
  final lifecycle = SiteLifecycle();
  final store = Store();
  late final ChatController chat;

  Future<void> settled() async {
    for (var round = 0; round < 3; round++) {
      await outbox.sites();
      await pumpEventQueue();
    }
  }

  /// What the live session's start does on every launch.
  Future<void> start() async {
    chat.attachTracker(_site, _LiveChannels());
    await settled();
  }

  List<ChatMessage> get shown => chat.messagesFor(_site, _target);

  Future<List<Object?>> held() async {
    await settled();
    if (!await file.exists()) return const [];
    final document = jsonDecode(await file.readAsString()) as Map;
    final section = (document['sites'] as Map)[_site];
    return section is Map ? section['entries'] as List<Object?> : const [];
  }
}

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-send-outbox-');
    file = File('${directory.path}/failed-sends.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  _Launch launch({
    WriteException? sendFailure,
    DiscourseUser? user = const DiscourseUser(id: 7, username: 'Reader'),
    DateTime Function()? clock,
  }) {
    final launched = _Launch(
      file,
      sendFailure: sendFailure,
      user: user,
      clock: clock,
    );
    addTearDown(launched.chat.dispose);
    return launched;
  }

  /// Leaves one message that never reached the site, then ends the launch.
  Future<String> leaveFailedMessage({
    OutgoingChatMessage? message,
    DateTime Function()? clock,
  }) async {
    final first = launch(sendFailure: _offline, clock: clock);
    await first.start();
    final send = first.chat.sendMessage(
      _site,
      9,
      message ?? OutgoingChatMessage.text('Hello after a tunnel'),
    )!;
    expect(await send.settled, ChatSendResult.failed);
    await first.settled();
    first.chat.dispose();
    return send.stagedId;
  }

  test('a failed message returns after a restart with its retry and is '
      'not sent by itself', () async {
    final stagedId = await leaveFailedMessage();

    final second = launch();
    await second.start();
    final restored = second.shown.single;
    expect(restored.stagedId, stagedId);
    expect(restored.raw, 'Hello after a tunnel');
    expect(restored.delivery, ChatMessageDelivery.failed);
    expect(restored.sendRetryable, isTrue);
    expect(restored.retryWaiting, isFalse);
    expect(restored.author.username, 'Reader');

    await second.chat.loadChannels(_site);
    await second.start();
    await second.settled();
    expect(second.shown, hasLength(1), reason: 'restored once per session');
    expect(second.api.chatMessagesSent, isEmpty);
  });

  test('a restored message is sent once, by its retry', () async {
    final stagedId = await leaveFailedMessage();
    final second = launch();
    await second.start();

    final retry = second.chat.retryMessage(_site, _target, stagedId)!;
    expect(second.chat.retryMessage(_site, _target, stagedId), isNull);
    expect(await retry.settled, ChatSendResult.sent);
    expect(second.chat.retryMessage(_site, _target, stagedId), isNull);

    expect(second.api.chatMessagesSent.map((sent) => sent.stagedId), [
      stagedId,
    ]);
    expect(second.api.chatMessagesSent.single.message, 'Hello after a tunnel');
    expect(await second.held(), isEmpty);

    final third = launch();
    await third.start();
    expect(third.shown, isEmpty);
    expect(third.api.chatMessagesSent, isEmpty);
  });

  test('a retry that fails again is kept for the next launch', () async {
    final stagedId = await leaveFailedMessage();
    final second = launch(sendFailure: _offline);
    await second.start();

    final retry = second.chat.retryMessage(_site, _target, stagedId)!;
    expect(await retry.settled, ChatSendResult.failed);
    expect(await second.held(), hasLength(1));
  });

  test(
    'a retry is not sent while the outbox still holds the message',
    () async {
      final stagedId = await leaveFailedMessage();
      final second = launch();
      await second.start();
      second.storageFails = true;

      final retry = second.chat.retryMessage(_site, _target, stagedId)!;
      expect(await retry.settled, ChatSendResult.failed);

      expect(second.api.chatMessagesSent, isEmpty);
      expect(second.shown.single.sendRetryable, isTrue);
    },
  );

  test('the retry sends the message as it was written', () async {
    final createdAt = DateTime.utc(2026, 11, 15, 9, 30, 0, 123, 456);
    final stagedId = await leaveFailedMessage(
      clock: () => createdAt,
      message: OutgoingChatMessage.text(
        '  with a file\n',
        uploads: const [
          ComposerUploadResult(
            id: 41,
            originalFilename: 'photo.png',
            shortUrl: 'upload://photo.png',
            url: '/uploads/photo.png',
            width: 800,
            height: 600,
            thumbnailUrl: '/uploads/photo_thumb.png',
          ),
        ],
        replyTo: const ChatReplyTo(
          id: 100,
          userId: 2,
          excerpt: 'earlier',
          username: 'sam',
        ),
      ),
    );

    final second = launch(clock: () => createdAt);
    await second.start();
    final restored = second.shown.single;
    expect(restored.uploads.single.url, '/uploads/photo.png');
    expect(restored.uploads.single.kind, ChatUploadKind.image);
    expect(restored.replyTo?.excerpt, 'earlier');
    await second.chat.retryMessage(_site, _target, stagedId)!.settled;

    final sent = second.api.chatMessagesSent.single;
    expect(sent.message, '  with a file\n');
    expect(sent.uploadIds, [41]);
    expect(sent.inReplyToId, 100);
    expect(sent.clientCreatedAt, createdAt);
    expect(sent.stagedId, stagedId);
  });

  test('a send that may have reached the site is not kept', () async {
    final first = launch(
      sendFailure: const WriteException(WriteFailure.unreachable),
    );
    await first.start();
    final send = first.chat.sendMessage(
      _site,
      9,
      OutgoingChatMessage.text('maybe delivered'),
    )!;
    expect(await send.settled, ChatSendResult.failed);

    expect(await first.held(), isEmpty);
  });

  test('sign-out or site removal drops the failed messages', () async {
    await leaveFailedMessage();
    final second = launch();
    await second.start();
    expect(second.shown, hasLength(1));

    second.chat.forget(_site);
    await second.settled();

    expect(second.shown, isEmpty);
    expect(await second.outbox.sites(), isEmpty);
    final third = launch();
    await third.start();
    expect(third.shown, isEmpty);
  });

  test("another account's failed messages are dropped, not shown", () async {
    await leaveFailedMessage();

    final second = launch(
      user: const DiscourseUser(id: 8, username: 'someone-else'),
    );
    await second.start();

    expect(second.shown, isEmpty);
    expect(await second.outbox.sites(), isEmpty);
  });

  test('a restore that outlives its account stages nothing', () async {
    await leaveFailedMessage();
    final second = launch();

    second.chat.attachTracker(_site, _LiveChannels());
    second.lifecycle.invalidate(_site);
    await second.settled();

    expect(second.shown, isEmpty);
  });

  test('a message sent before the restore lands does not replace it', () async {
    final stagedId = await leaveFailedMessage();
    final second = launch(sendFailure: _offline);

    final send = second.chat.sendMessage(
      _site,
      9,
      OutgoingChatMessage.text('second failure'),
    )!;
    expect(await send.settled, ChatSendResult.failed);

    expect(
      (await second.held()).map((entry) => (entry! as Map)['staged_id']),
      unorderedEquals([stagedId, send.stagedId]),
    );
  });

  test('a message past its retention is let go', () async {
    var now = DateTime.utc(2026, 11, 1);
    await leaveFailedMessage(clock: () => now);

    now = now.add(
      DefaultChatSendCoordinator.failedSendRetention +
          const Duration(minutes: 1),
    );
    final second = launch(clock: () => now);
    await second.start();

    expect(second.shown, isEmpty);
    expect(await second.held(), isEmpty);
  });

  group('FailedChatSend', () {
    final send = FailedChatSend(
      stagedId: 'native-1-0',
      target: const ChatThreadTarget(channelId: 9, threadId: 12),
      raw: 'thread reply',
      createdAt: DateTime.utc(2026, 11, 15, 9),
      failedAt: DateTime.utc(2026, 11, 15, 9, 0, 5),
      rateLimited: true,
      contextTopicId: 10,
      contextPostIds: const [20, 21],
    );

    test('survives its own encoding', () {
      final decoded = FailedChatSend.fromJson(
        jsonDecode(jsonEncode(send.toJson())),
      )!;

      expect(decoded.toJson(), send.toJson());
      expect(decoded.target, send.target);
      expect(decoded.rateLimited, isTrue);
    });

    test('answers null for an entry it cannot send as written', () {
      Object? without(String key) => send.toJson()..remove(key);
      Object? withValue(String key, Object? value) =>
          send.toJson()..[key] = value;

      for (final entry in [
        null,
        'text',
        <Object?>[],
        without('staged_id'),
        without('channel_id'),
        without('raw'),
        without('created_at'),
        without('failed_at'),
        withValue('staged_id', ''),
        withValue('channel_id', 0),
        withValue('thread_id', 'twelve'),
        withValue('raw', '   '),
        withValue('raw', 'x' * (ChatMessage.maximumEditLength + 1)),
        withValue('uploads', [
          {'id': 'forty-one'},
        ]),
      ]) {
        expect(FailedChatSend.fromJson(entry), isNull, reason: '$entry');
      }
    });

    test('a site keeps its newest failed messages', () {
      final bounded = boundFailedChatSends([
        for (var index = 0; index < maximumFailedChatSends + 3; index++)
          FailedChatSend(
            stagedId: 'native-$index',
            target: const ChatChannelTarget(9),
            raw: '$index',
            createdAt: DateTime.utc(2026),
            failedAt: DateTime.utc(2026),
            rateLimited: false,
          ),
      ]);

      expect(bounded, hasLength(maximumFailedChatSends));
      expect(bounded.first.stagedId, 'native-3');
    });
  });
}
