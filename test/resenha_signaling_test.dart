import 'package:discourse_native/src/plugins/resenha/resenha_signaling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'coalesces recipients and preserves each recipient event order',
    () async {
      final requests = <Map<String, Object?>>[];
      final batcher = ResenhaSignalBatcher(
        batchDelay: const Duration(hours: 1),
        sendBatch: (payload) async {
          requests.add(payload);
        },
      );
      addTearDown(batcher.close);

      final offer = batcher.send(2, {'type': 'offer', 'sdp': 'offer'});
      final candidates = batcher.send(3, {
        'events': [
          {
            'type': 'candidate',
            'candidate': {'candidate': 'first'},
          },
          {
            'type': 'candidate',
            'candidate': {'candidate': 'second'},
          },
        ],
      });

      await batcher.flush();
      await Future.wait([offer, candidates]);

      expect(requests, hasLength(1));
      final messages = requests.single['messages']! as List<Object?>;
      expect(messages, hasLength(2));
      expect((messages.first! as Map<String, Object?>)['recipient_id'], 2);
      final second = messages.last! as Map<String, Object?>;
      expect(second['recipient_id'], 3);
      expect(
        (second['events']! as List<Object?>).map(
          (event) =>
              ((event! as Map<String, Object?>)['candidate']!
                  as Map<String, Object?>)['candidate'],
        ),
        ['first', 'second'],
      );
    },
  );

  test('flushes one recipient before the twenty-event client cap', () async {
    final requests = <Map<String, Object?>>[];
    final batcher = ResenhaSignalBatcher(
      batchDelay: const Duration(hours: 1),
      sendBatch: (payload) async {
        requests.add(payload);
      },
    );
    addTearDown(batcher.close);

    final sending = batcher.send(2, {
      'events': [
        for (var index = 0; index < 21; index++)
          {
            'type': 'candidate',
            'candidate': {'candidate': 'candidate:$index'},
          },
      ],
    });
    await batcher.flush();
    await sending;

    expect(requests, hasLength(2));
    expect(_eventCount(requests[0]), 20);
    expect(_eventCount(requests[1]), 1);
  });

  test('closing drops a scheduled batch and releases its senders', () async {
    var requests = 0;
    final batcher = ResenhaSignalBatcher(
      batchDelay: const Duration(hours: 1),
      sendBatch: (_) async {
        requests += 1;
      },
    );

    final sending = batcher.send(2, {'type': 'offer', 'sdp': 'offer'});
    batcher.close();

    await expectLater(sending, completes);
    expect(requests, 0);
  });
}

int _eventCount(Map<String, Object?> payload) {
  final messages = payload['messages']! as List<Object?>;
  final message = messages.single! as Map<String, Object?>;
  return (message['events']! as List<Object?>).length;
}
