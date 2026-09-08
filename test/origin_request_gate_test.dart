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

    group('when the clock expires before timer delivery', () {
      late ManualScheduler scheduler;
      late Duration elapsed;
      final origin = Uri.parse('https://forum.example');

      OriginRequestGate createGate({
        int? maxConcurrent,
        int maxQueuedPerOrigin = 1,
        OriginRequestCooldownPolicy cooldownPolicy =
            OriginRequestCooldownPolicy.wait,
      }) {
        final gate = OriginRequestGate(
          maxConcurrent: maxConcurrent,
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: maxQueuedPerOrigin,
          cooldownPolicy: cooldownPolicy,
          cooldownFactory: () => OriginCooldown(
            clock: () => elapsed,
            timerFactory: scheduler.createTimer,
          ),
        );
        addTearDown(gate.close);
        gate.extendCooldown(origin, const Duration(seconds: 1));
        return gate;
      }

      setUp(() {
        scheduler = ManualScheduler();
        elapsed = Duration.zero;
      });

      test('rejecting a full backlog preserves its expiry wake', () async {
        final gate = createGate();
        var started = false;
        final queued = gate.run(origin, (_) async {
          started = true;
          return 7;
        });
        // Capture shutdown errors too, so a stalled queue fails without waiting
        // for a real-time timeout or leaving an unhandled future at teardown.
        final outcome = queued.then<Object>(
          (value) => value,
          onError: (Object error) => error,
        );

        elapsed = const Duration(seconds: 2);
        await expectLater(
          gate.acquire(origin),
          throwsA(isA<OriginRequestGateOverloadException>()),
        );
        expect(started, isFalse);

        scheduler.advance(const Duration(seconds: 1));
        gate.close();
        expect(started, isTrue);
        expect(await outcome, 7);
        expect(scheduler.activeTimerCount, 0);
      });

      test('a spare backlog slot drains accepted work in FIFO order', () async {
        final gate = createGate(maxQueuedPerOrigin: 2);
        final started = <int>[];
        final response = Completer<void>();
        final first = gate.run(origin, (_) {
          started.add(1);
          return response.future;
        });

        elapsed = const Duration(seconds: 2);
        final second = gate.run(origin, (_) async => started.add(2));
        expect(started, [1]);
        scheduler.advance(const Duration(seconds: 1));
        expect(started, [1]);

        response.complete();
        await first;
        await second;
        expect(started, [1, 2]);
        expect(scheduler.activeTimerCount, 0);
      });

      test('expiry respects both caps and FIFO within priorities', () async {
        final gate = createGate(maxConcurrent: 2, maxQueuedPerOrigin: 4);
        final firstBlocker = await gate.acquire(Uri.https('first.example'));
        final secondBlocker = await gate.acquire(Uri.https('second.example'));
        final started = <String>[];
        final responses = <String, Completer<void>>{};
        final requests = <String, Future<void>>{};
        for (final (name, priority) in [
          ('normal 1', OriginRequestPriority.normal),
          ('interactive 1', OriginRequestPriority.interactive),
          ('normal 2', OriginRequestPriority.normal),
          ('interactive 2', OriginRequestPriority.interactive),
        ]) {
          final response = Completer<void>();
          responses[name] = response;
          requests[name] = gate.run(origin, (_) {
            started.add(name);
            return response.future;
          }, priority: priority);
        }

        elapsed = const Duration(seconds: 2);
        await expectLater(
          gate.acquire(origin, priority: OriginRequestPriority.interactive),
          throwsA(isA<OriginRequestGateOverloadException>()),
        );
        scheduler.advance(const Duration(seconds: 1));
        expect(started, isEmpty, reason: 'the aggregate cap still applies');

        firstBlocker.release();
        expect(started, ['interactive 1']);
        secondBlocker.release();
        expect(started, ['interactive 1'], reason: 'the origin cap applies');

        const order = [
          'interactive 1',
          'interactive 2',
          'normal 1',
          'normal 2',
        ];
        for (var index = 0; index < order.length; index++) {
          expect(started, order.take(index + 1));
          responses[order[index]]!.complete();
          await requests[order[index]]!;
        }
        expect(started, order);
        expect(scheduler.activeTimerCount, 0);
      });

      test(
        'close cancels the delayed wake and rejects accepted work',
        () async {
          final gate = createGate();
          var started = false;
          final queued = gate.run(origin, (_) async => started = true);
          final rejection = expectLater(
            queued,
            throwsA(isA<OriginRequestGateClosedException>()),
          );
          elapsed = const Duration(seconds: 2);
          await expectLater(
            gate.acquire(origin),
            throwsA(isA<OriginRequestGateOverloadException>()),
          );

          gate.close();
          await rejection;
          gate.extendCooldown(origin, const Duration(seconds: 5));
          scheduler.advance(const Duration(seconds: 10));
          expect(started, isFalse);
          expect(scheduler.activeTimerCount, 0);
          await expectLater(
            gate.acquire(origin),
            throwsA(isA<OriginRequestGateClosedException>()),
          );
        },
      );

      test(
        'an extension replaces the delayed wake without shortening',
        () async {
          final gate = createGate();
          var started = false;
          final queued = gate.run(origin, (_) async => started = true);
          elapsed = const Duration(seconds: 2);
          await expectLater(
            gate.acquire(origin),
            throwsA(isA<OriginRequestGateOverloadException>()),
          );

          gate.extendCooldown(origin, const Duration(seconds: 3));
          elapsed = const Duration(seconds: 3);
          gate.extendCooldown(origin, const Duration(seconds: 1));
          scheduler.advance(const Duration(seconds: 1));
          expect(started, isFalse, reason: 'the old wake has been replaced');
          expect(scheduler.activeTimerCount, 1);

          // Deliver the replacement early relative to the monotonic clock.
          scheduler.advance(const Duration(seconds: 2));
          expect(started, isFalse);
          expect(scheduler.activeTimerCount, 1);
          elapsed = const Duration(seconds: 5);
          scheduler.advance(const Duration(seconds: 2));
          expect(started, isTrue);
          await queued;
          expect(scheduler.activeTimerCount, 0);
        },
      );

      test(
        'a synchronous callback can close while admitting new work',
        () async {
          final gate = createGate(maxQueuedPerOrigin: 2);
          final first = gate.run(origin, (context) async {
            gate.close();
            context.extendCooldown(const Duration(seconds: 5));
            return 7;
          });

          elapsed = const Duration(seconds: 2);
          var secondStarted = false;
          final second = gate.run(origin, (_) async => secondStarted = true);
          await expectLater(
            second,
            throwsA(isA<OriginRequestGateClosedException>()),
          );
          expect(await first, 7);
          scheduler.advance(const Duration(seconds: 10));
          expect(secondStarted, isFalse);
          expect(gate.isClosed, isTrue);
          expect(scheduler.activeTimerCount, 0);
        },
      );

      test('a synchronous callback can extend before the next grant', () async {
        final gate = createGate(maxQueuedPerOrigin: 2);
        final first = gate.run(origin, (context) async {
          context.extendCooldown(const Duration(seconds: 3));
        });

        elapsed = const Duration(seconds: 2);
        var secondStarted = false;
        final second = gate.run(origin, (_) async => secondStarted = true);
        await first;
        scheduler.advance(const Duration(seconds: 1));
        expect(secondStarted, isFalse);
        expect(scheduler.activeTimerCount, 1);

        elapsed = const Duration(seconds: 5);
        scheduler.advance(const Duration(seconds: 2));
        expect(secondStarted, isTrue);
        await second;
        expect(scheduler.activeTimerCount, 0);
      });

      test('reject policy admits work as soon as the clock expires', () async {
        final gate = createGate(
          cooldownPolicy: OriginRequestCooldownPolicy.reject,
        );
        await expectLater(
          gate.acquire(origin),
          throwsA(isA<OriginRequestGateCooldownException>()),
        );

        elapsed = const Duration(seconds: 2);
        var started = false;
        final request = gate.run(origin, (_) async => started = true);
        expect(started, isTrue);
        await request;
        scheduler.advance(const Duration(seconds: 1));
        expect(scheduler.activeTimerCount, 0);
      });
    });

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
