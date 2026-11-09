import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:discourse_native/src/foundation/retry_wait.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/post_mutation_outcome.dart';
import 'package:discourse_native/src/shell/post_mutation_feedback.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/manual_scheduler.dart';

const _siteUrl = 'https://example.com';
const _cooldown = Duration(seconds: 40);

void main() {
  group('how long a sender holds', () {
    const named = Duration(seconds: 7);

    for (final scenario in [
      (
        name: 'what was named',
        failure: const WriteException(
          WriteFailure.rateLimited,
          retryAfter: named,
        ),
        wait: named,
      ),
      (
        name: 'a second when nothing was named',
        failure: const WriteException(WriteFailure.rateLimited),
        wait: const Duration(seconds: 1),
      ),
      (
        name: 'nothing for a request that never left',
        failure: const WriteException(WriteFailure.unreachable, notSent: true),
        wait: Duration.zero,
      ),
      (
        name: 'nothing for a delay already past',
        failure: const WriteException(
          WriteFailure.rateLimited,
          retryAfter: Duration(seconds: -1),
        ),
        wait: Duration.zero,
      ),
    ]) {
      test(scenario.name, () {
        expect(scenario.failure.retryWait, scenario.wait);
      });
    }

    test('stays in place only up to the inline maximum', () {
      WriteException waiting(Duration wait) =>
          WriteException(WriteFailure.rateLimited, retryAfter: wait);

      expect(waiting(maximumInlineRetryWait).canWaitInPlace, isTrue);
      expect(
        waiting(
          maximumInlineRetryWait + const Duration(milliseconds: 1),
        ).canWaitInPlace,
        isFalse,
      );
    });
  });

  group('a wait in whole seconds', () {
    for (final scenario in [
      (wait: Duration.zero, seconds: 0),
      (wait: const Duration(microseconds: 1), seconds: 1),
      (wait: const Duration(seconds: 1), seconds: 1),
      (wait: const Duration(milliseconds: 1001), seconds: 2),
    ]) {
      test('${scenario.wait} reads as ${scenario.seconds}', () {
        expect(waitSeconds(scenario.wait), scenario.seconds);
      });
    }
  });

  group('a write the site rate-limited', () {
    Future<WriteException> refuse(http.Response response) async {
      final scheduler = ManualScheduler();
      final transport = _transport(scheduler, (_) async => response);
      addTearDown(transport.close);
      try {
        await _post(transport);
      } on WriteException catch (error) {
        return error;
      }
      fail('The write should have been refused.');
    }

    test(
      'names the cooldown it started when the site named no delay',
      () async {
        final refusal = await refuse(http.Response('{}', 429));

        expect(refusal.retryAfter, _cooldown);
        expect(refusal.message, 'Too fast — try again in 40s.');
      },
    );

    test(
      'names no wait when the refusal paused nothing and timed nothing',
      () async {
        final refusal = await refuse(http.Response('{"failed":"FAILED"}', 429));

        expect(refusal.retryAfter, isNull);
        expect(refusal.message, 'Too fast — try again in a moment.');
      },
    );

    test('keeps a delay named for one action that paused nothing', () async {
      final refusal = await refuse(
        http.Response(
          '{"error_type":"rate_limit","extras":{"wait_seconds":7}}',
          429,
        ),
      );

      expect(refusal.retryAfter, const Duration(seconds: 7));
    });

    test('keeps the delay the site named over any cooldown', () async {
      final refusal = await refuse(
        http.Response('{}', 429, headers: {'retry-after': '7'}),
      );

      expect(refusal.retryAfter, const Duration(seconds: 7));
    });

    test(
      'a retry-after on another failure is reported, not defaulted',
      () async {
        final named = await refuse(
          http.Response('{}', 503, headers: {'retry-after': '7'}),
        );
        final unnamed = await refuse(http.Response('{}', 503));

        expect(named.retryAfter, const Duration(seconds: 7));
        expect(unnamed.retryAfter, isNull);
      },
    );
  });

  group('a wait shorter than a second', () {
    const wait = Duration(milliseconds: 400);

    test('reads as one second in a write failure', () {
      const refusal = WriteException(
        WriteFailure.rateLimited,
        statusCode: 429,
        retryAfter: wait,
      );

      expect(refusal.message, 'Too fast — try again in 1s.');
    });

    testWidgets('reads as one second in post mutation feedback', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (built) {
            context = built;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(
        postMutationMessage(
          context,
          const PostMutationRefused(
            PostMutationProblem(
              PostMutationProblemKind.rateLimited,
              retryAfter: wait,
            ),
          ),
        ),
        'Too fast — try again in 1s.',
      );
    });

    test('reads as one second in a refused upload', () {
      const refusal = ComposerUploadException(
        'Rejected',
        statusCode: 429,
        retryAfter: wait,
      );

      expect(
        refusal.displayMessage,
        'Too many uploads. Try again in 1 second.',
      );
    });
  });
}

Future<void> _post(DiscourseTransport transport) => transport.write(
  Uri.parse('$_siteUrl/posts.json'),
  siteUrl: _siteUrl,
  method: 'POST',
  apiKey: 'key',
  body: const {'raw': 'hello'},
);

DiscourseTransport _transport(
  ManualScheduler scheduler,
  Future<http.Response> Function(http.Request) send,
) => DiscourseTransport(
  SafeHttpClient.owned(MockClient(send)),
  const Duration(seconds: 1),
  1024,
  coordinator: DiscourseRequestCoordinator(
    defaultRateLimitCooldown: _cooldown,
    cooldownFactory: () => OriginCooldown(
      clock: scheduler.now,
      timerFactory: scheduler.createTimer,
    ),
  ),
);
