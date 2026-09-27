import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/media_request_coordinator.dart';
import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/manual_scheduler.dart';

void main() {
  const cooldownCases = [
    (
      name: 'without a Date header',
      headers: {'retry-after': 'Mon, 24 Aug 2026 12:00:30 GMT'},
      clockSkew: Duration.zero,
    ),
    (
      name: 'with the device clock 5 minutes ahead',
      headers: {
        'date': 'Mon, 24 Aug 2026 12:00:00 GMT',
        'retry-after': 'Mon, 24 Aug 2026 12:00:30 GMT',
      },
      clockSkew: Duration(minutes: 5),
    ),
    (
      name: 'with the device clock 5 minutes behind',
      headers: {
        'date': 'Mon, 24 Aug 2026 12:00:00 GMT',
        'retry-after': 'Mon, 24 Aug 2026 12:00:30 GMT',
      },
      clockSkew: Duration(minutes: -5),
    ),
    (
      name: 'with an invalid Date header',
      headers: {
        'date': 'not a date',
        'retry-after': 'Mon, 24 Aug 2026 12:00:30 GMT',
      },
      clockSkew: Duration.zero,
    ),
    (
      name: 'with numeric Retry-After and a skewed Date header',
      headers: {'date': 'Mon, 24 Aug 2026 12:00:00 GMT', 'retry-after': '30'},
      clockSkew: Duration(minutes: 5),
    ),
  ];

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

    for (final scenario in cooldownCases) {
      test('pauses media and related origins ${scenario.name}', () async {
        final scheduler = ManualScheduler();
        var now = DateTime.utc(2026, 8, 24, 12).add(scenario.clockSkew);
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

        active.rateLimited(scenario.headers);
        active.release();

        now = now.add(const Duration(days: 1));
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

        now = now.subtract(const Duration(days: 2));
        scheduler.advance(const Duration(seconds: 30));
        for (final url in [cdn, forum]) {
          final afterCooldown = await coordinator.acquire(url);
          afterCooldown.release();
        }
        expect(scheduler.activeTimerCount, 0);
      });
    }

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
    test(
      'shares immutable headers regardless of name case and order',
      () async {
        final coordinator = DiscourseRequestCoordinator();
        addTearDown(coordinator.close);
        final url = Uri.https('forum.example', '/site.json');
        final response = Completer<http.Response>();
        var sends = 0;

        Future<http.Response> read(Map<String, String> headers) =>
            coordinator.run(
              url,
              () {
                sends++;
                return response.future;
              },
              coalesce: DiscourseGetRequestKey(
                url,
                headers: headers,
                timeout: const Duration(seconds: 10),
                maxResponseBytes: 1024,
              ),
            );

        final headers = {
          'Accept': 'application/json',
          'User-Api-Key': 'secret',
        };
        final first = read(headers);
        headers['Accept'] = 'text/html';
        final repeated = read({
          'user-api-key': 'secret',
          'accept': 'application/json',
        });
        final buffered = http.Response('{}', 200);
        response.complete(buffered);

        expect(await first, same(buffered));
        expect(await repeated, same(buffered));
        expect(sends, 1);
        await read({'Accept': 'application/json', 'User-Api-Key': 'secret'});
        expect(sends, 2);
      },
    );

    for (final scenario in cooldownCases) {
      test('holds queued requests ${scenario.name}', () async {
        final scheduler = ManualScheduler();
        var now = DateTime.utc(2026, 8, 24, 12).add(scenario.clockSkew);
        final coordinator = DiscourseRequestCoordinator(
          clock: () => now,
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        );
        addTearDown(coordinator.close);
        final origin = Uri.parse('https://forum.example');
        await coordinator.run(
          origin,
          () async => http.Response(
            '{"extras":{"wait_seconds":42}}',
            429,
            headers: scenario.headers,
          ),
        );
        var sent = false;
        final queued = coordinator.run(origin.resolve('/queued'), () async {
          sent = true;
          return http.Response('{}', 200);
        });

        now = now.add(const Duration(days: 1));
        scheduler.advance(const Duration(seconds: 29));
        expect(sent, isFalse);
        now = now.subtract(const Duration(days: 2));
        scheduler.advance(const Duration(seconds: 1));
        expect(sent, isTrue);
        expect((await queued).statusCode, 200);
        expect(scheduler.activeTimerCount, 0);
      });
    }

    for (final refusal in [
      (
        name: 'an exhausted daily like allowance',
        // ApplicationController's rendering of PostAction's one-day
        // `create_like` limiter, which names no request-wide error code.
        headers: {'retry-after': '68400', 'content-type': 'application/json'},
        body: jsonEncode({
          'errors': [
            "You've reached the maximum number of likes. Try again in 19 hours.",
          ],
          'error_type': 'rate_limit',
          'extras': {'wait_seconds': 68400, 'time_left': '19 hours'},
        }),
      ),
      (
        name: 'a spent search budget',
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'failed': 'FAILED',
          'message':
              "You've performed this action too many times, please try "
              'again later.',
        }),
      ),
    ]) {
      test('${refusal.name} leaves queued work free to go', () async {
        final scheduler = ManualScheduler();
        final coordinator = DiscourseRequestCoordinator(
          maxConcurrentPerOrigin: 1,
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        );
        addTearDown(coordinator.close);
        final origin = Uri.parse('https://forum.example');
        final refusalResponse = Completer<http.Response>();
        final refused = coordinator.run(
          origin.resolve('/post_actions'),
          () => refusalResponse.future,
        );
        var sent = false;
        final queued = coordinator.run(
          origin.resolve('/latest.json'),
          () async {
            sent = true;
            return http.Response('{}', 200);
          },
        );
        expect(sent, isFalse);

        refusalResponse.complete(
          http.Response(refusal.body, 429, headers: refusal.headers),
        );

        expect((await refused).statusCode, 429);
        await pumpEventQueue();
        expect(sent, isTrue);
        expect((await queued).statusCode, 200);
        expect(scheduler.activeTimerCount, 0);
      });
    }

    for (final limit in [
      (
        name: "the user API key's per-minute limiter",
        // ApplicationController adds the header whenever the limiter it
        // rescued names an error code; only request-wide limiters do.
        headers: {
          'retry-after': '60',
          'content-type': 'application/json',
          'discourse-rate-limit-error-code': 'user_api_key_limiter_60_secs',
        },
        body: jsonEncode({
          'errors': [
            "You've performed this action too many times. Please wait 60 "
                'seconds before trying again.',
          ],
          'error_type': 'rate_limit',
          'extras': {'wait_seconds': 60, 'time_left': '60 seconds'},
        }),
      ),
      (
        name: "the request tracker's per-IP limiter",
        headers: {
          'retry-after': '60',
          'content-type': 'text/plain',
          'discourse-rate-limit-error-code': 'ip_60_secs_limit',
        },
        body:
            "Slow down, you're making too many requests.\n"
            'Please retry again in 60 seconds.\n'
            'Error code: ip_60_secs_limit.\n',
      ),
      (
        name: 'a body too large to be an action refusal',
        headers: {'retry-after': '60'},
        body: jsonEncode({
          'error_type': 'rate_limit',
          'errors': ['x' * (16 * 1024)],
        }),
      ),
    ]) {
      test('${limit.name} holds queued work for its delay', () async {
        final scheduler = ManualScheduler();
        final coordinator = DiscourseRequestCoordinator(
          cooldownFactory: () => OriginCooldown(
            clock: scheduler.now,
            timerFactory: scheduler.createTimer,
          ),
        );
        addTearDown(coordinator.close);
        final origin = Uri.parse('https://forum.example');
        await coordinator.run(
          origin.resolve('/latest.json'),
          () async => http.Response(limit.body, 429, headers: limit.headers),
        );
        var sent = false;
        final queued = coordinator.run(origin.resolve('/queued'), () async {
          sent = true;
          return http.Response('{}', 200);
        });

        scheduler.advance(const Duration(seconds: 59));
        expect(sent, isFalse);
        scheduler.advance(const Duration(seconds: 1));
        expect(sent, isTrue);
        expect((await queued).statusCode, 200);
        expect(scheduler.activeTimerCount, 0);
      });
    }

    test('an elapsed server HTTP date overrides a longer body delay', () {
      final now = DateTime.utc(2026, 8, 24, 12);
      final response = http.Response(
        '{"extras":{"wait_seconds":42}}',
        429,
        headers: {
          'date': HttpDate.format(now),
          'retry-after': HttpDate.format(
            now.subtract(const Duration(minutes: 1)),
          ),
        },
      );

      expect(
        DiscourseRequestCoordinator.explicitRetryAfter(
          response,
          now: now.subtract(const Duration(minutes: 5)),
        ),
        Duration.zero,
      );
    });

    for (final header in [
      null,
      '',
      '-1',
      'not a date',
      'Wed, 24 NotAMonth 2026 12:00:00 GMT',
    ]) {
      test('an unreadable Retry-After "$header" uses the body delay', () {
        expect(
          DiscourseRequestCoordinator.explicitRetryAfter(
            http.Response(
              '{"extras":{"wait_seconds":42}}',
              429,
              headers: {
                'date': 'Mon, 24 Aug 2026 12:00:00 GMT',
                'retry-after': ?header,
              },
            ),
          ),
          const Duration(seconds: 42),
        );
      });
    }

    test('honors an HTTP-date Retry-After before the body delay', () {
      final response = http.Response(
        '{"extras":{"wait_seconds":5}}',
        429,
        headers: {'retry-after': HttpDate.format(DateTime.utc(9999))},
      );

      expect(
        DiscourseRequestCoordinator.explicitRetryAfter(response),
        const Duration(hours: 1),
      );
    });

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
