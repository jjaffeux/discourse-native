import 'package:discourse_native/src/plugins/chat/chat_pin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads pinned message, actor, excerpt, and membership snapshot', () {
    final snapshot = ChatPin.parse({
      'pinned_messages': [
        {
          'id': 91,
          'chat_message_id': 12,
          'pinned_at': '2026-08-25T10:00:00.000Z',
          'excerpt': '<p>A &amp; B</p>',
          'pinned_by': {'id': 7, 'username': 'reader', 'name': 'Reader'},
          'message': {
            'id': 12,
            'chat_channel_id': 9,
            'message': 'A & B',
            'cooked': '<p>A &amp; B</p>',
            'user': {'id': 2, 'username': 'sam'},
          },
        },
      ],
      'membership': {
        'following': true,
        'last_viewed_pins_at': '2026-08-25T09:00:00.000Z',
        'has_unseen_pins': true,
      },
    }, 'https://meta.example');

    final pin = snapshot.pins.single;
    expect(pin.id, 91);
    expect(pin.messageId, 12);
    expect(pin.message.pinned, isTrue);
    expect(pin.pinnedBy.displayName, 'Reader');
    expect(pin.excerpt, 'A & B');
    expect(snapshot.membership?.following, isTrue);
    expect(snapshot.membership?.hasUnseenPins, isTrue);
    expect(snapshot.membership?.lastViewedPinsAt, DateTime.utc(2026, 8, 25, 9));
  });

  test('bounds a malformed oversized pin list to core’s channel limit', () {
    final snapshot = ChatPin.parse({
      'pinned_messages': [
        for (var id = 1; id <= 30; id++)
          {
            'id': id,
            'chat_message_id': id,
            'message': {
              'id': id,
              'chat_channel_id': 9,
              'cooked': '<p>$id</p>',
              'user': {'id': 2, 'username': 'sam'},
            },
          },
      ],
    }, 'https://meta.example');

    expect(snapshot.pins, hasLength(ChatPin.maximumPerChannel));
    expect(snapshot.pins.last.id, ChatPin.maximumPerChannel);
  });
}
