import 'dart:async';
import 'dart:typed_data';

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;

import 'support/fakes.dart';

void main() {
  const siteUrl = 'https://forum.example';
  const secureUrl = '$siteUrl/secure-uploads/original/image.png';

  test(
    'credentials follow the exact forum origin across redirect hops',
    () async {
      final hops = [
        '$siteUrl/secure-uploads/first.png',
        '$siteUrl:444/external.png',
        '$siteUrl/secure-uploads/back.png',
        'https://cdn.example/signed.png',
      ];
      final requests = <http.Request>[];
      Future<http.Response> respond(http.Request request) async {
        final index = requests.length;
        requests.add(request);
        return index == hops.length - 1
            ? http.Response.bytes([1], 200)
            : http.Response('', 302, headers: {'location': hops[index + 1]});
      }

      final credentials = FakeApiCredentialReader()..keys[siteUrl] = 'secret';
      final repository = SiteImageRepository(
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        client: MockClient(respond),
      );
      addTearDown(repository.dispose);
      expect(
        (await repository.load(siteUrl: siteUrl, url: hops.first))?.bytes,
        [1],
      );
      expect(requests.map((r) => r.url.toString()), hops);
      expect(requests.map((r) => r.headers['User-Api-Key']), [
        'secret',
        null,
        'secret',
        null,
      ]);
      expect(requests.map((r) => r.headers['User-Api-Client-Id']), [
        'test-client',
        null,
        'test-client',
        null,
      ]);
    },
  );

  test(
    'anonymous images skip the client ID read and still fetch bytes',
    () async {
      final credentials = _HeldImageCredentials();
      final requests = <http.Request>[];
      final repository = SiteImageRepository(
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes([1], 200);
        }),
      );
      addTearDown(repository.dispose);

      expect((await repository.load(siteUrl: siteUrl, url: secureUrl))?.bytes, [
        1,
      ]);
      expect(credentials.clientIdReads, 0);
      expect(requests.single.headers, isNot(contains('User-Api-Key')));
      expect(requests.single.headers, isNot(contains('User-Api-Client-Id')));
    },
  );

  for (final clientId in ['', 'test-client']) {
    test(
      'authenticates the forum hop but never a CDN redirect (client ID: $clientId)',
      () async {
        final credentials = FakeApiCredentialReader(clientIdValue: clientId)
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
                  'location': 'https://objects.example/signed?token=x',
                  'cache-control': 'private, no-store',
                  'content-type': 'image/jpeg',
                },
              );
            }
            return http.Response.bytes(
              image.encodeBmp(image.Image(width: 1, height: 1)),
              200,
              headers: {'content-type': 'image/bmp'},
            );
          }),
        );
        addTearDown(repository.dispose);

        final loaded = await repository.load(siteUrl: siteUrl, url: secureUrl);

        expect(loaded?.mediaType, SiteImageMediaType.bmp);
        expect(
          loaded?.bytes,
          orderedEquals(image.encodeBmp(image.Image(width: 1, height: 1))),
        );
        expect(loaded?.isAnimated, isFalse);
        expect(
          repository.cached(siteUrl: siteUrl, url: secureUrl)?.mediaType,
          SiteImageMediaType.bmp,
        );
        expect(
          (await repository.load(siteUrl: siteUrl, url: secureUrl))?.mediaType,
          SiteImageMediaType.bmp,
        );
        expect(requests, hasLength(2));
        expect(requests.first.followRedirects, isFalse);
        expect(requests.first.headers['User-Api-Key'], 'account-key');
        expect(
          requests.first.headers['User-Api-Client-Id'],
          clientId.isEmpty ? null : clientId,
        );
        expect(requests.last.url.host, 'objects.example');
        expect(requests.last.headers, isNot(contains('User-Api-Key')));
        expect(requests.last.headers, isNot(contains('User-Api-Client-Id')));
      },
    );
  }

  for (final (format, bytes, contentType, expected) in [
    (
      'PNG',
      image.encodePng(image.Image(width: 1, height: 1)),
      'image/svg+xml',
      SiteImageMediaType.png,
    ),
    (
      'JPEG',
      image.encodeJpg(image.Image(width: 1, height: 1)),
      null,
      SiteImageMediaType.jpeg,
    ),
    (
      'GIF',
      image.encodeGif(image.Image(width: 1, height: 1)),
      null,
      SiteImageMediaType.gif,
    ),
    (
      'WebP',
      image.encodeWebP(image.Image(width: 1, height: 1)),
      null,
      SiteImageMediaType.webp,
    ),
    (
      'TIFF',
      image.encodeTiff(image.Image(width: 1, height: 1)),
      null,
      SiteImageMediaType.tiff,
    ),
    (
      'BMP',
      image.encodeBmp(image.Image(width: 1, height: 1)),
      'IMAGE/BMP; charset=binary',
      SiteImageMediaType.bmp,
    ),
    (
      'SVG',
      Uint8List.fromList('<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits),
      null,
      SiteImageMediaType.svg,
    ),
    (
      'unknown',
      Uint8List.fromList([1, 2, 3]),
      'application/octet-stream',
      null,
    ),
  ]) {
    test(
      'retains $format response metadata consistently with SVG rendering',
      () async {
        var requests = 0;
        final repository = SiteImageRepository(
          credentials: FakeApiCredentialReader(),
          lifecycle: SiteLifecycle(),
          client: MockClient((_) async {
            requests++;
            return http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': ?contentType},
            );
          }),
        );
        addTearDown(repository.dispose);
        final loaded = await repository.load(siteUrl: siteUrl, url: secureUrl);
        expect(loaded?.mediaType, expected);
        expect(loaded?.isSvg, expected == SiteImageMediaType.svg);
        final cached = repository.cached(siteUrl: siteUrl, url: secureUrl);
        expect(cached?.mediaType, expected);
        expect(cached?.bytes, orderedEquals(bytes));
        final reloaded = await repository.load(
          siteUrl: siteUrl,
          url: secureUrl,
        );
        expect(reloaded?.mediaType, expected);
        expect(reloaded?.isSvg, expected == SiteImageMediaType.svg);
        expect(requests, 1);
      },
    );
  }

  for (final (brand, contentType, expected) in [
    ('avif', 'IMAGE/AVIF; charset=binary', SiteImageMediaType.avif),
    ('heic', 'image/heic', SiteImageMediaType.heic),
    ('mif1', 'image/png', SiteImageMediaType.heif),
  ]) {
    test(
      'a generic HEIF container retains its declared $brand image type',
      () async {
        final bytes = [
          0,
          0,
          0,
          24,
          ...'ftypmif1'.codeUnits,
          0,
          0,
          0,
          0,
          ...'mif1'.codeUnits,
          ...brand.codeUnits,
        ];
        final repository = SiteImageRepository(
          credentials: FakeApiCredentialReader(),
          lifecycle: SiteLifecycle(),
          client: MockClient(
            (_) async => http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': contentType},
            ),
          ),
        );
        addTearDown(repository.dispose);
        final loaded = await repository.load(siteUrl: siteUrl, url: secureUrl);
        expect(loaded?.mediaType, expected);
      },
    );
  }

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

  test('bounds authenticated transfers until their bodies finish', () async {
    final credentials = FakeApiCredentialReader()
      ..keys[siteUrl] = 'account-key';
    final client = _HeldImageBodiesClient();
    final repository = SiteImageRepository(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      client: client,
    );
    addTearDown(() {
      client.releaseBodies();
      repository.dispose();
    });

    final loads = [
      for (var index = 0; index < 20; index++)
        repository.load(
          siteUrl: siteUrl,
          url: '$siteUrl/secure-uploads/original/$index.png',
        ),
    ];
    await Future<void>.delayed(Duration.zero);

    expect(client.requests, hasLength(8));
    expect(client.active, 8);
    expect(client.peak, 8);

    client.releaseBodies();
    final images = await Future.wait(loads);
    expect(images.map((image) => image?.bytes), everyElement([1, 2, 3]));
    expect(client.requests, hasLength(20));
    expect(client.peak, 8);
    expect(client.active, 0);
  });

  test('bounds aggregate transfers across account sessions', () async {
    const sites = [
      'https://a.example',
      'https://b.example',
      'https://c.example',
    ];
    final credentials = FakeApiCredentialReader();
    for (final site in sites) {
      credentials.keys[site] = 'key-$site';
    }
    final client = _HeldImageBodiesClient();
    final repository = SiteImageRepository(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      client: client,
    );
    addTearDown(() {
      client.releaseBodies();
      repository.dispose();
    });

    final loads = [
      for (final site in sites)
        for (var index = 0; index < 12; index++)
          repository.load(siteUrl: site, url: '$site/$index.png'),
    ];
    await Future<void>.delayed(Duration.zero);

    expect(client.requests, hasLength(16));
    expect(client.active, 16);
    expect(client.peak, 16);
    expect(client.peakByOrigin.values, everyElement(lessThanOrEqualTo(8)));

    client.releaseBodies();
    final images = await Future.wait(loads);
    expect(images.map((image) => image?.bytes), everyElement([1, 2, 3]));
    expect(client.requests, hasLength(36));
    expect(client.peak, 16);
    expect(client.peakByOrigin.values, everyElement(lessThanOrEqualTo(8)));
    expect(client.active, 0);
  });

  test('shares a CDN origin transfer limit across account sessions', () async {
    const sites = ['https://a.example', 'https://b.example'];
    final credentials = FakeApiCredentialReader();
    for (final site in sites) {
      credentials.keys[site] = 'key-$site';
    }
    final client = _HeldImageBodiesClient();
    final repository = SiteImageRepository(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      client: client,
    );
    addTearDown(() {
      client.releaseBodies();
      repository.dispose();
    });

    final loads = [
      for (var account = 0; account < sites.length; account++)
        for (var index = 0; index < 12; index++)
          repository.load(
            siteUrl: sites[account],
            url: 'https://cdn.example/$account/$index.png',
          ),
    ];
    await Future<void>.delayed(Duration.zero);

    expect(client.requests, hasLength(8));
    expect(client.active, 8);
    expect(client.peakByOrigin, {'https://cdn.example': 8});

    client.releaseBodies();
    final images = await Future.wait(loads);
    expect(images.map((image) => image?.bytes), everyElement([1, 2, 3]));
    expect(client.requests, hasLength(24));
    expect(client.peak, 8);
    expect(client.active, 0);
  });

  test(
    'finishes a gallery larger than the coordinator backlog limit',
    () async {
      final client = _HeldImageBodiesClient();
      final repository = SiteImageRepository(
        credentials: FakeApiCredentialReader(),
        lifecycle: SiteLifecycle(),
        client: client,
      );
      addTearDown(() {
        client.releaseBodies();
        repository.dispose();
      });

      final loads = [
        for (var index = 0; index < 96; index++)
          repository.load(siteUrl: siteUrl, url: '$siteUrl/$index.png'),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, hasLength(8));

      client.releaseBodies();
      final images = await Future.wait(loads);
      expect(images.map((image) => image?.bytes), everyElement([1, 2, 3]));
      expect(client.requests, hasLength(96));
      expect(client.peak, 8);
      expect(client.active, 0);
    },
  );

  testWidgets('local backlog outlives individual download timeouts', (
    tester,
  ) async {
    var requested = 0;
    final repository = SiteImageRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
      client: MockClient.streaming((request, _) async {
        requested++;
        return http.StreamedResponse(
          Stream.fromFuture(
            Future<List<int>>.delayed(
              const Duration(seconds: 8),
              () => [1, 2, 3],
            ),
          ),
          200,
        );
      }),
    );
    addTearDown(repository.dispose);
    List<SiteImageBytes?>? images;
    final loads = [
      for (var index = 0; index < 24; index++)
        repository.load(siteUrl: siteUrl, url: '$siteUrl/$index.png'),
    ];
    unawaited(Future.wait(loads).then((result) => images = result));
    await tester.pump();
    expect(requested, 8);
    await tester.pump(const Duration(seconds: 8));
    expect(requested, 16);
    expect(images, isNull);
    await tester.pump(const Duration(seconds: 8));
    expect(requested, 24);
    await tester.pump(const Duration(seconds: 8));
    expect(images, hasLength(24));
    expect(images!.map((image) => image?.bytes), everyElement([1, 2, 3]));
  });

  test('retiring queued images leaves other account sessions open', () async {
    const retiredSite = 'https://retired.example';
    const survivorSite = 'https://survivor.example';
    final client = _HeldImageBodiesClient();
    final repository = SiteImageRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
      client: client,
    );
    addTearDown(() {
      client.releaseBodies();
      repository.dispose();
    });

    final active = [
      for (var index = 0; index < 8; index++)
        repository.load(
          siteUrl: siteUrl,
          url: 'https://cdn.example/active/$index.png',
        ),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(client.requests, hasLength(8));
    final retired = [
      for (var index = 0; index < 12; index++)
        repository.load(
          siteUrl: retiredSite,
          url: 'https://cdn.example/retired/$index.png',
        ),
    ];
    final survivors = [
      for (var index = 0; index < 4; index++)
        repository.load(
          siteUrl: survivorSite,
          url: 'https://cdn.example/survivor/$index.png',
        ),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(client.requests, hasLength(8));

    repository.forget(retiredSite);
    expect(await Future.wait(retired), everyElement(isNull));
    client.releaseBodies();

    final images = await Future.wait([...active, ...survivors]);
    expect(images.map((image) => image?.bytes), everyElement([1, 2, 3]));
    expect(client.requests, hasLength(12));
    expect(
      client.requests.where(
        (request) => request.url.path.startsWith('/retired/'),
      ),
      isEmpty,
    );
    final later = await repository.load(
      siteUrl: survivorSite,
      url: 'https://cdn.example/survivor/later.png',
    );
    expect(later?.bytes, [1, 2, 3]);
    expect(client.peak, 8);
    expect(client.active, 0);
  });

  test(
    'different accounts keep identical external image requests isolated',
    () async {
      const otherSite = 'https://other.example';
      const externalUrl = 'https://images.example/shared.png';
      final credentials = FakeApiCredentialReader()
        ..keys[siteUrl] = 'first-key'
        ..keys[otherSite] = 'second-key';
      final client = _ControlledImageClient(honorAbort: true);
      final repository = SiteImageRepository(
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        client: client,
      );
      addTearDown(repository.dispose);

      final first = repository.load(siteUrl: siteUrl, url: externalUrl);
      await client.started.future;
      final second = repository.load(siteUrl: otherSite, url: externalUrl);
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, hasLength(2));
      client.response.complete(http.StreamedResponse(Stream.value([1]), 200));

      expect((await first)?.bytes, [1]);
      expect((await second)?.bytes, [2]);
      expect(repository.cached(siteUrl: siteUrl, url: externalUrl)?.bytes, [1]);
      expect(repository.cached(siteUrl: otherSite, url: externalUrl)?.bytes, [
        2,
      ]);
      for (final request in client.requests) {
        expect(request.url.toString(), externalUrl);
        expect(request.headers, isNot(contains('User-Api-Key')));
        expect(request.headers, isNot(contains('User-Api-Client-Id')));
      }
    },
  );

  test(
    'redirected CDN cooldown is shared without closing other origins',
    () async {
      final requests = <Uri>[];
      final repository = SiteImageRepository(
        credentials: FakeApiCredentialReader()..keys[siteUrl] = 'account-key',
        lifecycle: SiteLifecycle(),
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.origin == siteUrl) {
            return http.Response(
              '',
              302,
              headers: {'location': 'https://cdn.example/rate-limited.png'},
            );
          }
          if (request.url.host == 'cdn.example') {
            return http.Response('', 429, headers: {'retry-after': '60'});
          }
          return http.Response.bytes([1], 200);
        }),
      );
      addTearDown(repository.dispose);

      expect(await repository.load(siteUrl: siteUrl, url: secureUrl), isNull);
      repository.forget(siteUrl);
      expect(
        await repository.load(siteUrl: siteUrl, url: '$siteUrl/other.png'),
        isNull,
      );
      expect(
        await repository.load(
          siteUrl: 'https://other.example',
          url: 'https://cdn.example/other.png',
        ),
        isNull,
      );
      expect(
        (await repository.load(
          siteUrl: 'https://other.example',
          url: 'https://other.example/image.png',
        ))?.bytes,
        [1],
      );
      expect(requests.map((url) => url.host), [
        'forum.example',
        'cdn.example',
        'other.example',
      ]);
    },
  );

  test('forget suppresses a cached result already awaiting delivery', () async {
    final repository = SiteImageRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
      client: MockClient((_) async => http.Response.bytes([1], 200)),
    );
    addTearDown(repository.dispose);
    await repository.load(siteUrl: siteUrl, url: secureUrl);
    final pending = repository.load(siteUrl: siteUrl, url: secureUrl);
    repository.forget(siteUrl);
    expect(await pending, isNull);
  });

  for (final stage in ['API key', 'client ID']) {
    for (final abandon in [
      'replacement',
      'forget',
      'invalidation',
      'dispose',
    ]) {
      for (final outcome in ['success', 'error']) {
        test(
          '$abandon suppresses late $stage $outcome during opening',
          () async {
            final credentials = _HeldImageCredentials()
              ..keys[siteUrl] = 'old-key';
            final held = credentials.hold(stage);
            final lifecycle = SiteLifecycle();
            final requests = <http.Request>[];
            final repository = SiteImageRepository(
              credentials: credentials,
              lifecycle: lifecycle,
              client: MockClient((request) async {
                requests.add(request);
                return http.Response.bytes([2], 200);
              }),
            );
            addTearDown(() {
              repository.dispose();
              held.release();
            });
            final stale = repository.load(siteUrl: siteUrl, url: secureUrl);
            await held.started.future;

            switch (abandon) {
              case 'replacement' || 'invalidation':
                lifecycle.invalidate(siteUrl);
              case 'forget':
                // The lease remains current; forget must retire the opening.
                repository.forget(siteUrl);
              case 'dispose':
                repository.dispose();
            }
            final replaces = abandon == 'replacement' || abandon == 'forget';
            SiteImageBytes? fresh;
            if (replaces) {
              credentials.keys[siteUrl] = 'new-key';
              final pending = repository.load(siteUrl: siteUrl, url: secureUrl);
              expect(credentials.keyReads, [siteUrl, siteUrl]);
              fresh = await pending;
              expect(fresh?.bytes, [2]);
            }

            if (outcome == 'error') {
              held.result.completeError(StateError('retired credentials'));
            } else {
              held.result.complete('old-credential');
            }
            expect(await stale, isNull);

            // A retired key lookup must not continue into the client ID reader.
            expect(
              credentials.clientIdReads,
              (stage == 'client ID' ? 1 : 0) + (replaces ? 1 : 0),
            );
            expect(
              repository.cached(siteUrl: siteUrl, url: secureUrl),
              same(fresh),
            );
            if (replaces) {
              expect(
                await repository.load(siteUrl: siteUrl, url: secureUrl),
                same(fresh),
              );
            }
            expect(requests.map(_requestIdentity), [
              if (replaces) ('GET', secureUrl, 'new-key', 'new-client'),
            ]);
          },
        );
      }
    }

    test(
      'retired $stage openings cannot remove a third opening or another site',
      () async {
        const otherSite = 'https://other.example';
        const otherUrl = '$otherSite/image.png';
        final credentials = _HeldImageCredentials()
          ..keys[siteUrl] = 'newest-key'
          ..keys[otherSite] = 'other-key';
        final held = <_HeldImageCredential>[];
        final lifecycle = SiteLifecycle();
        final requests = <http.Request>[];
        final repository = SiteImageRepository(
          credentials: credentials,
          lifecycle: lifecycle,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response.bytes([
              request.url.host == 'other.example' ? 3 : 2,
            ], 200);
          }),
        );
        addTearDown(() {
          repository.dispose();
          for (final lookup in held) {
            lookup.release();
          }
        });

        final retired = <Future<SiteImageBytes?>>[];
        for (var index = 0; index < 2; index++) {
          lifecycle.invalidate(siteUrl);
          held.add(credentials.hold(stage));
          retired.add(repository.load(siteUrl: siteUrl, url: secureUrl));
          expect(credentials.keyReads, List.filled(index + 1, siteUrl));
          await held.last.started.future;
        }
        final other = await repository.load(siteUrl: otherSite, url: otherUrl);
        expect(other?.bytes, [3]);

        lifecycle.invalidate(siteUrl);
        held.add(credentials.hold(stage));
        final newest = repository.load(siteUrl: siteUrl, url: secureUrl);
        expect(credentials.keyReads, [siteUrl, siteUrl, otherSite, siteUrl]);
        await held.last.started.future;

        held[1].result.completeError(StateError('retired credentials'));
        expect(await retired[1], isNull);
        held[0].result.complete('old-credential');
        expect(await retired[0], isNull);

        final coalesced = repository.load(siteUrl: siteUrl, url: secureUrl);
        expect(credentials.keyReads, [siteUrl, siteUrl, otherSite, siteUrl]);
        held.last.result.complete(
          stage == 'API key' ? 'newest-key' : 'newest-client',
        );
        final fresh = await newest;
        expect(fresh?.bytes, [2]);
        expect(await coalesced, same(fresh));
        expect(
          await repository.load(siteUrl: siteUrl, url: secureUrl),
          same(fresh),
        );
        expect(
          await repository.load(siteUrl: otherSite, url: otherUrl),
          same(other),
        );
        expect(credentials.clientIdReads, stage == 'API key' ? 2 : 4);
        expect(requests.map(_requestIdentity), [
          ('GET', otherUrl, 'other-key', 'new-client'),
          (
            'GET',
            secureUrl,
            'newest-key',
            stage == 'API key' ? 'new-client' : 'newest-client',
          ),
        ]);
      },
    );

    test(
      'a current $stage failure reaches the caller and allows retry',
      () async {
        final credentials = _HeldImageCredentials()..keys[siteUrl] = 'new-key';
        final held = credentials.hold(stage);
        final requests = <http.Request>[];
        final repository = SiteImageRepository(
          credentials: credentials,
          lifecycle: SiteLifecycle(),
          client: MockClient((request) async {
            requests.add(request);
            return http.Response.bytes([2], 200);
          }),
        );
        addTearDown(() {
          repository.dispose();
          held.release();
        });
        final error = StateError('current credentials');
        final failed = expectLater(
          repository.load(siteUrl: siteUrl, url: secureUrl),
          throwsA(same(error)),
        );
        await held.started.future;
        held.result.completeError(error);
        await failed;

        expect(
          (await repository.load(siteUrl: siteUrl, url: secureUrl))?.bytes,
          [2],
        );
        expect(credentials.keyReads, [siteUrl, siteUrl]);
        expect(requests.map(_requestIdentity), [
          ('GET', secureUrl, 'new-key', 'new-client'),
        ]);
      },
    );
  }

  test('coalesces same-session credential reads and image downloads', () async {
    final credentials = _HeldImageCredentials();
    final key = credentials.hold('API key');
    final clientId = credentials.hold('client ID');
    final requests = <http.Request>[];
    final repository = SiteImageRepository(
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes([2], 200);
      }),
    );
    addTearDown(() {
      repository.dispose();
      key.release();
      clientId.release();
    });

    final first = repository.load(siteUrl: siteUrl, url: secureUrl);
    await key.started.future;
    final second = repository.load(siteUrl: siteUrl, url: secureUrl);
    expect(credentials.keyReads, [siteUrl]);
    key.result.complete('account-key');
    await clientId.started.future;
    final third = repository.load(siteUrl: siteUrl, url: secureUrl);
    expect(credentials.keyReads, [siteUrl]);
    expect(credentials.clientIdReads, 1);
    clientId.result.complete('account-client');

    final image = await first;
    expect(image?.bytes, [2]);
    expect(await second, same(image));
    expect(await third, same(image));
    expect(requests.map(_requestIdentity), [
      ('GET', secureUrl, 'account-key', 'account-client'),
    ]);
  });

  for (final abandon in ['forget', 'replacement', 'dispose']) {
    for (final lateResponse in ['abort', 'bytes', 'redirect']) {
      test('$abandon aborts transfers and rejects late $lateResponse', () async {
        final credentials = FakeApiCredentialReader()
          ..keys[siteUrl] = 'old-key';
        final lifecycle = SiteLifecycle();
        final client = _ControlledImageClient(
          honorAbort: lateResponse == 'abort',
        );
        final repository = SiteImageRepository(
          credentials: credentials,
          lifecycle: lifecycle,
          client: client,
        );
        addTearDown(repository.dispose);

        final stale = repository.load(siteUrl: siteUrl, url: secureUrl);
        await client.started.future;
        expect(client.requests.single.headers['User-Api-Key'], 'old-key');
        if (abandon == 'dispose') {
          repository.dispose();
        } else {
          if (abandon == 'replacement') {
            lifecycle.invalidate(siteUrl);
          } else {
            // Forget must retire the session even if its lease is still current.
            repository.forget(siteUrl);
          }
          credentials.keys[siteUrl] = 'new-key';
          final fresh = await repository.load(siteUrl: siteUrl, url: secureUrl);
          expect(fresh?.bytes, [2]);
          expect(client.requests.last.headers['User-Api-Key'], 'new-key');
          final other = await repository.load(
            siteUrl: 'https://other.example',
            url: 'https://other.example/image.png',
          );
          expect(other?.bytes, [2]);
        }

        // Observe the abort independently of whether the transport honors it.
        await Future<void>.delayed(Duration.zero);
        expect(client.aborted, isTrue);
        if (lateResponse != 'abort') {
          client.response.complete(
            http.StreamedResponse(
              Stream.value([1]),
              lateResponse == 'redirect' ? 302 : 200,
              headers: lateResponse == 'redirect'
                  ? {'location': '$siteUrl/late-authenticated-hop'}
                  : {},
            ),
          );
        }
        expect(await stale, isNull);
        expect(
          client.requests.where((r) => r.url.path == '/late-authenticated-hop'),
          isEmpty,
        );
        if (abandon != 'dispose') {
          expect(repository.cached(siteUrl: siteUrl, url: secureUrl)?.bytes, [
            2,
          ]);
        }
        repository.dispose();
        repository.dispose();
        expect(client.closed, isFalse);
        expect((await client.get(Uri.parse('$siteUrl/shared'))).bodyBytes, [2]);
        expect(await repository.load(siteUrl: siteUrl, url: secureUrl), isNull);
      });
    }
  }

  test('forums share one image byte budget', () async {
    const imageBytes = 512 * 1024;
    const sites = [
      'https://a.example',
      'https://b.example',
      'https://c.example',
      'https://d.example',
    ];
    final requests = <String>[];
    final repository = SiteImageRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
      client: MockClient((request) async {
        requests.add(request.url.toString());
        return http.Response.bytes(Uint8List(imageBytes), 200);
      }),
    );
    addTearDown(repository.dispose);
    String image(String site, int index) =>
        '$site/uploads/default/original/1X/$index.png';
    List<int> retained(String site) => [
      for (var index = 0; index < 200; index++)
        if (repository.isCached(siteUrl: site, url: image(site, index))) index,
    ];

    for (final site in sites) {
      for (var index = 0; index < 200; index++) {
        await repository.load(siteUrl: site, url: image(site, index));
      }
    }

    // The whole budget is what one forum could already retain on its own.
    const budget = 64 * 1024 * 1024;
    const budgetImages = budget ~/ imageBytes;
    expect(repository.maxCachedBytes, budget);
    expect(
      sites.expand(retained).length * imageBytes,
      lessThanOrEqualTo(budget),
    );
    expect(retained(sites.last), [
      for (var i = 200 - budgetImages; i < 200; i++) i,
    ]);
    for (final site in sites.take(3)) {
      expect(retained(site), isEmpty);
    }

    requests.clear();
    final returned = await repository.load(
      siteUrl: sites.first,
      url: image(sites.first, 199),
    );
    expect(returned?.bytes, hasLength(imageBytes));
    expect(requests, [image(sites.first, 199)]);
    expect(retained(sites.first), [199]);
    expect(retained(sites.last), [
      for (var i = 201 - budgetImages; i < 200; i++) i,
    ]);
  });

  test('a trimmed forum still delivers the images it is loading', () async {
    const otherSite = 'https://other.example';
    final held = Completer<void>();
    final repository = SiteImageRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
      maxCachedBytes: 2,
      client: MockClient((request) async {
        if (request.url.path == '/held.png') await held.future;
        return http.Response.bytes([1, 2], 200);
      }),
    );
    addTearDown(() {
      if (!held.isCompleted) held.complete();
      repository.dispose();
    });

    await repository.load(siteUrl: siteUrl, url: '$siteUrl/shown.png');
    final pending = repository.load(siteUrl: siteUrl, url: '$siteUrl/held.png');
    final other = await repository.load(
      siteUrl: otherSite,
      url: '$otherSite/image.png',
    );
    expect(other?.bytes, [1, 2]);
    expect(
      repository.isCached(siteUrl: siteUrl, url: '$siteUrl/shown.png'),
      isFalse,
    );

    held.complete();
    expect((await pending)?.bytes, [1, 2]);
    expect(
      repository.isCached(siteUrl: siteUrl, url: '$siteUrl/held.png'),
      isTrue,
    );
    expect(
      repository.isCached(siteUrl: otherSite, url: '$otherSite/image.png'),
      isFalse,
    );
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

final class _HeldImageBodiesClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final peakByOrigin = <String, int>{};
  final _activeByOrigin = <String, int>{};
  final _release = Completer<void>();
  var active = 0;
  var peak = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    active++;
    if (active > peak) peak = active;
    final origin = request.url.origin;
    final activeAtOrigin = (_activeByOrigin[origin] ?? 0) + 1;
    _activeByOrigin[origin] = activeAtOrigin;
    if (activeAtOrigin > (peakByOrigin[origin] ?? 0)) {
      peakByOrigin[origin] = activeAtOrigin;
    }
    return http.StreamedResponse(_body(origin), 200);
  }

  Stream<List<int>> _body(String origin) async* {
    try {
      yield [1];
      await _release.future;
      yield [2, 3];
    } finally {
      active--;
      _activeByOrigin[origin] = _activeByOrigin[origin]! - 1;
    }
  }

  void releaseBodies() {
    if (!_release.isCompleted) _release.complete();
  }
}

final class _ControlledImageClient extends http.BaseClient {
  _ControlledImageClient({required this.honorAbort});

  final bool honorAbort;
  final started = Completer<void>();
  final response = Completer<http.StreamedResponse>();
  final requests = <http.BaseRequest>[];
  bool aborted = false;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (closed) throw StateError('Shared client is closed');
    requests.add(request);
    if (requests.length != 1) {
      return Future.value(http.StreamedResponse(Stream.value([2]), 200));
    }
    final abortable = request as http.AbortableRequest;
    unawaited(
      abortable.abortTrigger!.then((_) {
        aborted = true;
        if (honorAbort && !response.isCompleted) {
          response.completeError(http.RequestAbortedException(request.url));
        }
      }),
    );
    started.complete();
    return response.future;
  }

  @override
  void close() => closed = true;
}

final class _HeldImageCredential {
  final started = Completer<void>();
  final result = Completer<String>();

  Future<String> read() {
    started.complete();
    return result.future;
  }

  void release() {
    if (!result.isCompleted) result.complete('abandoned');
  }
}

final class _HeldImageCredentials extends FakeApiCredentialReader {
  _HeldImageCredentials() : super(clientIdValue: 'new-client');

  final keyReads = <String>[];
  var clientIdReads = 0;
  final _keys = <_HeldImageCredential>[];
  final _clientIds = <_HeldImageCredential>[];

  _HeldImageCredential hold(String stage) {
    final held = _HeldImageCredential();
    (stage == 'API key' ? _keys : _clientIds).add(held);
    return held;
  }

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    keyReads.add(siteUrl);
    return _keys.isEmpty ? super.apiKeyFor(siteUrl) : _keys.removeAt(0).read();
  }

  @override
  Future<String> clientId() {
    clientIdReads++;
    return _clientIds.isEmpty
        ? super.clientId()
        : _clientIds.removeAt(0).read();
  }
}

(String, String, String?, String?) _requestIdentity(http.Request request) => (
  request.method,
  request.url.toString(),
  request.headers['User-Api-Key'],
  request.headers['User-Api-Client-Id'],
);
