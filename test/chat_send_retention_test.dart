import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;

void main() {
  for (final failFirst in [false, true]) {
    test(
      'a send keeps its canonical owner under reader pressure, failure=$failFirst',
      () async {
        final gate = Completer<void>();
        final subject = fixtures.build(
          currentUser: const DiscourseUser(id: 7, username: 'reader'),
          channels: {
            fixtures.site: ChatChannels(public: [fixtures.channel(9)]),
          },
          messages: {
            '9': fixtures.page([fixtures.message(100)]),
          },
          sendGate: gate,
          sendFailure: failFirst
              ? const WriteException(WriteFailure.unreachable, notSent: true)
              : null,
          sentMessageId: 101,
          maxRetainedCanonicalMessageIdsPerSite: 50,
        );
        addTearDown(subject.chat.dispose);
        await subject.chat.loadChannels(fixtures.site);
        const target = ChatChannelTarget(9);
        final reader = subject.chat.acquireReader(
          fixtures.site,
          target,
          readerId: 'tab',
        );
        addTearDown(reader.dispose);
        reader.beginViewing();
        await reader.open();
        final send = subject.chat.sendMessage(
          fixtures.site,
          9,
          OutgoingChatMessage.text('Hello'),
        )!;
        expect(subject.chat.hasSendingMessage(fixtures.site, target), isTrue);
        expect(reader.stream.localMessageIds, [send.localId]);
        gate.complete();
        await send.settled;
        if (failFirst) {
          expect(
            subject.store
                .read<ChatMessage>(fixtures.site, send.localId)
                ?.delivery,
            ChatMessageDelivery.failed,
          );
          subject.api.chatSendFailure = null;
          final retry = subject.chat.retryMessage(
            fixtures.site,
            target,
            send.stagedId,
          );
          expect(retry, isNotNull);
          await retry!.settled;
          expect(subject.api.chatMessagesSent, hasLength(2));
        } else {
          expect(subject.api.chatMessagesSent, hasLength(1));
        }
        final stored = subject.store.read<ChatMessage>(
          fixtures.site,
          send.localId,
        );
        expect(stored?.delivery, ChatMessageDelivery.sent);
        expect(stored?.serverId, 101);
        expect(subject.chat.hasSendingMessage(fixtures.site, target), isFalse);
      },
    );
  }
}
