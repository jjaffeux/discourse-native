import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_signaling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('signal batching', () {
    test('rejects event thresholds outside the server bounds', () {
      for (final threshold in [0, 26]) {
        expect(
          () => VoiceSignalBatcher(
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
      final batcher = VoiceSignalBatcher(sendBatch: (_) async => requests++);
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
        final batcher = VoiceSignalBatcher(
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
      final batcher = VoiceSignalBatcher(
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
      final batcher = VoiceSignalBatcher(
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
        final batcher = VoiceSignalBatcher(
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

    test(
      'closing before an extracted batch starts prevents its request',
      () async {
        var requests = 0;
        final batcher = VoiceSignalBatcher(
          flushEventThreshold: 1,
          sendBatch: (_) async => requests++,
        );
        final sending = batcher.send(2, {'type': 'offer', 'sdp': 'offer'});

        batcher.close();
        await sending;
        await batcher.flush();

        expect(requests, 0);
      },
    );

    test('closing releases queued batches behind an active request', () async {
      final started = Completer<void>();
      final response = Completer<void>();
      final requests = <Map<String, Object?>>[];
      final batcher = VoiceSignalBatcher(
        flushEventThreshold: 1,
        sendBatch: (payload) {
          requests.add(payload);
          if (requests.length == 1) {
            started.complete();
            return response.future;
          }
          return Future<void>.value();
        },
      );
      addTearDown(() {
        batcher.close();
        if (!response.isCompleted) response.complete();
      });
      final active = batcher.send(2, {'type': 'offer', 'sdp': 'active'});
      await started.future;
      var queuedCompleted = false;
      final queued = Future.wait([
        batcher.send(2, {'type': 'offer', 'sdp': 'queued'}),
        batcher.send(3, {'type': 'offer', 'sdp': 'also queued'}),
      ]).then((_) => queuedCompleted = true);

      batcher.close();
      // Complete the cancelled senders' microtasks while the network request
      // remains explicitly blocked by response.
      await Future<void>.delayed(Duration.zero);
      expect(queuedCompleted, isTrue);
      response.complete();
      await Future.wait([active, queued]);
      await batcher.flush();

      expect(requests, [
        {
          'messages': [
            {
              'recipient_id': 2,
              'events': [
                {'type': 'offer', 'sdp': 'active'},
              ],
            },
          ],
        },
      ]);
    });
  });
}

int _eventCount(Map<String, Object?> payload) {
  final messages = payload['messages']! as List<Object?>;
  final message = messages.single! as Map<String, Object?>;
  return (message['events']! as List<Object?>).length;
}
