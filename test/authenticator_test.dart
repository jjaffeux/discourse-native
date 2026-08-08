import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';
const _pair = AuthKeyPair(publicPem: 'public-pem', privatePem: 'private-pem');
const _credentials = UserApiCredentials(
  key: 'api-key',
  apiVersion: 4,
  push: false,
);

void main() {
  group('Authenticator.connect', () {
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
      var generationCount = 0;
      final authenticator = Authenticator(
        store: store,
        protocol: _FakeProtocol(),
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
      expect(store.apiKeys.keys, {
        'https://one.example',
        'https://two.example',
      });
    });

    test(
      'does not open the browser when the client id cannot be read',
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
      final authenticator = Authenticator(
        store: store,
        protocol: _FakeProtocol(),
        launcher: (_, _) async =>
            throw PlatformException(code: 'UNAVAILABLE', message: 'no browser'),
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
      final protocolError = const UserApiAuthException(
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

  @override
  Uri authUrl({
    required String siteUrl,
    required String publicKeyPem,
    required String nonce,
    required String clientId,
    required String applicationName,
  }) {
    events?.add('auth-url');
    this.siteUrl = siteUrl;
    this.publicKeyPem = publicKeyPem;
    this.nonce = nonce;
    this.clientId = clientId;
    this.applicationName = applicationName;
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

  @override
  Future<String> readOrCreateClientId() async {
    events?.add('read-client-id');
    if (clientIdError != null) throw clientIdError!;
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
    apiKeys[siteUrl] = key;
  }

  @override
  Future<void> deleteApiKey(String siteUrl) async {
    if (deleteApiKeyError != null) throw deleteApiKeyError!;
    apiKeys.remove(siteUrl);
  }
}
