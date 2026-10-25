import 'dart:async';

import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:discourse_native/src/data/origin_request_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/manual_scheduler.dart';

void main() {
  for (final aggregate in [false, true]) {
    test(
      'bounds interactive overtakes in ${aggregate ? 'aggregate' : 'origin'} contention',
      () async {
        final gate = OriginRequestGate(
          maxConcurrent: aggregate ? 1 : null,
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 12,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
        );
        addTearDown(gate.close);
        final origin = Uri.parse('https://first.example');
        final other = Uri.parse('https://second.example');
        final active = await gate.acquire(origin);
        final order = <String>[];
        Future<void> enqueue(
          String name,
          Uri url,
          OriginRequestPriority priority,
        ) => gate.run(url, (_) async {
          order.add(name);
        }, priority: priority);
        final background = enqueue(
          'background',
          origin,
          OriginRequestPriority.normal,
        );
        final requests = <Future<void>>[];
        for (var i = 0; i < 6; i++) {
          requests.add(
            enqueue(
              'interactive-$i',
              aggregate && i.isOdd ? other : origin,
              OriginRequestPriority.interactive,
            ),
          );
          if (!aggregate) {
            await enqueue(
              'independent-$i',
              other,
              OriginRequestPriority.interactive,
            );
          }
        }
        final trailing = enqueue(
          'background-2',
          origin,
          OriginRequestPriority.normal,
        );
        order.clear();
        active.release();
        await Future.wait([background, ...requests, trailing]);
        expect(order, [
          'interactive-0',
          'interactive-1',
          'interactive-2',
          'background',
          'interactive-3',
          'interactive-4',
          'interactive-5',
          'background-2',
        ]);
      },
    );
  }

  for (final aggregate in [false, true]) {
    test(
      'interactive grants with no normal waiter keep the allowance in ${aggregate ? 'aggregate' : 'origin'} contention',
      () async {
        final gate = OriginRequestGate(
          maxConcurrent: aggregate ? 1 : null,
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 8,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
        );
        addTearDown(gate.close);
        final origin = Uri.parse('https://first.example');
        final active = await gate.acquire(origin);
        final order = <String>[];
        final hold = Completer<void>();
        Future<void> enqueue(
          String name,
          OriginRequestPriority priority, {
          Future<void>? until,
        }) => gate.run(origin, (_) async {
          order.add(name);
          await until;
        }, priority: priority);
        final early = [
          for (var i = 0; i < 3; i++)
            enqueue(
              'early-$i',
              OriginRequestPriority.interactive,
              until: i == 2 ? hold.future : null,
            ),
        ];
        active.release();
        await pumpEventQueue();
        expect(order, ['early-0', 'early-1', 'early-2']);

        final background = enqueue('background', OriginRequestPriority.normal);
        final late = enqueue('late', OriginRequestPriority.interactive);
        hold.complete();
        await Future.wait([...early, background, late]);
        expect(order, ['early-0', 'early-1', 'early-2', 'late', 'background']);
      },
    );
  }

  test(
    'another origin cannot reset a waiting origin fairness allowance',
    () async {
      final gate = OriginRequestGate(
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 12,
        cooldownPolicy: OriginRequestCooldownPolicy.wait,
      );
      addTearDown(gate.close);
      final origin = Uri.parse('https://first.example');
      final other = Uri.parse('https://second.example');
      final first = await gate.acquire(origin);
      final order = <String>[];
      final background = gate.acquire(origin).then((lease) {
        order.add('background');
        return lease;
      });
      final urgent = List.generate(
        4,
        (i) => gate
            .acquire(origin, priority: OriginRequestPriority.interactive)
            .then((lease) {
              order.add('interactive-$i');
              return lease;
            }),
      );
      first.release();
      for (var i = 0; i < 3; i++) {
        final lease = await urgent[i];
        final independent = await gate.acquire(other);
        independent.release();
        lease.release();
      }
      (await background).release();
      (await urgent.last).release();
      expect(order, [
        'interactive-0',
        'interactive-1',
        'interactive-2',
        'background',
        'interactive-3',
      ]);
    },
  );

  test(
    'promotion keeps original FIFO position and respects cooldown',
    () async {
      final scheduler = ManualScheduler();
      final gate = OriginRequestGate(
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 4,
        cooldownPolicy: OriginRequestCooldownPolicy.wait,
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
      addTearDown(gate.close);
      final origin = Uri.parse('https://first.example');
      final active = await gate.acquire(origin);
      var promoted = false;
      final order = <String>[];
      final older = gate.run(
        origin,
        (_) async {
          order.add('older');
        },
        resolvePriority: () => promoted
            ? OriginRequestPriority.interactive
            : OriginRequestPriority.normal,
      );
      final newer = gate.run(origin, (_) async {
        order.add('newer');
      }, priority: OriginRequestPriority.interactive);
      active.extendCooldown(const Duration(seconds: 2));
      active.release();
      promoted = true;
      scheduler.advance(const Duration(seconds: 1));
      expect(order, isEmpty);
      scheduler.advance(const Duration(seconds: 1));
      await Future.wait([older, newer]);
      expect(order, ['older', 'newer']);
    },
  );

  test('acquire re-resolves priority at each admission scan', () async {
    final gate = OriginRequestGate(
      maxConcurrentPerOrigin: 1,
      maxQueuedPerOrigin: 2,
      cooldownPolicy: OriginRequestCooldownPolicy.wait,
    );
    addTearDown(gate.close);
    final origin = Uri.parse('https://first.example');
    final active = await gate.acquire(origin);
    var promoted = false;
    final order = <String>[];
    Future<void> record(String name, Future<OriginRequestLease> admission) =>
        admission.then((lease) {
          order.add(name);
          lease.release();
        });
    final background = record('background', gate.acquire(origin));
    final promotable = record(
      'promotable',
      gate.acquire(
        origin,
        resolvePriority: () => promoted
            ? OriginRequestPriority.interactive
            : OriginRequestPriority.normal,
      ),
    );

    promoted = true;
    active.release();
    await Future.wait([background, promotable]);
    expect(order, ['promotable', 'background']);
  });

  group('OriginRequestGate', () {
    for (final useRun in [false, true]) {
      test(
        '${useRun ? 'run' : 'acquire'} cancellation frees queued capacity',
        () async {
          final gate = OriginRequestGate(
            maxConcurrentPerOrigin: 1,
            maxQueuedPerOrigin: 2,
            cooldownPolicy: OriginRequestCooldownPolicy.wait,
          );
          addTearDown(gate.close);
          final url = Uri.parse('https://example.com/work');
          final held = await gate.acquire(url);
          final abort = Completer<void>();
          var started = false;
          final Future<Object?> cancelled = useRun
              ? gate.run<Object?>(url, (_) async {
                  started = true;
                  return null;
                }, abortTrigger: abort.future)
              : gate.acquire(url, abortTrigger: abort.future);
          final survivor = gate.acquire(url);
          final rejected = expectLater(
            cancelled,
            throwsA(isA<OriginRequestGateCancelledException>()),
          );

          abort.complete();
          await rejected;
          final next = gate.acquire(url);
          next.ignore();
          held.release();
          final survivorLease = await survivor;
          var nextGranted = false;
          final nextReady = next.then((lease) {
            nextGranted = true;
            return lease;
          });
          await pumpEventQueue();
          expect(started, isFalse);
          expect(nextGranted, isFalse);
          survivorLease.release();
          (await nextReady).release();
        },
      );
    }

    test('an erroring abort signal cancels queued admission', () async {
      final gate = OriginRequestGate(
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 1,
        cooldownPolicy: OriginRequestCooldownPolicy.wait,
      );
      addTearDown(gate.close);
      final url = Uri.parse('https://example.com/work');
      final held = await gate.acquire(url);
      final abort = Completer<void>();
      final cancelled = gate.acquire(url, abortTrigger: abort.future);
      final rejected = expectLater(
        cancelled,
        throwsA(isA<OriginRequestGateCancelledException>()),
      );

      abort.completeError(StateError('cancelled by owner'));
      await rejected;
      final next = gate.acquire(url);
      next.ignore();
      held.release();
      (await next).release();
    });

    test('cancellation after a grant leaves the lease caller-owned', () async {
      final gate = OriginRequestGate(
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 1,
        cooldownPolicy: OriginRequestCooldownPolicy.wait,
      );
      addTearDown(gate.close);
      final url = Uri.parse('https://example.com/work');
      final abort = Completer<void>();
      final held = await gate.acquire(url, abortTrigger: abort.future);

      abort.completeError(StateError('owner already has the lease'));
      var nextGranted = false;
      final next = gate.acquire(url).then((lease) {
        nextGranted = true;
        return lease;
      });
      await pumpEventQueue();

      expect(nextGranted, isFalse);
      held.release();
      (await next).release();
    });

    test(
      'cancellation after gate close leaves its rejection unchanged',
      () async {
        final gate = OriginRequestGate(
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 1,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
        );
        final url = Uri.parse('https://example.com/work');
        final held = await gate.acquire(url);
        final abort = Completer<void>();
        final pending = gate.acquire(url, abortTrigger: abort.future);
        final rejected = expectLater(
          pending,
          throwsA(isA<OriginRequestGateClosedException>()),
        );
        gate.close();
        await rejected;
        abort.complete();
        await pumpEventQueue();
        held.release();
      },
    );

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

    // Diagnostics attribute an HTTP request to the operation and correlation
    // in its zone, so a grant must not lend queued work the releaser's zone.
    group('queued work starts in the zone that submitted it', () {
      final origin = Uri.parse('https://forum.example');

      Future<Object?> submit(
        OriginRequestGate gate,
        Uri url,
        String submitter, {
        Future<void>? hold,
      }) => runZoned(
        () => gate.run(url, (_) async {
          await hold;
          return Zone.current[#submitter];
        }),
        zoneValues: {#submitter: submitter},
      );

      test('when the origin releases a slot', () async {
        final gate = OriginRequestGate(
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 1,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
        );
        addTearDown(gate.close);
        final hold = Completer<void>();
        final active = submit(gate, origin, 'active', hold: hold.future);
        final queued = submit(gate, origin, 'queued');

        hold.complete();

        expect(await active, 'active');
        expect(await queued, 'queued');
      });

      test('when another origin releases an aggregate slot', () async {
        final gate = OriginRequestGate(
          maxConcurrent: 1,
          maxConcurrentPerOrigin: 1,
          maxQueuedPerOrigin: 1,
          cooldownPolicy: OriginRequestCooldownPolicy.wait,
        );
        addTearDown(gate.close);
        final hold = Completer<void>();
        final active = submit(gate, origin, 'active', hold: hold.future);
        final queued = submit(
          gate,
          Uri.parse('https://other.example'),
          'queued',
        );

        hold.complete();

        expect(await active, 'active');
        expect(await queued, 'queued');
      });

      test('when a cooldown wakes', () async {
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
        addTearDown(gate.close);
        gate.extendCooldown(origin, const Duration(seconds: 30));
        final queued = submit(gate, origin, 'queued');

        runZoned(
          () => scheduler.advance(const Duration(seconds: 30)),
          zoneValues: {#submitter: 'wake'},
        );

        expect(await queued, 'queued');
      });
    });

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

      test('expiry grants waiting origins in submission order', () async {
        final gate = createGate();
        final other = Uri.parse('https://other.example');
        gate.extendCooldown(other, const Duration(seconds: 1));
        final started = <String>[];
        final requests = [
          gate.run(origin, (_) async => started.add('first')),
          gate.run(other, (_) async => started.add('second')),
        ];

        elapsed = const Duration(seconds: 2);
        requests.add(
          gate.run(
            Uri.parse('https://third.example'),
            (_) async => started.add('third'),
          ),
        );
        expect(started, ['first', 'second', 'third']);
        await Future.wait(requests);
        expect(scheduler.activeTimerCount, 0);
      });

      test('a zero extension admits work whose cooldown has expired', () async {
        final gate = createGate();
        var started = false;
        final queued = gate.run(origin, (_) async => started = true);

        elapsed = const Duration(seconds: 2);
        gate.extendCooldown(origin, Duration.zero);
        expect(started, isTrue);
        await queued;
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

    test('a cooldown rejection empties only its own origin backlog', () async {
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
      final limited = Uri.parse('https://limited.example');
      final unrelated = Uri.parse('https://unrelated.example');
      final limitedActive = await gate.acquire(limited);
      final unrelatedActive = await gate.acquire(unrelated);
      final rejected = expectLater(
        gate.acquire(limited),
        throwsA(isA<OriginRequestGateCooldownException>()),
      );
      final survivor = gate.acquire(unrelated);

      limitedActive.extendCooldown(const Duration(minutes: 1));
      await rejected;
      unrelatedActive.release();
      (await survivor).release();

      scheduler.advance(const Duration(minutes: 1));
      final next = gate.acquire(limited);
      limitedActive.release();
      (await next).release();
    });

    test('a released origin keeps its cooldown', () async {
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
      addTearDown(gate.close);
      final url = Uri.parse('https://forum.example/request');
      final lease = await gate.acquire(url);
      lease.extendCooldown(const Duration(seconds: 5));
      lease.release();

      var granted = false;
      final next = gate.acquire(url).then((lease) {
        granted = true;
        return lease;
      });
      scheduler.advance(const Duration(seconds: 4));
      await pumpEventQueue();
      expect(granted, isFalse);

      scheduler.advance(const Duration(seconds: 1));
      (await next).release();
    });

    test('a release frees exactly one slot of its origin', () async {
      final gate = OriginRequestGate(
        maxConcurrentPerOrigin: 2,
        maxQueuedPerOrigin: 1,
        cooldownPolicy: OriginRequestCooldownPolicy.wait,
      );
      addTearDown(gate.close);
      final url = Uri.parse('https://forum.example/request');
      final first = await gate.acquire(url);
      final second = await gate.acquire(url);

      first.release();
      first.release();
      final third = await gate.acquire(url);
      var fourthGranted = false;
      final fourth = gate.acquire(url).then((lease) {
        fourthGranted = true;
        return lease;
      });
      await pumpEventQueue();
      expect(fourthGranted, isFalse);

      second.release();
      (await fourth).release();
      third.release();
    });

    test(
      'a context captured beyond its operation cannot extend the cooldown',
      () async {
        final scheduler = ManualScheduler();
        final gate = OriginRequestGate(
          maxConcurrentPerOrigin: 2,
          maxQueuedPerOrigin: 1,
          cooldownPolicy: OriginRequestCooldownPolicy.reject,
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        );
        addTearDown(gate.close);
        final url = Uri.parse('https://forum.example/request');
        final held = await gate.acquire(url);
        late OriginRequestContext captured;
        await gate.run(url, (context) async => captured = context);

        captured.extendCooldown(const Duration(minutes: 1));
        expect(scheduler.activeTimerCount, 0);
        (await gate.acquire(url)).release();
        held.release();
      },
    );

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

      gate.extendCooldown(url, Duration.zero);
      final fourth = await gate.acquire(url);
      expect(cooldownsCreated, 5, reason: 'a zero extension keeps no origin');
      fourth.release();
    });

    test('forgets an origin whose only waiter is cancelled', () async {
      var cooldownsCreated = 0;
      final gate = OriginRequestGate(
        maxConcurrent: 1,
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 1,
        cooldownPolicy: OriginRequestCooldownPolicy.wait,
        cooldownFactory: () {
          cooldownsCreated++;
          return OriginCooldown();
        },
      );
      addTearDown(gate.close);
      final held = await gate.acquire(Uri.parse('https://first.example'));
      final waiting = Uri.parse('https://second.example');
      final abort = Completer<void>();
      final cancelled = expectLater(
        gate.acquire(waiting, abortTrigger: abort.future),
        throwsA(isA<OriginRequestGateCancelledException>()),
      );

      abort.complete();
      await cancelled;
      held.release();
      final lease = await gate.acquire(waiting);
      expect(cooldownsCreated, 3, reason: 'a cancelled idle origin is removed');
      lease.release();
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
