import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/media_request_coordinator.dart';
import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/manual_scheduler.dart';

void main() {
  group('MediaRequestCoordinator', () {
    test('a zero Retry-After preserves already queued work', () async {
      final scheduler = ManualScheduler();
      final coordinator = MediaRequestCoordinator(
        maxConcurrentPerOrigin: 1,
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
      addTearDown(coordinator.close);
      final origin = Uri.parse('https://media.example');

      final active = await coordinator.acquire(origin.resolve('/active'));
      var queuedWasGranted = false;
      final queued = coordinator.acquire(origin.resolve('/queued')).then((
        lease,
      ) {
        queuedWasGranted = true;
        return lease;
      });

      active.rateLimited({'retry-after': '0'});
      expect(scheduler.activeTimerCount, 0);
      expect(queuedWasGranted, isFalse);

      active.release();
      final queuedLease = await queued;
      expect(queuedWasGranted, isTrue);
      queuedLease.release();
    });

    test('cooldown expiry follows the injected monotonic clock', () async {
      final scheduler = ManualScheduler();
      final coordinator = MediaRequestCoordinator(
        defaultRateLimitCooldown: const Duration(minutes: 1),
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
      addTearDown(coordinator.close);
      final url = Uri.parse('https://media.example/avatar.png');

      final active = await coordinator.acquire(url);
      active.rateLimited(const {});
      active.release();

      await expectLater(
        coordinator.acquire(url),
        throwsA(
          isA<MediaOriginRateLimitedException>().having(
            (error) => error.retryAfter,
            'retryAfter',
            const Duration(minutes: 1),
          ),
        ),
      );
      scheduler.advance(const Duration(seconds: 59));
      await expectLater(
        coordinator.acquire(url),
        throwsA(
          isA<MediaOriginRateLimitedException>().having(
            (error) => error.retryAfter,
            'retryAfter',
            const Duration(seconds: 1),
          ),
        ),
      );

      scheduler.advance(const Duration(seconds: 1));
      expect(scheduler.activeTimerCount, 0);
      final afterCooldown = await coordinator.acquire(url);
      afterCooldown.release();
    });

    test('HTTP-date cooldowns propagate to a related origin', () async {
      final scheduler = ManualScheduler();
      final now = DateTime.utc(2026, 8, 24, 12);
      final coordinator = MediaRequestCoordinator(
        clock: () => now,
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
      addTearDown(coordinator.close);
      final cdn = Uri.parse('https://cdn.example/avatar.png');
      final forum = Uri.parse('https://forum.example/users/1');
      final active = await coordinator.acquire(cdn, relatedUrl: forum);

      active.rateLimited({
        'retry-after': HttpDate.format(now.add(const Duration(seconds: 30))),
      });
      active.release();

      for (final url in [cdn, forum]) {
        await expectLater(
          coordinator.acquire(url),
          throwsA(
            isA<MediaOriginRateLimitedException>()
                .having((error) => error.origin, 'origin', url.origin)
                .having(
                  (error) => error.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 30),
                ),
          ),
        );
      }
    });

    test('close rejects queued work and makes an active lease inert', () async {
      final scheduler = ManualScheduler();
      final coordinator = MediaRequestCoordinator(
        maxConcurrentPerOrigin: 1,
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
      final origin = Uri.parse('https://media.example');
      final active = await coordinator.acquire(origin.resolve('/active'));
      final queued = coordinator.acquire(origin.resolve('/queued'));
      final queuedRejection = expectLater(queued, throwsA(isA<StateError>()));

      coordinator.close();
      await queuedRejection;
      active.rateLimited({'retry-after': '3600'});
      active.release();

      expect(scheduler.activeTimerCount, 0);
      await expectLater(
        coordinator.acquire(origin.resolve('/later')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DiscourseRequestCoordinator', () {
    test('a shorter later 429 cannot reduce an origin cooldown', () async {
      final scheduler = ManualScheduler();
      final coordinator = DiscourseRequestCoordinator(
        maxConcurrentPerOrigin: 2,
        cooldownFactory: () => OriginCooldown(
          clock: scheduler.now,
          timerFactory: scheduler.createTimer,
        ),
      );
      addTearDown(coordinator.close);
      final origin = Uri.parse('https://forum.example');
      final firstResponse = Completer<http.Response>();
      final secondResponse = Completer<http.Response>();
      var sends = 0;

      final first = coordinator.run(origin.resolve('/first'), () {
        sends++;
        return firstResponse.future;
      });
      final second = coordinator.run(origin.resolve('/second'), () {
        sends++;
        return secondResponse.future;
      });
      expect(sends, 2);

      firstResponse.complete(
        http.Response('{}', 429, headers: {'retry-after': '60'}),
      );
      expect((await first).statusCode, 429);
      scheduler.advance(const Duration(seconds: 10));
      secondResponse.complete(
        http.Response('{}', 429, headers: {'retry-after': '5'}),
      );
      expect((await second).statusCode, 429);
      expect(scheduler.activeTimerCount, 1);

      final queued = coordinator.run(origin.resolve('/queued'), () async {
        sends++;
        return http.Response('{}', 200);
      });
      expect(sends, 2);
      scheduler.advance(const Duration(seconds: 49));
      expect(sends, 2);

      scheduler.advance(const Duration(seconds: 1));
      expect((await queued).statusCode, 200);
      expect(sends, 3);
      expect(scheduler.activeTimerCount, 0);
    });

    test(
      'close rejects queued work but preserves an in-flight result',
      () async {
        final scheduler = ManualScheduler();
        final coordinator = DiscourseRequestCoordinator(
          maxConcurrentPerOrigin: 1,
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        );
        final origin = Uri.parse('https://forum.example');
        final activeResponse = Completer<http.Response>();
        var sends = 0;
        final active = coordinator.run(origin.resolve('/active'), () {
          sends++;
          return activeResponse.future;
        });
        final queued = coordinator.run(origin.resolve('/queued'), () async {
          sends++;
          return http.Response('{}', 200);
        });
        final queuedRejection = expectLater(queued, throwsA(isA<StateError>()));

        coordinator.close();
        await queuedRejection;
        activeResponse.complete(
          http.Response('{}', 429, headers: {'retry-after': '3600'}),
        );

        expect((await active).statusCode, 429);
        expect(sends, 1);
        expect(scheduler.activeTimerCount, 0);
      },
    );
  });
}
