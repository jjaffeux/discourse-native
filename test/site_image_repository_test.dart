import 'dart:async';

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void main() {
  const siteUrl = 'https://forum.example';
  const secureUrl = '$siteUrl/secure-uploads/original/image.png';

  test('authenticates the forum hop but never a CDN redirect', () async {
    final credentials = FakeApiCredentialReader()
      ..keys[siteUrl] = 'account-key';
    final requests = <http.Request>[];
    final repository = SiteImageRepository(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'forum.example') {
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://objects.example/signed/image.png?token=x',
              'cache-control': 'private, no-store',
            },
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    addTearDown(repository.dispose);

    final image = await repository.load(siteUrl: siteUrl, url: secureUrl);

    expect(image?.bytes, orderedEquals([1, 2, 3]));
    expect(image?.isAnimated, isFalse);
    expect(requests, hasLength(2));
    expect(requests.first.followRedirects, isFalse);
    expect(requests.first.headers['User-Api-Key'], 'account-key');
    expect(requests.first.headers['User-Api-Client-Id'], 'test-client');
    expect(requests.last.url.host, 'objects.example');
    expect(requests.last.headers, isNot(contains('User-Api-Key')));
    expect(requests.last.headers, isNot(contains('User-Api-Client-Id')));
  });

  test('recognizes animated image responses', () async {
    final repository = SiteImageRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('typed')) {
          return http.Response.bytes(
            [1],
            200,
            headers: {'content-type': 'image/gif; charset=binary'},
          );
        }
        if (request.url.path.endsWith('signed')) {
          return http.Response.bytes('GIF89a'.codeUnits, 200);
        }
        return http.Response.bytes([
          ...'RIFF'.codeUnits,
          13,
          0,
          0,
          0,
          ...'WEBP'.codeUnits,
          ...'VP8X'.codeUnits,
          1,
          0,
          0,
          0,
          0x02,
        ], 200);
      }),
    );
    addTearDown(repository.dispose);

    final typed = await repository.load(
      siteUrl: siteUrl,
      url: '$siteUrl/typed',
    );
    final signed = await repository.load(
      siteUrl: siteUrl,
      url: '$siteUrl/signed',
    );
    final webp = await repository.load(
      siteUrl: siteUrl,
      url: '$siteUrl/animated-webp',
    );

    expect(typed?.isAnimated, isTrue);
    expect(signed?.isAnimated, isTrue);
    expect(webp?.isAnimated, isTrue);
  });

  test('does not attach forum credentials to an external image', () async {
    late http.Request sent;
    final credentials = FakeApiCredentialReader()
      ..keys[siteUrl] = 'account-key';
    final repository = SiteImageRepository(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      client: MockClient((request) async {
        sent = request;
        return http.Response.bytes([1], 200);
      }),
    );
    addTearDown(repository.dispose);

    await repository.load(
      siteUrl: siteUrl,
      url: 'https://images.example/hotlinked.png',
    );

    expect(sent.headers, isNot(contains('User-Api-Key')));
    expect(sent.headers, isNot(contains('User-Api-Client-Id')));
  });

  test('does not throttle authenticated media requests', () async {
    final credentials = FakeApiCredentialReader()
      ..keys[siteUrl] = 'account-key';
    final gate = Completer<void>();
    var active = 0;
    var peak = 0;
    final repository = SiteImageRepository(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      client: MockClient((request) async {
        active++;
        peak = peak > active ? peak : active;
        await gate.future;
        active--;
        return http.Response.bytes([1], 200);
      }),
    );
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      repository.dispose();
    });

    final loads = [
      for (var index = 0; index < 20; index++)
        repository.load(
          siteUrl: siteUrl,
          url: '$siteUrl/secure-uploads/original/$index.png',
        ),
    ];

    for (var attempt = 0; attempt < 20 && peak < 20; attempt++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(peak, 20);

    gate.complete();
    expect(await Future.wait(loads), everyElement(isNotNull));
  });

  test('an invalidated account cannot publish or retain stale bytes', () async {
    final credentials = FakeApiCredentialReader()..keys[siteUrl] = 'old-key';
    final lifecycle = SiteLifecycle();
    final firstResponse = Completer<http.Response>();
    final firstRequestStarted = Completer<void>();
    final keys = <String?>[];
    var requestCount = 0;
    final repository = SiteImageRepository(
      credentials: credentials,
      lifecycle: lifecycle,
      client: MockClient((request) {
        keys.add(request.headers['User-Api-Key']);
        requestCount++;
        if (requestCount == 1) {
          firstRequestStarted.complete();
          return firstResponse.future;
        }
        return Future.value(http.Response.bytes([2], 200));
      }),
    );
    addTearDown(repository.dispose);

    final stale = repository.load(siteUrl: siteUrl, url: secureUrl);
    await firstRequestStarted.future;

    lifecycle.invalidate(siteUrl);
    repository.forget(siteUrl);
    credentials.keys[siteUrl] = 'new-key';
    firstResponse.complete(http.Response.bytes([1], 200));

    expect(await stale, isNull);
    final fresh = await repository.load(siteUrl: siteUrl, url: secureUrl);
    expect(fresh?.bytes, orderedEquals([2]));
    expect(keys, ['old-key', 'new-key']);
  });
}
