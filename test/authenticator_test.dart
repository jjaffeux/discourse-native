import 'dart:async';

import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/push_registration.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _site = 'https://meta.discourse.org';
const _pair = AuthKeyPair(publicPem: 'public-pem', privatePem: 'private-pem');
const _credentials = UserApiCredentials(
  key: 'api-key',
  apiVersion: 4,
  push: false,
);
const _macosRegistration = PushRegistration(
  clientId: 'macos-apns-token',
  pushUrl: PlatformPushRegistrationProvider.macosPushUrl,
);

void main() {
  group('discovery to authorization', () {
    for (final redirected in [false, true]) {
      test(
        'launches the discovered subfolder${redirected ? ' after a redirect' : ''}',
        () async {
          const siteUrl = 'https://forum.example:8443/community';
          final endpoint = Uri.parse('$siteUrl/user-api-key/new');
          final requested = <(String, Uri)>[];
          final api = DiscourseApi(
            client: MockClient((request) async {
              requested.add((request.method, request.url));
              if (redirected &&
                  request.url ==
                      Uri.parse('https://old.example/user-api-key/new')) {
                return http.Response(
                  '',
                  301,
                  headers: {'location': endpoint.toString()},
                );
              }
              if (request.url == endpoint) {
                return http.Response(
                  '',
                  200,
                  headers: {'auth-api-version': '4'},
                );
              }
              if (request.url == Uri.parse('$siteUrl/site/basic-info.json')) {
                return http.Response('{"title":"Subfolder"}', 200);
              }
              return http.Response('not found', 404);
            }),
          );
          addTearDown(api.close);

          final site = await api.lookup(
            redirected ? 'old.example' : '$siteUrl/',
          );
          expect(site.url, siteUrl);
          expect(requested, [
            if (redirected)
              ('HEAD', Uri.parse('https://old.example/user-api-key/new')),
            ('HEAD', endpoint),
            ('GET', Uri.parse('$siteUrl/site/basic-info.json')),
          ]);

          final store = _FakeSecureStore();
          final launched = <(Uri, String)>[];
          const cancelled = UserApiAuthException(UserApiAuthFailure.cancelled);
          final authenticator = Authenticator(
            store: store,
            pushRegistrations: _FakePushRegistrationProvider(null),
            keyPairGenerator: () async => _pair,
            nonceGenerator: () => 'fixed-nonce',
            launcher: (url, callbackScheme) async {
              launched.add((Uri.parse(url), callbackScheme));
              throw cancelled;
            },
          );

          await expectLater(
            authenticator.authorize(site.url),
            throwsA(same(cancelled)),
          );

          expect(launched, hasLength(1));
          final (url, callbackScheme) = launched.single;
          expect(url.origin, 'https://forum.example:8443');
          expect(url.path, endpoint.path);
          expect(url.queryParameters['nonce'], 'fixed-nonce');
          expect(url.queryParameters['public_key'], _pair.publicPem);
          expect(url.queryParameters['client_id'], 'client-id');
          expect(callbackScheme, UserApiKeyProtocol.redirectScheme);
          expect(store.apiKeyWrites, isEmpty);
        },
      );
    }
  });

  group('Authenticator.connect', () {
    test('can validate a handshake before persisting its credential', () async {
      final events = <String>[];
      final store = _FakeSecureStore(events: events);
      final authenticator = Authenticator(
        store: store,
        protocol: _FakeProtocol(events: events),
        keyPairGenerator: () async => _pair,
        nonceGenerator: () => 'nonce',
        launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
      );

      final credentials = await authenticator.authorize(_site);

      expect(credentials, same(_credentials));
      expect(store.apiKeys, isEmpty);

      await authenticator.persistCredentials(_site, credentials);

      expect(store.apiKeys, {_site: _credentials.key});
    });

    test(
      'runs the handshake before persisting validated credentials',
      () async {
        final events = <String>[];
        final store = _FakeSecureStore(events: events);
        final protocol = _FakeProtocol(events: events);
        late String launchedUrl;
        late String launchedScheme;
        final authenticator = Authenticator(
          store: store,
          protocol: protocol,
          applicationName: 'Test Client',
          nonceGenerator: () => 'fixed-nonce',
          keyPairGenerator: () async {
            events.add('generate-key-pair');
            return _pair;
          },
          launcher: (url, callbackScheme) async {
            events.add('launch');
            launchedUrl = url;
            launchedScheme = callbackScheme;
            return 'discourse://auth_redirect?payload=reply';
          },
        );

        final result = await authenticator.connect(_site);

        expect(result, same(_credentials));
        expect(store.apiKeys, {_site: 'api-key'});
        expect(protocol.siteUrl, _site);
        expect(protocol.publicKeyPem, 'public-pem');
        expect(protocol.privateKeyPem, 'private-pem');
        expect(protocol.clientId, 'client-id');
        expect(protocol.nonce, 'fixed-nonce');
        expect(protocol.applicationName, 'Test Client');
        expect(launchedUrl, 'https://authorize.invalid');
        expect(launchedScheme, UserApiKeyProtocol.redirectScheme);
        expect(events, [
          'read-client-id',
          'generate-key-pair',
          'auth-url',
          'launch',
          'callback-payload',
          'decode-payload',
          'write-api-key',
        ]);
      },
    );

    test('uses a fresh transient key pair for each connection', () async {
      final store = _FakeSecureStore();
      final events = <String>[];
      var generationCount = 0;
      final authenticator = Authenticator(
        store: store,
        protocol: _FakeProtocol(),
        pushRegistrations: _FakePushRegistrationProvider(
          _macosRegistration,
          events: events,
        ),
        nonceGenerator: () => 'nonce',
        keyPairGenerator: () async {
          generationCount += 1;
          return _pair;
        },
        launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
      );

      await authenticator.connect('https://one.example');
      await authenticator.connect('https://two.example');

      expect(generationCount, 2);
      expect(events, ['read-push-registration', 'read-push-registration']);
      expect(store.apiKeys.keys, {
        'https://one.example',
        'https://two.example',
      });
    });

    test('registers a macOS push token as the user API client', () async {
      final events = <String>[];
      final store = _FakeSecureStore(events: events);
      final protocol = _FakeProtocol(events: events);
      final authenticator = Authenticator(
        store: store,
        protocol: protocol,
        pushRegistrations: _FakePushRegistrationProvider(
          const PushRegistration(
            clientId: 'macos-apns-token',
            pushUrl: PlatformPushRegistrationProvider.macosPushUrl,
          ),
          events: events,
        ),
        keyPairGenerator: () async {
          events.add('generate-key-pair');
          return _pair;
        },
        nonceGenerator: () => 'nonce',
        launcher: (_, _) async {
          events.add('launch');
          return 'discourse://auth_redirect?payload=reply';
        },
      );

      await authenticator.connect(_site);

      expect(protocol.clientId, 'macos-apns-token');
      expect(protocol.pushUrl, PlatformPushRegistrationProvider.macosPushUrl);
      expect(await authenticator.clientId(), 'macos-apns-token');
      expect(events, [
        'read-push-registration',
        'generate-key-pair',
        'auth-url',
        'launch',
        'callback-payload',
        'decode-payload',
        'write-api-key',
      ]);
    });

    for (final persist in [false, true]) {
      test(
        '${persist ? 'connect' : 'authorize'} refreshes a client ID cached as unavailable within the retry interval',
        () async {
          final events = <String>[];
          var now = DateTime.utc(2026, 9, 8, 12);
          final provider = _FakePushRegistrationProvider(null, events: events);
          final store = _FakeSecureStore(events: events);
          final protocol = _FakeProtocol();
          final authenticator = Authenticator(
            store: store,
            protocol: protocol,
            pushRegistrations: provider,
            clock: () => now,
            keyPairGenerator: () async => _pair,
            nonceGenerator: () => 'nonce',
            launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
          );

          expect(await authenticator.clientId(), 'client-id');
          provider.value = _macosRegistration;
          now = now.add(const Duration(seconds: 30));

          final credentials = await (persist
              ? authenticator.connect(_site)
              : authenticator.authorize(_site));

          expect(credentials, same(_credentials));
          expect(protocol.clientId, _macosRegistration.clientId);
          expect(protocol.pushUrl, _macosRegistration.pushUrl);
          expect(store.apiKeyWrites, [if (persist) (_site, _credentials.key)]);
          expect(await authenticator.clientId(), _macosRegistration.clientId);
          now = now.add(const Duration(minutes: 3));
          expect(await authenticator.clientId(), _macosRegistration.clientId);
          expect(events.where((event) => event == 'read-push-registration'), [
            'read-push-registration',
            'read-push-registration',
          ]);
          expect(events.where((event) => event == 'read-client-id'), [
            'read-client-id',
          ]);
        },
      );
    }

    test(
      'a superseded connection can learn the push identity without continuing its handshake',
      () async {
        final events = <String>[];
        final provider = _ControlledPushRegistrationProvider();
        final store = _FakeSecureStore();
        final authenticator = Authenticator(
          store: store,
          protocol: _FakeProtocol(events: events),
          pushRegistrations: provider,
          keyPairGenerator: () async {
            events.add('generate-key-pair');
            return _pair;
          },
          nonceGenerator: () => 'nonce',
          launcher: (_, _) async {
            events.add('launch');
            return 'discourse://auth_redirect?payload=reply';
          },
        );

        final superseded = expectLater(
          authenticator.connect(_site),
          throwsA(
            isA<UserApiAuthException>().having(
              (error) => error.failure,
              'failure',
              UserApiAuthFailure.cancelled,
            ),
          ),
        );
        final connection = authenticator.connect(_site);
        expect(provider.requests, hasLength(2));
        provider.requests[1].complete(null);
        expect(await connection, same(_credentials));

        provider.requests[0].complete(_macosRegistration);
        await superseded;

        final clientId = authenticator.clientId();
        expect(provider.requests, hasLength(2));
        expect(await clientId, _macosRegistration.clientId);
        expect(store.apiKeyWrites, [(_site, _credentials.key)]);
        expect(events, [
          'generate-key-pair',
          'auth-url',
          'launch',
          'callback-payload',
          'decode-payload',
        ]);
      },
    );

    test(
      'disconnect cancels only its pending site before credential persistence',
      () async {
        final callbacks = [Completer<String>(), Completer<String>()];
        final started = [Completer<void>(), Completer<void>()];
        var launchIndex = 0;
        final store = _FakeSecureStore();
        final authenticator = Authenticator(
          store: store,
          protocol: _FakeProtocol(),
          keyPairGenerator: () async => _pair,
          nonceGenerator: () => 'nonce',
          launcher: (_, _) {
            final index = launchIndex++;
            started[index].complete();
            return callbacks[index].future;
          },
        );
        const firstSite = 'https://one.example';
        const secondSite = 'https://two.example';

        final firstConnection = authenticator.connect(firstSite);
        await started[0].future;
        final firstCancelled = expectLater(
          firstConnection,
          throwsA(
            isA<UserApiAuthException>().having(
              (error) => error.failure,
              'failure',
              UserApiAuthFailure.cancelled,
            ),
          ),
        );
        final secondConnection = authenticator.connect(secondSite);
        await started[1].future;

        await authenticator.disconnect(firstSite);
        callbacks[0].complete('discourse://auth_redirect?payload=reply');
        callbacks[1].complete('discourse://auth_redirect?payload=reply');

        await firstCancelled;
        expect(await secondConnection, same(_credentials));
        expect(store.apiKeyWrites, [(secondSite, _credentials.key)]);
        expect(store.apiKeys, {secondSite: _credentials.key});
      },
    );

    test(
      'does not open the browser when the client ID cannot be read',
      () async {
        var launches = 0;
        final error = StateError('preferences unavailable');
        final authenticator = Authenticator(
          store: _FakeSecureStore(clientIdError: error),
          protocol: _FakeProtocol(),
          launcher: (_, _) async {
            launches += 1;
            return 'unused';
          },
        );

        await expectLater(authenticator.connect(_site), throwsA(same(error)));
        expect(launches, 0);
      },
    );

    test(
      'does not open the browser for a site URL containing credentials',
      () async {
        var launches = 0;
        final store = _FakeSecureStore();
        final authenticator = Authenticator(
          store: store,
          keyPairGenerator: () async => _pair,
          nonceGenerator: () => 'nonce',
          launcher: (_, _) async {
            launches += 1;
            return 'unused';
          },
        );

        await expectLater(
          authenticator.connect('https://reader:password@forum.example'),
          throwsA(isA<UnsafeHttpTransportException>()),
        );
        expect(launches, 0);
        expect(store.apiKeys, isEmpty);
      },
    );

    test('reports browser cancellation without persisting a key', () async {
      final store = _FakeSecureStore();
      final authenticator = Authenticator(
        store: store,
        protocol: _FakeProtocol(),
        launcher: (_, _) async =>
            throw PlatformException(code: 'CANCELED', message: 'dismissed'),
      );

      await expectLater(
        authenticator.connect(_site),
        throwsA(
          isA<UserApiAuthException>().having(
            (error) => error.failure,
            'failure',
            UserApiAuthFailure.cancelled,
          ),
        ),
      );
      expect(store.apiKeys, isEmpty);
    });

    test('distinguishes platform launch failures from cancellation', () async {
      final store = _FakeSecureStore();
      final platformError = PlatformException(
        code: 'UNAVAILABLE',
        message: 'no browser',
      );
      final authenticator = Authenticator(
        store: store,
        protocol: _FakeProtocol(),
        launcher: (_, _) async => throw platformError,
      );

      await expectLater(
        authenticator.connect(_site),
        throwsA(
          isA<UserApiAuthException>()
              .having(
                (error) => error.failure,
                'failure',
                UserApiAuthFailure.launchFailed,
              )
              .having(
                (error) => error.detail,
                'detail',
                contains('UNAVAILABLE'),
              )
              .having(
                (error) => error.diagnosticCause,
                'diagnostic cause',
                same(platformError),
              )
              .having(
                (error) => error.diagnosticCauseStackTrace,
                'diagnostic cause stack',
                isNotNull,
              ),
        ),
      );
      expect(store.apiKeys, isEmpty);
    });

    test('preserves protocol failures raised by the launcher', () async {
      const error = UserApiAuthException(
        UserApiAuthFailure.badReply,
        'browser callback rejected',
      );
      final authenticator = Authenticator(
        store: _FakeSecureStore(),
        protocol: _FakeProtocol(),
        launcher: (_, _) async => throw error,
      );

      await expectLater(authenticator.connect(_site), throwsA(same(error)));
    });

    test('does not persist credentials when reply validation fails', () async {
      final store = _FakeSecureStore();
      const protocolError = UserApiAuthException(
        UserApiAuthFailure.badReply,
        'invalid payload',
      );
      final authenticator = Authenticator(
        store: store,
        protocol: _FakeProtocol(decodeError: protocolError),
        launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
      );

      await expectLater(
        authenticator.connect(_site),
        throwsA(same(protocolError)),
      );
      expect(store.apiKeys, isEmpty);
    });

    test('surfaces persistence failure after successful validation', () async {
      final events = <String>[];
      final error = StateError('keychain write failed');
      final store = _FakeSecureStore(events: events, writeApiKeyError: error);
      final authenticator = Authenticator(
        store: store,
        protocol: _FakeProtocol(events: events),
        launcher: (_, _) async {
          events.add('launch');
          return 'discourse://auth_redirect?payload=reply';
        },
      );

      await expectLater(authenticator.connect(_site), throwsA(same(error)));
      expect(
        events.indexOf('decode-payload'),
        lessThan(events.indexOf('write-api-key')),
      );
      expect(store.apiKeys, isEmpty);
    });
  });

  group('Authenticator.clientId', () {
    for (final routineCompletesLast in [true, false]) {
      test(
        'a late unavailable ${routineCompletesLast ? 'client ID read' : 'authorization registration'} keeps the successful push identity',
        () async {
          final events = <String>[];
          final provider = _ControlledPushRegistrationProvider();
          final protocol = _FakeProtocol();
          final authenticator = Authenticator(
            store: _FakeSecureStore(events: events),
            protocol: protocol,
            pushRegistrations: provider,
            keyPairGenerator: () async => _pair,
            nonceGenerator: () => 'nonce',
            launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
          );

          final reads = [authenticator.clientId(), authenticator.clientId()];
          expect(provider.requests, hasLength(1));
          final authorization = authenticator.authorize(_site);
          expect(provider.requests, hasLength(2));

          if (routineCompletesLast) {
            provider.requests[1].complete(_macosRegistration);
            await authorization;
            reads.add(authenticator.clientId());
            provider.requests[0].complete(null);
          } else {
            provider.requests[0].complete(_macosRegistration);
            await Future.wait(reads);
            provider.requests[1].complete(null);
          }

          expect(await authorization, same(_credentials));
          expect(await Future.wait(reads), [
            _macosRegistration.clientId,
            _macosRegistration.clientId,
            if (routineCompletesLast) _macosRegistration.clientId,
          ]);
          expect(protocol.clientId, _macosRegistration.clientId);
          expect(protocol.pushUrl, _macosRegistration.pushUrl);
          expect(await authenticator.clientId(), _macosRegistration.clientId);
          expect(provider.requests, hasLength(2));
          expect(events, isEmpty);
        },
      );
    }

    for (final authorizing in [false, true]) {
      test(
        '${authorizing ? 'authorize' : 'clientId'} uses a push identity learned while the fallback client ID is being read',
        () async {
          final events = <String>[];
          final fallbackStarted = Completer<void>();
          final fallback = Completer<String>();
          final provider = _FakePushRegistrationProvider(null, events: events);
          final protocol = _FakeProtocol();
          final authenticator = Authenticator(
            store: _FakeSecureStore(
              events: events,
              clientIdReader: () {
                fallbackStarted.complete();
                return fallback.future;
              },
            ),
            protocol: protocol,
            pushRegistrations: provider,
            keyPairGenerator: () async => _pair,
            nonceGenerator: () => 'nonce',
            launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
          );

          final pendingRead = authorizing
              ? authenticator.authorize(_site)
              : authenticator.clientId();
          await fallbackStarted.future;
          provider.value = _macosRegistration;
          if (authorizing) {
            expect(await authenticator.clientId(), _macosRegistration.clientId);
          } else {
            await authenticator.authorize(_site);
          }
          fallback.complete('client-id');

          expect(
            await pendingRead,
            authorizing ? same(_credentials) : _macosRegistration.clientId,
          );
          expect(protocol.clientId, _macosRegistration.clientId);
          expect(protocol.pushUrl, _macosRegistration.pushUrl);
          expect(await authenticator.clientId(), _macosRegistration.clientId);
          expect(events, [
            'read-push-registration',
            'read-client-id',
            'read-push-registration',
          ]);
        },
      );
    }

    test('reuses the push registration for later client id reads', () async {
      final events = <String>[];
      final authenticator = Authenticator(
        store: _FakeSecureStore(events: events),
        pushRegistrations: _FakePushRegistrationProvider(
          _macosRegistration,
          events: events,
        ),
      );

      expect(await authenticator.clientId(), 'macos-apns-token');
      expect(await authenticator.clientId(), 'macos-apns-token');
      expect(events, ['read-push-registration']);
    });

    test(
      'shares one registration read between concurrent client id reads',
      () async {
        final events = <String>[];
        final registrationRead = Completer<void>();
        final authenticator = Authenticator(
          store: _FakeSecureStore(events: events),
          pushRegistrations: _FakePushRegistrationProvider(
            _macosRegistration,
            events: events,
            gate: registrationRead,
          ),
        );

        final reads = [authenticator.clientId(), authenticator.clientId()];
        expect(events, ['read-push-registration']);

        registrationRead.complete();
        expect(await Future.wait(reads), [
          'macos-apns-token',
          'macos-apns-token',
        ]);
        expect(events, ['read-push-registration']);
      },
    );

    test(
      'asks the platform again for a client id only after the retry interval when registration was unavailable',
      () async {
        final events = <String>[];
        var now = DateTime.utc(2026, 9, 2, 12);
        final provider = _FakePushRegistrationProvider(null, events: events);
        final authenticator = Authenticator(
          store: _FakeSecureStore(events: events),
          pushRegistrations: provider,
          pushRegistrationRetryInterval: const Duration(seconds: 90),
          clock: () => now,
        );

        expect(await authenticator.clientId(), 'client-id');
        provider.value = _macosRegistration;
        now = now.add(const Duration(seconds: 90));
        expect(await authenticator.clientId(), 'client-id');
        expect(events, [
          'read-push-registration',
          'read-client-id',
          'read-client-id',
        ]);

        now = now.add(const Duration(seconds: 1));
        expect(await authenticator.clientId(), 'macos-apns-token');
        expect(await authenticator.clientId(), 'macos-apns-token');
        expect(events, [
          'read-push-registration',
          'read-client-id',
          'read-client-id',
          'read-push-registration',
        ]);
      },
    );
  });

  test('credential lifecycle methods delegate keychain failures', () async {
    final error = StateError('keychain unavailable');
    final store = _FakeSecureStore(
      readApiKeyError: error,
      deleteApiKeyError: error,
      clientIdError: error,
    );
    final authenticator = Authenticator(store: store);

    await expectLater(authenticator.apiKeyFor(_site), throwsA(same(error)));
    await expectLater(authenticator.clientId(), throwsA(same(error)));
    await expectLater(authenticator.disconnect(_site), throwsA(same(error)));
  });
}

final class _FakeProtocol extends UserApiKeyProtocol {
  _FakeProtocol({this.events, this.decodeError});

  final List<String>? events;
  final Object? decodeError;

  String? siteUrl;
  String? publicKeyPem;
  String? privateKeyPem;
  String? nonce;
  String? clientId;
  String? applicationName;
  String? pushUrl;

  @override
  Uri authUrl({
    required String siteUrl,
    required String publicKeyPem,
    required String nonce,
    required String clientId,
    required String applicationName,
    String? pushUrl,
  }) {
    events?.add('auth-url');
    this.siteUrl = siteUrl;
    this.publicKeyPem = publicKeyPem;
    this.nonce = nonce;
    this.clientId = clientId;
    this.applicationName = applicationName;
    this.pushUrl = pushUrl;
    return Uri.parse('https://authorize.invalid');
  }

  @override
  String payloadFromCallback(String callbackUrl) {
    events?.add('callback-payload');
    return 'decoded-callback';
  }

  @override
  UserApiCredentials decodePayload({
    required String payload,
    required String privateKeyPem,
    required String expectedNonce,
  }) {
    events?.add('decode-payload');
    this.privateKeyPem = privateKeyPem;
    if (decodeError != null) throw decodeError!;
    return _credentials;
  }
}

final class _FakePushRegistrationProvider implements PushRegistrationProvider {
  _FakePushRegistrationProvider(this.value, {this.events, this.gate});

  PushRegistration? value;
  final List<String>? events;
  final Completer<void>? gate;

  @override
  Future<PushRegistration?> registration() async {
    events?.add('read-push-registration');
    if (gate case final pending?) await pending.future;
    return value;
  }
}

final class _ControlledPushRegistrationProvider
    implements PushRegistrationProvider {
  final requests = <Completer<PushRegistration?>>[];

  @override
  Future<PushRegistration?> registration() {
    final request = Completer<PushRegistration?>();
    requests.add(request);
    return request.future;
  }
}

final class _FakeSecureStore implements SecureStore {
  _FakeSecureStore({
    this.events,
    this.clientIdReader,
    this.clientIdError,
    this.readApiKeyError,
    this.writeApiKeyError,
    this.deleteApiKeyError,
  });

  final List<String>? events;
  final Future<String> Function()? clientIdReader;
  final Object? clientIdError;
  final Object? readApiKeyError;
  final Object? writeApiKeyError;
  final Object? deleteApiKeyError;

  final Map<String, String> apiKeys = {};
  final List<(String, String)> apiKeyWrites = [];

  @override
  Future<String> readOrCreateClientId() async {
    events?.add('read-client-id');
    if (clientIdError != null) throw clientIdError!;
    if (clientIdReader case final read?) return read();
    return 'client-id';
  }

  @override
  Future<String?> readApiKey(String siteUrl) async {
    if (readApiKeyError != null) throw readApiKeyError!;
    return apiKeys[siteUrl];
  }

  @override
  Future<void> writeApiKey(String siteUrl, String key) async {
    events?.add('write-api-key');
    if (writeApiKeyError != null) throw writeApiKeyError!;
    apiKeyWrites.add((siteUrl, key));
    apiKeys[siteUrl] = key;
  }

  @override
  Future<void> deleteApiKey(String siteUrl) async {
    if (deleteApiKeyError != null) throw deleteApiKeyError!;
    apiKeys.remove(siteUrl);
  }
}
