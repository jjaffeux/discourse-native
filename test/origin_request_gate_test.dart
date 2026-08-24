import 'dart:async';

import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:discourse_native/src/data/origin_request_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/manual_scheduler.dart';

void main() {
  group('OriginRequestGate', () {
    test(
      'bounds a FIFO backlog independently for each normalized origin',
      () async {
        final gate = OriginRequestGate(
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 2,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
        );
        addTearDown(gate.close);
        final first = await gate.acquire(
          Uri.parse('https://EXAMPLE.com:443/first'),
        );
        expect(first.origin, 'https://example.com');

        var thirdGranted = false;
        final second = gate.acquire(Uri.parse('https://example.com/second'));
        final third = gate.acquire(Uri.parse('https://example.com/third')).then(
          (lease) {
            thirdGranted = true;
            return lease;
          },
        );

        await expectLater(
          gate.acquire(Uri.parse('https://example.com/overflow')),
          throwsA(
            isA<OriginRequestGateOverloadException>()
                .having(
                  (error) => error.origin,
                  'origin',
                  'https://example.com',
                )
                .having((error) => error.maxQueued, 'maxQueued', 2),
          ),
        );
        final otherOrigin = await gate.acquire(
          Uri.parse('https://example.com:444/independent'),
        );

        first.release();
        final secondLease = await second;
        expect(thirdGranted, isFalse);
        secondLease.release();
        final thirdLease = await third;
        thirdLease.release();
        otherOrigin.release();
      },
    );

    test(
      'wait policy retains old and new work through an extended cooldown',
      () async {
        final scheduler = ManualScheduler();
        final gate = OriginRequestGate(
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 3,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        );
        addTearDown(gate.close);
        final origin = Uri.parse('https://forum.example');
        final active = await gate.acquire(origin.resolve('/active'));
        var oldWaiterGranted = false;
        var newWaiterGranted = false;
        final oldWaiter = gate.acquire(origin.resolve('/old')).then((lease) {
          oldWaiterGranted = true;
          return lease;
        });

        active.extendCooldown(const Duration(minutes: 1));
        scheduler.advance(const Duration(seconds: 10));
        active.extendCooldown(const Duration(seconds: 5));
        final newWaiter = gate.acquire(origin.resolve('/new')).then((lease) {
          newWaiterGranted = true;
          return lease;
        });
        active.release();

        scheduler.advance(const Duration(seconds: 49));
        expect(oldWaiterGranted, isFalse);
        expect(newWaiterGranted, isFalse);
        expect(scheduler.activeTimerCount, 1);

        scheduler.advance(const Duration(seconds: 1));
        final oldLease = await oldWaiter;
        expect(newWaiterGranted, isFalse, reason: 'waiters stay FIFO');
        oldLease.release();
        final newLease = await newWaiter;
        newLease.release();
        expect(scheduler.activeTimerCount, 0);
      },
    );

    test(
      'reject policy drops waiters and rejects new work until expiry',
      () async {
        final scheduler = ManualScheduler();
        final gate = OriginRequestGate(
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 2,
          cooldownPolicy: OriginRequestCooldownPolicy.reject,
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        );
        addTearDown(gate.close);
        final origin = Uri.parse('https://media.example');
        final active = await gate.acquire(origin.resolve('/active'));
        final queued = gate.acquire(origin.resolve('/queued'));
        final queuedRejection = expectLater(
          queued,
          throwsA(
            isA<OriginRequestGateCooldownException>().having(
              (error) => error.retryAfter,
              'retryAfter',
              const Duration(minutes: 1),
            ),
          ),
        );

        active.extendCooldown(const Duration(minutes: 1));
        await queuedRejection;
        scheduler.advance(const Duration(seconds: 10));
        await expectLater(
          gate.acquire(origin.resolve('/new')),
          throwsA(
            isA<OriginRequestGateCooldownException>()
                .having(
                  (error) => error.origin,
                  'origin',
                  'https://media.example',
                )
                .having(
                  (error) => error.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 50),
                ),
          ),
        );

        active.release();
        scheduler.advance(const Duration(seconds: 50));
        final afterExpiry = await gate.acquire(origin.resolve('/after'));
        afterExpiry.release();
      },
    );

    test('a related-origin cooldown uses the same rejection policy', () async {
      final scheduler = ManualScheduler();
      final gate = OriginRequestGate(
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 1,
        cooldownPolicy: OriginRequestCooldownPolicy.reject,
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
      addTearDown(gate.close);
      final related = Uri.parse('https://CDN.example:443/avatar.png');

      gate.extendCooldown(related, const Duration(seconds: 5));
      await expectLater(
        gate.acquire(related),
        throwsA(
          isA<OriginRequestGateCooldownException>().having(
            (error) => error.origin,
            'origin',
            'https://cdn.example',
          ),
        ),
      );

      scheduler.advance(const Duration(seconds: 5));
      final lease = await gate.acquire(related);
      lease.release();
    });

    test(
      'run starts synchronously and releases after success or failure',
      () async {
        final gate = OriginRequestGate(
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 1,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
        );
        addTearDown(gate.close);
        final url = Uri.parse('https://forum.example/request');
        var started = false;

        final success = gate.run(url, (_) async {
          started = true;
          return 1;
        });
        expect(started, isTrue);
        expect(await success, 1);

        final failure = gate.run<int>(url, (_) {
          throw StateError('delegate failed');
        });
        await expectLater(failure, throwsStateError);
        final afterFailure = await gate.acquire(url);
        afterFailure.release();
      },
    );

    test('forgets idle origins after release and cooldown expiry', () async {
      final scheduler = ManualScheduler();
      var cooldownsCreated = 0;
      final gate = OriginRequestGate(
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 1,
        cooldownPolicy: OriginRequestCooldownPolicy.wait,
        cooldownFactory: () {
          cooldownsCreated++;
          return OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          );
        },
      );
      addTearDown(gate.close);
      final url = Uri.parse('https://forum.example/request');

      final first = await gate.acquire(url);
      first.release();
      final second = await gate.acquire(url);
      expect(cooldownsCreated, 2, reason: 'a released idle origin is removed');

      second.extendCooldown(const Duration(seconds: 5));
      second.release();
      scheduler.advance(const Duration(seconds: 5));
      final third = await gate.acquire(url);
      expect(cooldownsCreated, 3, reason: 'an expired idle origin is removed');
      third.release();
    });

    test(
      'close rejects waiters but preserves active work and cancels wakes',
      () async {
        final scheduler = ManualScheduler();
        final gate = OriginRequestGate(
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 1,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        );
        final url = Uri.parse('https://forum.example/request');
        final response = Completer<int>();
        late OriginRequestContext activeContext;
        final active = gate.run(url, (context) async {
          activeContext = context;
          final value = await response.future;
          context.extendCooldown(const Duration(hours: 1));
          return value;
        });
        final queued = gate.acquire(url);
        final queuedRejection = expectLater(
          queued,
          throwsA(isA<OriginRequestGateClosedException>()),
        );
        activeContext.extendCooldown(const Duration(minutes: 1));
        expect(scheduler.activeTimerCount, 1);

        gate.close();
        await queuedRejection;
        expect(gate.isClosed, isTrue);
        expect(scheduler.activeTimerCount, 0);

        response.complete(7);
        expect(await active, 7);
        activeContext.extendCooldown(const Duration(hours: 1));
        expect(scheduler.activeTimerCount, 0);
        await expectLater(
          gate.acquire(url),
          throwsA(isA<OriginRequestGateClosedException>()),
        );
      },
    );
  });
}
