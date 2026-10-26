import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache.dart';
import 'package:discourse_native/src/data/byte_cache_store.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_get_sender.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/http_basic_auth.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_video_source.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/basic_auth_storage.dart';
import 'support/fakes.dart';

const _authorization = 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==';

HttpBasicAuthentication _credential(
  String url, {
  String password = 'open sesame',
}) => HttpBasicAuthentication(
  origin: Uri.parse(url),
  username: 'Aladdin',
  password: password,
);

void main() {
  test('recognizes Basic schemes without reading quoted realm contents', () {
    for (final value in [
      'Basic realm="ngrok"',
      'bAsIc realm="staging", charset="UTF-8"',
      'Digest realm="example", Basic realm="other"',
    ]) {
      expect(hasHttpBasicChallenge(401, {'www-authenticate': value}), isTrue);
    }
    for (final value in [
      'Bearer realm="Basic"',
      'Digest realm="private, Basic words", nonce="abc"',
      r'Digest realm="private\", Basic words", nonce="abc"',
      'NotBasic realm="ngrok"',
    ]) {
      expect(hasHttpBasicChallenge(401, {'www-authenticate': value}), isFalse);
    }
    expect(
      hasHttpBasicChallenge(403, {'www-authenticate': 'Basic realm="ngrok"'}),
      isFalse,
    );
    expect(hasHttpBasicChallenge(401, {}), isFalse);
  });

  test(
    'credentials encode independently and remain bound to scheme host and port',
    () {
      final credential = _credential('https://forum.example');
      expect(
        credential.authorizationFor(Uri.parse('https://forum.example/path')),
        _authorization,
      );
      for (final url in [
        'https://other.example',
        'https://forum.example:444',
        'http://forum.example',
      ]) {
        expect(credential.authorizationFor(Uri.parse(url)), isNull);
      }
      expect('$credential', isNot(contains('Aladdin')));
      expect('$credential', isNot(contains('open sesame')));
      expect(
        _credential(
          'https://forum.example',
          password: 'a:b',
        ).authorizationFor(Uri.parse('https://forum.example')),
        'Basic QWxhZGRpbjphOmI=',
      );
      for (final fields in [
        ('a:b', 'x'),
        ('name', 'bad\nvalue'),
        ('name\u007f', 'x'),
      ]) {
        expect(
          () => HttpBasicAuthentication(
            origin: Uri.parse('https://forum.example'),
            username: fields.$1,
            password: fields.$2,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'confirmed credentials survive restart and rollback cannot undo a newer save',
    () async {
      final storage = BasicAuthMemoryStorage();
      final store = HttpBasicAuthStore(storage: storage);
      final first = await store.remember(_credential('https://forum.example'));
      final second = await store.remember(
        _credential('https://forum.example', password: 'new'),
      );
      await first.rollback();
      final restarted = HttpBasicAuthStore(storage: storage);
      await restarted.load();
      expect(
        restarted.authorizationFor(Uri.parse('https://forum.example')),
        'Basic QWxhZGRpbjpuZXc=',
      );
      await second.rollback();
      expect(
        store.authorizationFor(Uri.parse('https://forum.example')),
        _authorization,
      );
      storage.writeFailure = StateError('storage unavailable');
      await expectLater(
        store.forgetOrigin(Uri.parse('https://forum.example')),
        throwsStateError,
      );
      expect(
        store.authorizationFor(Uri.parse('https://forum.example')),
        _authorization,
      );
    },
  );

  test(
    'reusing one credential object gives each save independent rollback ownership',
    () async {
      final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
      final credential = _credential('https://forum.example');
      final first = await store.remember(credential);
      await store.remember(credential);
      await first.rollback();
      expect(
        store.authorizationFor(Uri.parse('https://forum.example')),
        _authorization,
      );
    },
  );

  test(
    'a re-added origin keeps its credential while a removal write is pending',
    () async {
      final storage = BasicAuthMemoryStorage();
      final store = HttpBasicAuthStore(storage: storage);
      await store.remember(_credential('https://forum.example'));
      var unused = true;
      storage.writeGate = Completer<void>();
      final removing = store.forgetOrigin(
        Uri.parse('https://forum.example'),
        whenUnused: () => unused,
      );
      await Future<void>.delayed(Duration.zero);
      unused = false;
      storage.writeGate!.complete();
      await removing;
      final restarted = HttpBasicAuthStore(storage: storage);
      await restarted.load();
      expect(
        restarted.authorizationFor(Uri.parse('https://forum.example')),
        _authorization,
      );
    },
  );

  test(
    'real loopback discovery challenges then authenticates both endpoints',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = <(String, String?)>[];
      server.listen((request) async {
        final authorization = request.headers.value('authorization');
        seen.add((request.uri.path, authorization));
        if (authorization != _authorization) {
          request.response.statusCode = 401;
          request.response.headers.set(
            'www-authenticate',
            'Basic realm="local"',
          );
        } else if (request.uri.path == '/user-api-key/new') {
          request.response.headers.set('auth-api-version', '4');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"title":"Protected forum"}');
        }
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server.port}';
      final api = DiscourseApi();
      addTearDown(api.close);
      await expectLater(
        api.lookup(url),
        throwsA(
          isA<HttpBasicAuthenticationRequired>().having(
            (e) => e.origin.origin,
            'origin',
            url,
          ),
        ),
      );
      final instance = await api.lookup(url, authentication: _credential(url));
      expect(instance.title, 'Protected forum');
      expect(instance.url, url);
      expect(seen, [
        ('/user-api-key/new', null),
        ('/user-api-key/new', _authorization),
        ('/site/basic-info.json', _authorization),
      ]);
    },
  );

  test(
    'redirected challenges bind to the new origin without forwarding candidate credentials',
    () async {
      final seen = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen.add(request);
          return request.url.host == 'first.example'
              ? http.Response(
                  '',
                  302,
                  headers: {
                    'location': 'https://next.example:444/user-api-key/new',
                  },
                )
              : http.Response(
                  '',
                  401,
                  headers: {'www-authenticate': 'Basic realm="next"'},
                );
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.lookup(
          'https://first.example',
          authentication: _credential('https://first.example'),
        ),
        throwsA(
          isA<HttpBasicAuthenticationRequired>().having(
            (e) => e.origin.origin,
            'origin',
            'https://next.example:444',
          ),
        ),
      );
      expect(seen.map((r) => r.headers['authorization']), [
        _authorization,
        null,
      ]);
    },
  );

  test('basic-info challenge is distinct from a generic 401', () async {
    var basic = true;
    final api = DiscourseApi(
      client: MockClient(
        (request) async => request.method == 'HEAD'
            ? http.Response('', 200, headers: {'auth-api-version': '4'})
            : http.Response(
                '',
                401,
                headers: basic
                    ? {'www-authenticate': 'Basic realm="info"'}
                    : {},
              ),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.lookup('https://forum.example'),
      throwsA(isA<HttpBasicAuthenticationRequired>()),
    );
    basic = false;
    await expectLater(
      api.lookup('https://forum.example'),
      throwsA(
        isA<SiteLookupException>().having(
          (e) => e is HttpBasicAuthenticationRequired,
          'basic challenge',
          isFalse,
        ),
      ),
    );
  });

  test(
    'confirmed Basic credentials coexist with API headers and preserve explicit Authorization',
    () async {
      final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
      await store.remember(_credential('https://forum.example'));
      final requests = <http.Request>[];
      final client = SafeHttpClient.owned(
        MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
        basicAuth: store,
      );
      addTearDown(client.close);
      await client.post(
        Uri.parse('https://forum.example/posts'),
        headers: {'User-Api-Key': 'api-secret', 'User-Api-Client-Id': 'device'},
      );
      await client.get(
        Uri.parse('https://forum.example/explicit'),
        headers: {'Authorization': 'Bearer explicit'},
      );
      await client.get(Uri.parse('https://forum.example:444/other'));
      expect(requests.first.headers['authorization'], _authorization);
      expect(requests.first.headers['user-api-key'], 'api-secret');
      expect(requests.first.headers['user-api-client-id'], 'device');
      expect(requests[1].headers['authorization'], 'Bearer explicit');
      expect(requests[2].headers['authorization'], isNull);
    },
  );

  test('queued anonymous GET is retired when credentials change', () async {
    final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    var requests = 0;
    final client = SafeHttpClient.owned(
      MockClient((request) async {
        requests++;
        started.complete();
        return gate.future;
      }),
      basicAuth: store,
    );
    final coordinator = DiscourseRequestCoordinator(maxConcurrentPerOrigin: 1);
    addTearDown(client.close);
    addTearDown(coordinator.close);
    final sender = DiscourseGetSender(
      client,
      coordinator,
      const Duration(seconds: 5),
      1024,
    );
    Future<http.Response> get(String path) => sender.send(
      http.Request('GET', Uri.parse('https://forum.example/$path')),
      scope: null,
      cancellation: null,
    );
    final first = get('blocker');
    final firstCheck = expectLater(
      first,
      throwsA(isA<DiscourseQueuedRequestCancelledException>()),
    );
    await started.future;
    final queued = get('queued');
    final queuedCheck = expectLater(
      queued,
      throwsA(isA<DiscourseQueuedRequestCancelledException>()),
    );
    await store.remember(_credential('https://forum.example'));
    gate.complete(http.Response('{}', 200));
    await Future.wait([firstCheck, queuedCheck]);
    expect(requests, 1);
  });

  test(
    'protected media skips public disk cache and rotates memory identity',
    () async {
      final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
      await store.remember(_credential('https://forum.example'));
      final disk = _Disk();
      var requests = 0;
      final cache = _Bytes(
        store,
        disk,
        MockClient((request) async {
          requests++;
          return http.Response.bytes(
            [requests],
            200,
            headers: {'cache-control': 'public, max-age=3600'},
          );
        }),
      );
      addTearDown(cache.close);
      const url = 'https://forum.example/image';
      expect(await cache.load(url), [1]);
      expect(await cache.load(url), [1]);
      expect(disk.reads, 0);
      expect(disk.writes, 0);
      await store.remember(
        _credential('https://forum.example', password: 'other'),
      );
      expect(cache.cached(url), isNull);
      expect(await cache.load(url), [2]);
      expect(disk.reads, 0);
      expect(disk.writes, 0);
    },
  );

  test(
    'native protected video keeps the existing external-open boundary',
    () async {
      final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
      await store.remember(_credential('https://forum.example'));
      final resolver = SiteVideoSourceResolver(
        credentials: FakeAuthenticator(),
        lifecycle: SiteLifecycle(),
        basicAuth: store,
      );
      addTearDown(resolver.close);
      await expectLater(
        resolver.resolve(
          siteUrl: 'https://forum.example',
          url: Uri.parse('https://forum.example/uploads/video.mp4'),
        ),
        throwsA(isA<SiteVideoSourceRequiresAuthenticationException>()),
      );
    },
  );
  test(
    'public-to-protected redirects never persist authenticated bytes',
    () async {
      final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
      await store.remember(_credential('https://protected.example'));
      final disk = _Disk()..cachedBytes = null;
      final requests = <http.Request>[];
      final cache = _Bytes(
        store,
        disk,
        MockClient((request) async {
          requests.add(request);
          return request.url.host == 'public.example'
              ? http.Response(
                  '',
                  302,
                  headers: {
                    'location': 'https://protected.example/image',
                    'cache-control': 'public,max-age=3600',
                  },
                )
              : http.Response.bytes(
                  [1],
                  200,
                  headers: {'cache-control': 'public,max-age=3600'},
                );
        }),
      );
      addTearDown(cache.close);
      expect(await cache.load('https://public.example/image'), [1]);
      expect(requests.map((request) => request.headers['authorization']), [
        null,
        _authorization,
      ]);
      expect(disk.writes, 0);
    },
  );

  test('a media response from retired credentials is discarded', () async {
    final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
    await store.remember(_credential('https://forum.example'));
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    var requests = 0;
    final cache = _Bytes(
      store,
      _Disk(),
      MockClient((request) async {
        requests++;
        if (requests == 1) {
          started.complete();
          return gate.future;
        }
        return http.Response.bytes([2], 200);
      }),
    );
    addTearDown(cache.close);
    const url = 'https://forum.example/image';
    final old = cache.load(url);
    await started.future;
    await store.remember(
      _credential('https://forum.example', password: 'replacement'),
    );
    gate.complete(http.Response.bytes([1], 200));
    expect(await old, isNull);
    expect(await cache.load(url), [2]);
  });

  test(
    'same-value credential replacement cannot join the retired GET',
    () async {
      final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
      await store.remember(_credential('https://forum.example'));
      final gate = Completer<http.Response>();
      final started = Completer<void>();
      var requests = 0;
      final inner = SafeHttpClient.owned(
        MockClient((request) async {
          requests++;
          if (requests == 1) {
            started.complete();
            return gate.future;
          }
          return http.Response('new representation', 200);
        }),
        basicAuth: store,
      );
      final client = SafeHttpClient.borrowed(inner);
      expect(identical(client.basicAuth, store), isTrue);
      addTearDown(inner.close);
      final coordinator = DiscourseRequestCoordinator();
      addTearDown(client.close);
      addTearDown(coordinator.close);
      final sender = DiscourseGetSender(
        client,
        coordinator,
        const Duration(seconds: 5),
        1024,
      );
      Future<http.Response> get() => sender.send(
        http.Request('GET', Uri.parse('https://forum.example/topic')),
        scope: null,
        cancellation: null,
      );
      final old = get();
      final checkOld = expectLater(
        old,
        throwsA(isA<DiscourseQueuedRequestCancelledException>()),
      );
      await started.future;
      await store.remember(_credential('https://forum.example'));
      expect((await get()).body, 'new representation');
      gate.complete(http.Response('old representation', 200));
      await checkOld;
      expect(requests, 2);
    },
  );

  test(
    'production instance loading restores credentials before returning forums',
    () async {
      final storage = BasicAuthMemoryStorage();
      await HttpBasicAuthStore(
        storage: storage,
      ).remember(_credential('https://forum.example'));
      final restarted = HttpBasicAuthStore(storage: storage);
      final instances = InstanceStore(
        persistence: _Instances(),
        basicAuth: restarted,
      );
      expect((await instances.load()).single.url, 'https://forum.example');
      expect(
        restarted.authorizationFor(Uri.parse('https://forum.example')),
        _authorization,
      );
    },
  );

  test(
    'sign-out retains server authentication and final same-origin removal clears it',
    () async {
      final store = HttpBasicAuthStore(storage: BasicAuthMemoryStorage());
      await store.remember(_credential('https://forum.example'));
      const first = DiscourseInstance(
        url: 'https://forum.example/first',
        title: 'First',
      );
      const second = DiscourseInstance(
        url: 'https://forum.example/second',
        title: 'Second',
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore([first, second]),
        api: FakeDiscourseApi(),
        basicAuth: store,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      expect(await shell.disconnectInstance(first.url), isTrue);
      expect(store.protects(Uri.parse(first.url)), isTrue);
      expect(await shell.removeInstance(first), isTrue);
      expect(store.protects(Uri.parse(second.url)), isTrue);
      expect(await shell.removeInstance(second), isTrue);
      for (var attempt = 0; attempt < 5; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.protects(Uri.parse(second.url)), isFalse);
    },
  );
}

final class _Bytes extends ByteCache<Uint8List> {
  _Bytes(
    HttpBasicAuthStore authentication,
    ByteCacheStore disk,
    http.Client client,
  ) : super(basicAuth: authentication, store: disk, client: client);
  @override
  Uint8List? decode(http.Response response) => response.bodyBytes;
}

final class _Disk implements ByteCacheStore {
  int reads = 0;
  int writes = 0;
  Uint8List? cachedBytes = Uint8List.fromList([99]);
  @override
  Future<Uint8List?> read(String url) async {
    reads++;
    return cachedBytes;
  }

  @override
  Future<void> write(
    String url,
    Uint8List bytes, {
    required DateTime expiresAt,
  }) async {
    writes++;
  }

  @override
  Future<void> remove(String url) async {}
}

final class _Instances implements InstancePersistence {
  @override
  Future<String?> read() async =>
      '[{"url":"https://forum.example","title":"Protected forum"}]';
  @override
  Future<void> write(String value) async {}
}
