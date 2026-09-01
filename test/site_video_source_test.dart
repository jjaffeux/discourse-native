import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_video_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
