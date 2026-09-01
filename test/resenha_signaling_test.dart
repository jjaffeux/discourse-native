import 'package:discourse_native/src/plugins/resenha/resenha_signaling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('signal batching', () {
    test('rejects event thresholds outside the server bounds', () {
      for (final threshold in [0, 26]) {
        expect(
          () => ResenhaSignalBatcher(
            flushEventThreshold: threshold,
            sendBatch: (_) async {},
          ),
          throwsRangeError,
          reason: 'threshold $threshold',
        );
      }
    });

    test('rejects a non-positive recipient without sending', () async {
      var requests = 0;
      final batcher = ResenhaSignalBatcher(sendBatch: (_) async => requests++);
      addTearDown(batcher.close);

      await expectLater(
        batcher.send(0, {'type': 'offer', 'sdp': 'offer'}),
        throwsRangeError,
      );

      expect(requests, 0);
    });

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

        expect(requests, [
          {
            'messages': [
              {
                'recipient_id': 2,
                'events': [
                  {'type': 'offer', 'sdp': 'offer'},
                ],
              },
              {
                'recipient_id': 3,
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
              },
            ],
          },
        ]);
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

    test('reports a failed batch and accepts the next one', () async {
      var attempts = 0;
      final batcher = ResenhaSignalBatcher(
        batchDelay: const Duration(hours: 1),
        sendBatch: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
        },
      );
      addTearDown(batcher.close);

      final first = batcher.send(2, {'type': 'offer', 'sdp': 'first'});
      final firstFailure = expectLater(first, throwsStateError);
      await batcher.flush();
      await firstFailure;

      final second = batcher.send(2, {'type': 'offer', 'sdp': 'second'});
      await batcher.flush();

      await expectLater(second, completes);
      expect(attempts, 2);
    });

    test(
      'drops a scheduled batch and releases its senders when closed',
      () async {
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
      },
    );
  });
}

int _eventCount(Map<String, Object?> payload) {
  final messages = payload['messages']! as List<Object?>;
  final message = messages.single! as Map<String, Object?>;
  return (message['events']! as List<Object?>).length;
}
