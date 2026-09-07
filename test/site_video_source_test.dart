import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_video_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/manual_scheduler.dart';

void main() {
  const siteUrl = 'https://meta.discourse.org';

  test('public and cross-origin URLs need no credential probe', () async {
    var requests = 0;
    final resolver = SiteVideoSourceResolver(
      credentials: const _Credentials(apiKey: 'secret'),
      lifecycle: SiteLifecycle(),
      client: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      }),
    );
    addTearDown(resolver.close);

    final public = await resolver.resolve(
      siteUrl: siteUrl,
      url: Uri.parse('$siteUrl/uploads/demo.mp4'),
    );
    final cdn = await resolver.resolve(
      siteUrl: siteUrl,
      url: Uri.parse('https://cdn.example.com/secure-uploads/demo.mp4'),
    );

    expect(public.url, Uri.parse('$siteUrl/uploads/demo.mp4'));
    expect(
      cdn.url,
      Uri.parse('https://cdn.example.com/secure-uploads/demo.mp4'),
    );
    expect(requests, 0);
  });

  test(
    'credentials stay on the forum while signed redirects are resolved',
    () async {
      final requests = <http.Request>[];
      final resolver = SiteVideoSourceResolver(
        credentials: const _Credentials(
          apiKey: 'secret',
          clientIdValue: 'client',
        ),
        lifecycle: SiteLifecycle(),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.host == 'meta.discourse.org') {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://cdn.example.com/signed/demo.mp4'},
            );
          }
          return http.Response('', 200);
        }),
      );
      addTearDown(resolver.close);

      final source = await resolver.resolve(
        siteUrl: siteUrl,
        url: Uri.parse('$siteUrl/secure-uploads/original/demo.mp4'),
      );

      expect(source.url, Uri.parse('https://cdn.example.com/signed/demo.mp4'));
      expect(requests, hasLength(2));
      expect(requests.first.method, 'HEAD');
      expect(requests.first.followRedirects, isFalse);
      expect(requests.first.headers['User-Api-Key'], 'secret');
      expect(requests.first.headers['User-Api-Client-Id'], 'client');
      expect(requests.last.headers, isNot(contains('User-Api-Key')));
    },
  );

  test('same-origin protected source is not handed to a media stack', () async {
    final resolver = SiteVideoSourceResolver(
      credentials: const _Credentials(apiKey: 'secret', clientIdValue: ''),
      lifecycle: SiteLifecycle(),
      client: MockClient((_) async => http.Response('', 200)),
    );
    addTearDown(resolver.close);

    await expectLater(
      resolver.resolve(
        siteUrl: siteUrl,
        url: Uri.parse('$siteUrl/secure-uploads/original/demo.mp4'),
      ),
      throwsA(isA<SiteVideoSourceRequiresAuthenticationException>()),
    );
  });

  test('rejects downgrade redirects', () async {
    final resolver = SiteVideoSourceResolver(
      credentials: const _Credentials(apiKey: 'secret'),
      lifecycle: SiteLifecycle(),
      client: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'http://cdn.example.com/demo.mp4'},
        ),
      ),
    );
    addTearDown(resolver.close);

    expect(
      resolver.resolve(
        siteUrl: siteUrl,
        url: Uri.parse('$siteUrl/secure-uploads/original/demo.mp4'),
      ),
      throwsA(isA<UnsafeHttpTransportException>()),
    );
  });

  test('an invalidated account cannot finish resolving media', () async {
    final credentials = _DelayedCredentials();
    final lifecycle = SiteLifecycle();
    final resolver = SiteVideoSourceResolver(
      credentials: credentials,
      lifecycle: lifecycle,
      client: MockClient((_) async => http.Response('', 200)),
    );
    addTearDown(resolver.close);

    final resolving = resolver.resolve(
      siteUrl: siteUrl,
      url: Uri.parse('$siteUrl/secure-uploads/original/demo.mp4'),
    );
    await Future<void>.delayed(Duration.zero);
    lifecycle.invalidate(siteUrl);
    credentials.apiKey.complete('stale-secret');

    await expectLater(resolving, throwsStateError);
  });

  test('times out a stalled credential lookup', () async {
    final credentials = _DelayedCredentials();
    final resolver = SiteVideoSourceResolver(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      requestTimeout: const Duration(milliseconds: 10),
      client: MockClient((_) async => http.Response('', 200)),
    );
    addTearDown(resolver.close);

    await expectLater(
      resolver.resolve(
        siteUrl: siteUrl,
        url: Uri.parse('$siteUrl/secure-uploads/original/demo.mp4'),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('times out and aborts a stalled redirect probe', () async {
    final abortObserved = Completer<void>();
    final resolver = SiteVideoSourceResolver(
      credentials: const _Credentials(apiKey: 'secret'),
      lifecycle: SiteLifecycle(),
      requestTimeout: const Duration(milliseconds: 10),
      client: MockClient.streaming((request, _) async {
        final abortTrigger = (request as http.Abortable).abortTrigger!;
        await abortTrigger;
        abortObserved.complete();
        throw http.RequestAbortedException(request.url);
      }),
    );
    addTearDown(resolver.close);

    await expectLater(
      resolver.resolve(
        siteUrl: siteUrl,
        url: Uri.parse('$siteUrl/secure-uploads/original/demo.mp4'),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await abortObserved.future;
  });

  for (final timeout in [false, true]) {
    test(
      'cancels a probe body arriving after ${timeout ? 'its deadline' : 'closure'}',
      () async {
        final started = Completer<void>();
        final headers = Completer<http.StreamedResponse>();
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        addTearDown(() async {
          if (!cancelled) await body.stream.listen(null).cancel();
          await body.close();
        });
        final scheduler = ManualScheduler();
        final resolver = SiteVideoSourceResolver(
          credentials: const _Credentials(apiKey: 'secret'),
          lifecycle: SiteLifecycle(),
          requestTimeout: const Duration(minutes: 1),
          client: MockClient.streaming((request, _) {
            started.complete();
            return headers.future;
          }),
        );
        addTearDown(resolver.close);
        final resolving = runZoned(
          () => resolver.resolve(
            siteUrl: siteUrl,
            url: Uri.parse('$siteUrl/secure-uploads/demo.mp4'),
          ),
          zoneSpecification: ZoneSpecification(
            createTimer: (_, _, zone, duration, callback) =>
                scheduler.createTimer(duration, zone.bindCallback(callback)),
          ),
        );
        await started.future;
        final stopped = expectLater(
          resolving,
          timeout ? throwsA(isA<TimeoutException>()) : throwsStateError,
        );
        if (timeout) {
          scheduler.advance(const Duration(minutes: 1));
        } else {
          resolver.close();
        }
        await stopped;

        headers.complete(http.StreamedResponse(body.stream, 200));
        // Drain the late-response continuation queued by completing headers.
        await Future<void>.delayed(Duration.zero);
        expect(cancelled, isTrue);
      },
    );
  }

  test('closing aborts a stalled redirect probe', () async {
    final requestStarted = Completer<void>();
    final resolver = SiteVideoSourceResolver(
      credentials: const _Credentials(apiKey: 'secret'),
      lifecycle: SiteLifecycle(),
      client: MockClient.streaming((request, _) async {
        requestStarted.complete();
        await (request as http.Abortable).abortTrigger!;
        throw http.RequestAbortedException(request.url);
      }),
    );

    final resolving = resolver.resolve(
      siteUrl: siteUrl,
      url: Uri.parse('$siteUrl/secure-uploads/original/demo.mp4'),
    );
    await requestStarted.future;
    final elapsed = Stopwatch()..start();
    resolver.close();

    await expectLater(resolving, throwsA(anything));
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('closing releases a stalled credential deadline immediately', () async {
    final scheduler = ManualScheduler();
    final credentials = _DelayedCredentials();
    final resolver = SiteVideoSourceResolver(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      client: MockClient((_) async => http.Response('', 200)),
    );
    addTearDown(resolver.close);
    final resolving = runZoned(
      () => resolver.resolve(
        siteUrl: siteUrl,
        url: Uri.parse('$siteUrl/secure-uploads/demo.mp4'),
      ),
      zoneSpecification: ZoneSpecification(
        createTimer: (_, _, zone, duration, callback) =>
            scheduler.createTimer(duration, zone.bindCallback(callback)),
      ),
    );
    expect(scheduler.activeTimerCount, 1);
    final stopped = expectLater(resolving, throwsStateError);

    resolver.close();
    await stopped;

    expect(scheduler.activeTimerCount, 0);
    credentials.apiKey.completeError(StateError('late credential failure'));
    await pumpEventQueue();
  });

  test('closing does not retain and abort completed probe requests', () async {
    final aborted = <Uri>[];
    final resolver = SiteVideoSourceResolver(
      credentials: const _Credentials(apiKey: 'secret'),
      lifecycle: SiteLifecycle(),
      client: MockClient.streaming((request, _) async {
        unawaited(
          (request as http.Abortable).abortTrigger!.then((_) {
            aborted.add(request.url);
          }),
        );
        return http.StreamedResponse(
          const Stream.empty(),
          request.url.host == 'meta.discourse.org' ? 302 : 200,
          headers: {'location': 'https://cdn.example.com/demo.mp4'},
        );
      }),
    );

    await resolver.resolve(
      siteUrl: siteUrl,
      url: Uri.parse('$siteUrl/secure-uploads/demo.mp4'),
    );
    resolver.close();
    await pumpEventQueue();

    expect(aborted, isEmpty);
  });

  for (final timeout in [false, true]) {
    test(
      '${timeout ? 'a deadline' : 'closing'} interrupts a stalled probe-body cancellation',
      () async {
        final scheduler = ManualScheduler();
        final cancelling = Completer<void>();
        final releaseCancellation = Completer<void>();
        final body = StreamController<List<int>>(
          onCancel: () {
            cancelling.complete();
            return releaseCancellation.future;
          },
        );
        final resolver = SiteVideoSourceResolver(
          credentials: const _Credentials(apiKey: 'secret'),
          lifecycle: SiteLifecycle(),
          client: MockClient.streaming(
            (request, _) async => http.StreamedResponse(body.stream, 200),
          ),
        );
        addTearDown(resolver.close);
        var stopped = false;
        final resolving =
            runZoned(
              () => resolver.resolve(
                siteUrl: siteUrl,
                url: Uri.parse('$siteUrl/secure-uploads/demo.mp4'),
              ),
              zoneSpecification: ZoneSpecification(
                createTimer: (_, _, zone, duration, callback) => scheduler
                    .createTimer(duration, zone.bindCallback(callback)),
              ),
            ).then<void>(
              (_) {
                fail(
                  'An interrupted resolver must not publish a video source.',
                );
              },
              onError: (Object error) {
                expect(error, timeout ? isA<TimeoutException>() : isStateError);
                stopped = true;
              },
            );
        await cancelling.future;

        if (timeout) {
          scheduler.advance(resolver.requestTimeout);
        } else {
          resolver.close();
        }
        await pumpEventQueue();
        try {
          expect(stopped, isTrue);
          expect(scheduler.activeTimerCount, 0);
        } finally {
          releaseCancellation.complete();
          await resolving;
          await body.close();
        }
      },
    );
  }
}

final class _Credentials implements ApiCredentialReader {
  const _Credentials({required this.apiKey, this.clientIdValue = 'client'});

  final String? apiKey;
  final String clientIdValue;

  @override
  Future<String?> apiKeyFor(String siteUrl) async => apiKey;

  @override
  Future<String> clientId() async => clientIdValue;
}

final class _DelayedCredentials implements ApiCredentialReader {
  final Completer<String?> apiKey = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) => apiKey.future;

  @override
  Future<String> clientId() async => 'client';
}
