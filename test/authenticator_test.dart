import 'dart:async';

import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/private_storage.dart';
import 'package:discourse_native/src/data/push_registration.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
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
          'read-push-client-id',
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
      expect(await authenticator.clientId(), isEmpty);
      expect(events, [
        'read-push-registration',
        'write-push-client-id:macos-apns-token',
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
        '${persist ? 'connect' : 'authorize'} registers push independently of request credentials',
        () async {
          final events = <String>[];
          final provider = _FakePushRegistrationProvider(null, events: events);
          final store = _FakeSecureStore(events: events);
          final protocol = _FakeProtocol();
          final authenticator = Authenticator(
            store: store,
            protocol: protocol,
            pushRegistrations: provider,
            keyPairGenerator: () async => _pair,
            nonceGenerator: () => 'nonce',
            launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
          );

          expect(await authenticator.clientId(), isEmpty);
          provider.value = _macosRegistration;

          final credentials = await (persist
              ? authenticator.connect(_site)
              : authenticator.authorize(_site));

          expect(credentials, same(_credentials));
          expect(protocol.clientId, _macosRegistration.clientId);
          expect(protocol.pushUrl, _macosRegistration.pushUrl);
          expect(store.apiKeyWrites, [if (persist) (_site, _credentials.key)]);
          expect(await authenticator.clientId(), isEmpty);
          expect(await authenticator.clientId(), isEmpty);
          expect(events.where((event) => event == 'read-push-registration'), [
            'read-push-registration',
          ]);
          expect(events.where((event) => event == 'read-client-id'), isEmpty);
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
        expect(await clientId, isEmpty);
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

  group('request identity across push registrations', () {
    test(
      'ordinary requests do not access push registration or ID storage',
      () async {
        final events = <String>[];
        final provider = _ControlledPushRegistrationProvider();
        final authenticator = Authenticator(
          store: _FakeSecureStore(events: events),
          pushRegistrations: provider,
        );

        expect(
          await Future.wait(List.generate(8, (_) => authenticator.clientId())),
          everyElement(isEmpty),
        );
        expect(provider.requests, isEmpty);
        expect(events, isEmpty);
      },
    );

    test(
      'an existing key never migrates to another build token, including concurrent requests',
      () async {
        final install = _Install();
        final associatedClient = <String, String>{
          'existing-key': 'production-token',
        };
        final existingClients = {'production-token', 'development-token'};
        var migrationAttempts = 0;
        final api = DiscourseApi(
          client: MockClient((request) async {
            expect(request.headers['User-Api-Key'], 'existing-key');
            final clientId = request.headers['User-Api-Client-Id'];
            if (clientId != null &&
                clientId.isNotEmpty &&
                clientId != associatedClient['existing-key']) {
              migrationAttempts++;
              // Mirrors UserApiKey#update_last_used: changing a key's client
              // inserts a new row without looking up an existing registration.
              if (!existingClients.add(clientId)) {
                return http.Response('duplicate client ID', 500);
              }
              associatedClient['existing-key'] = clientId;
            }
            return http.Response('{}', 200);
          }),
        );
        addTearDown(api.close);

        for (final token in [
          'development-token',
          'production-token',
          'rotated-token',
        ]) {
          install.pushClientIds.value = token;
          final provider = _FakePushRegistrationProvider(
            PushRegistration(
              clientId: token,
              pushUrl: PlatformPushRegistrationProvider.iosPushUrl,
            ),
          );
          final authenticator = Authenticator(
            store: install.open(),
            pushRegistrations: provider,
          );
          await Future.wait(
            List.generate(4, (_) async {
              await api.notificationTotals(
                siteUrl: _site,
                apiKey: 'existing-key',
                clientId: await authenticator.clientId(),
              );
            }),
          );
          expect(provider.reads, 0);
        }
        expect(migrationAttempts, 0);
        expect(associatedClient['existing-key'], 'production-token');
      },
    );

    test(
      'reconnection registers the current push token without migrating requests',
      () async {
        final install = _Install();
        for (final token in [
          'production-token',
          'development-token',
          'production-token',
        ]) {
          final protocol = _FakeProtocol();
          final authenticator = Authenticator(
            store: install.open(),
            protocol: protocol,
            pushRegistrations: _FakePushRegistrationProvider(
              PushRegistration(
                clientId: token,
                pushUrl: PlatformPushRegistrationProvider.iosPushUrl,
              ),
            ),
            keyPairGenerator: () async => _pair,
            nonceGenerator: () => 'nonce',
            launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
          );
          expect(await authenticator.authorize(_site), same(_credentials));
          expect(protocol.clientId, token);
          expect(protocol.pushUrl, PlatformPushRegistrationProvider.iosPushUrl);
          expect(install.pushClientIds.value, token);
          expect(await authenticator.clientId(), isEmpty);
        }
      },
    );

    test(
      'a relaunch without APNs uses the saved ID only during authorization',
      () async {
        final install = _Install()..pushClientIds.value = 'saved-token';
        final protocol = _FakeProtocol();
        final authenticator = Authenticator(
          store: install.open(),
          protocol: protocol,
          pushRegistrations: _FakePushRegistrationProvider(null),
          keyPairGenerator: () async => _pair,
          nonceGenerator: () => 'nonce',
          launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
        );
        expect(await authenticator.clientId(), isEmpty);
        await authenticator.authorize(_site);
        expect(protocol.clientId, 'saved-token');
        expect(protocol.pushUrl, isNull);
        expect(await authenticator.clientId(), isEmpty);
      },
    );

    test(
      'requests do not wait for an authorization to record its push token',
      () async {
        final gate = Completer<void>();
        final install = _Install()..pushClientIds.writeGate = gate;
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final protocol = _FakeProtocol();
        final authenticator = Authenticator(
          store: install.open(),
          protocol: protocol,
          pushRegistrations: _FakePushRegistrationProvider(_macosRegistration),
          keyPairGenerator: () async => _pair,
          nonceGenerator: () => 'nonce',
          launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
        );
        final pending = authenticator.authorize(_site);
        await install.pushClientIds.writeStarted.future;
        expect(await authenticator.clientId(), isEmpty);
        expect(protocol.clientId, isNull);
        gate.complete();
        await pending;
        expect(protocol.clientId, _macosRegistration.clientId);
      },
    );

    test(
      'authorization still works when the push token cannot be recorded',
      () async {
        final diagnostics = _RecordingDiagnosticsSink();
        addTearDown(DiagnosticsSink.install(diagnostics).close);
        final error = StateError('preferences unavailable');
        final install = _Install()..pushClientIds.writeError = error;
        final protocol = _FakeProtocol();
        final authenticator = Authenticator(
          store: install.open(),
          protocol: protocol,
          pushRegistrations: _FakePushRegistrationProvider(_macosRegistration),
          keyPairGenerator: () async => _pair,
          nonceGenerator: () => 'nonce',
          launcher: (_, _) async => 'discourse://auth_redirect?payload=reply',
        );
        await authenticator.authorize(_site);
        expect(protocol.clientId, _macosRegistration.clientId);
        expect(await authenticator.clientId(), isEmpty);
        expect(diagnostics.errors, [same(error)]);
        expect(diagnostics.operations, ['credentials.pushClientId']);
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
    expect(await authenticator.clientId(), isEmpty);
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
  _FakePushRegistrationProvider(this.value, {this.events});

  PushRegistration? value;
  final List<String>? events;
  int reads = 0;

  @override
  Future<PushRegistration?> registration() async {
    reads += 1;
    events?.add('read-push-registration');
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
    this.clientIdError,
    this.readApiKeyError,
    this.writeApiKeyError,
    this.deleteApiKeyError,
  });

  final List<String>? events;
  final Object? clientIdError;
  final Object? readApiKeyError;
  final Object? writeApiKeyError;
  final Object? deleteApiKeyError;

  final Map<String, String> apiKeys = {};
  final List<(String, String)> apiKeyWrites = [];
  String? pushClientId;

  @override
  Future<String> readOrCreateClientId() async {
    events?.add('read-client-id');
    if (clientIdError != null) throw clientIdError!;
    return 'client-id';
  }

  @override
  Future<String?> readPushClientId() async {
    events?.add('read-push-client-id');
    if (clientIdError != null) throw clientIdError!;
    return pushClientId;
  }

  @override
  Future<void> writePushClientId(String value) async {
    events?.add('write-push-client-id:$value');
    pushClientId = value;
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

/// One installation's preferences, reopened by each simulated launch.
final class _Install {
  final clientIds = _MemoryClientIds('install-id');
  final pushClientIds = _MemoryClientIds();

  SecureStore open() => SecureStore(
    storage: const _UnusedPrivateStorage(),
    clientIds: clientIds,
    pushClientIds: pushClientIds,
    tokenGenerator: () => throw StateError('must not generate'),
  );
}

final class _MemoryClientIds implements ClientIdPersistence {
  _MemoryClientIds([this.value]);

  String? value;
  int reads = 0;
  Object? writeError;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();

  @override
  Future<String?> read() async {
    reads += 1;
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (writeError case final error?) throw error;
    this.value = value;
  }
}

final class _UnusedPrivateStorage implements PrivateStorage {
  const _UnusedPrivateStorage();

  @override
  Future<String?> read(String key) => throw StateError('unexpected read');

  @override
  Future<void> write(String key, String value) =>
      throw StateError('unexpected write');

  @override
  Future<void> delete(String key) => throw StateError('unexpected delete');
}

final class _RecordingDiagnosticsSink implements DiagnosticsSink {
  final List<Object> errors = [];
  final List<String?> operations = [];

  @override
  void recordLog({
    required String name,
    String source = 'application',
    String? component,
    String? message,
    Map<String, Object?> attributes = const {},
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? operation,
    String? correlationId,
    bool handled = true,
    bool degraded = false,
  }) {}

  @override
  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  }) {
    errors.add(error);
    operations.add(operation);
  }
}
