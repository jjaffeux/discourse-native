import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';

void main() {
  group('chatInboxActivityAt', () {
    for (final kind in ['Category', 'DirectMessage']) {
      for (final messageId in [null, 0]) {
        test('ignores a $kind placeholder with message ID $messageId', () {
          final channel = ChatChannel.fromJson({
            'id': 9,
            'title': 'Empty conversation',
            'chatable_type': kind,
            'last_message': {
              'id': messageId,
              'created_at': '2026-09-27T09:28:00.000Z',
            },
          }, _site);

          expect(chatInboxActivityAt(channel), isNull);
        });
      }
    }

    test('uses the timestamp of a real message', () {
      final channel = ChatChannel.fromJson(const {
        'id': 9,
        'title': 'General',
        'chatable_type': 'Category',
        'last_message': {'id': 50, 'created_at': '2026-09-27T09:13:00.000Z'},
      }, _site);

      expect(chatInboxActivityAt(channel), DateTime.utc(2026, 9, 27, 9, 13));
    });

    test('does not invent activity when the timestamp is missing', () {
      const channel = ChatChannel(
        id: 9,
        title: 'General',
        kind: ChatChannelKind.category,
        lastMessageId: 50,
      );

      expect(chatInboxActivityAt(channel), isNull);
    });

    test('uses real thread activity instead of a placeholder timestamp', () {
      final threadAt = DateTime.utc(2026, 9, 26);
      final channel = ChatChannel(
        id: 9,
        title: 'General',
        kind: ChatChannelKind.category,
        lastMessageAt: DateTime.utc(2026, 9, 27),
        unreadThreadOverview: {10: threadAt},
      );

      expect(chatInboxActivityAt(channel), threadAt);
    });

    test('uses the newest message or unread thread timestamp', () {
      final latest = DateTime.utc(2026, 9, 27);
      final older = DateTime.utc(2026, 9, 26);
      for (final messageIsNewest in [false, true]) {
        final channel = ChatChannel(
          id: 9,
          title: 'General',
          kind: ChatChannelKind.category,
          lastMessageId: 50,
          lastMessageAt: messageIsNewest ? latest : older,
          unreadThreadOverview: {
            10: messageIsNewest ? older : latest,
            11: DateTime.utc(2026, 9, 25),
          },
        );

        expect(chatInboxActivityAt(channel), latest);
      }
    });
  });
}
