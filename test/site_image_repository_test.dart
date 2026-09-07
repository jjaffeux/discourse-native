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
