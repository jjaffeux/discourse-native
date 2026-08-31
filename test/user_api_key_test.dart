import 'dart:convert';

import 'package:basic_utils/basic_utils.dart' show CryptoUtils;
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

/// Encrypts the way Discourse does: Ruby's `public_encrypt`, i.e. PKCS#1 v1.5.
String encryptLikeDiscourse(Map<String, dynamic> payload, String publicPem) {
  return encryptTextLikeDiscourse(jsonEncode(payload), publicPem);
}

String encryptTextLikeDiscourse(String payload, String publicPem) {
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(
      true,
      PublicKeyParameter<RSAPublicKey>(
        CryptoUtils.rsaPublicKeyFromPem(publicPem),
      ),
    );
  return base64Encode(cipher.process(utf8.encode(payload)));
}

/// Ruby's `Base64.encode64` wraps output at 60 characters and appends a final
/// newline. Discourse uses this form for the callback payload.
String wrapLikeDiscourseRuby(String payload) {
  final wrapped = StringBuffer();
  for (var offset = 0; offset < payload.length; offset += 60) {
    final candidateEnd = offset + 60;
    final end = candidateEnd < payload.length ? candidateEnd : payload.length;
    wrapped.writeln(payload.substring(offset, end));
  }
  return wrapped.toString();
}

void main() {
  const protocol = UserApiKeyProtocol();

  // Generating 2048-bit RSA is slow; one pair for the whole file.
  late AuthKeyPair pair;
  setUpAll(() => pair = AuthKeyPair.generate());

  group('authUrl', () {
    test('carries everything the site needs to answer', () {
      final url = protocol.authUrl(
        siteUrl: 'https://meta.discourse.org',
        publicKeyPem:
            '-----BEGIN PUBLIC KEY-----\nabc\n-----END PUBLIC KEY-----',
        nonce: 'nonce-123',
        clientId: 'client-abc',
        applicationName: 'Discourse Native',
      );

      expect(url.path, '/user-api-key/new');
      expect(url.origin, 'https://meta.discourse.org');
      expect(url.queryParameters['nonce'], 'nonce-123');
      expect(url.queryParameters['client_id'], 'client-abc');
      expect(url.queryParameters['auth_redirect'], 'discourse://auth_redirect');
      expect(url.queryParameters['scopes'], contains('session_info'));
      expect(url.queryParameters, isNot(contains('push_url')));
      // The PEM survives being put through query encoding.
      expect(url.queryParameters['public_key'], contains('BEGIN PUBLIC KEY'));
    });

    test('registers an optional push provider with the site', () {
      final url = protocol.authUrl(
        siteUrl: 'https://meta.discourse.org',
        publicKeyPem: 'public',
        nonce: 'nonce',
        clientId: 'macos-apns-token',
        applicationName: 'Discourse Native',
        pushUrl: 'https://api.discourse.org/api/publish_native_macos',
      );

      expect(url.queryParameters['client_id'], 'macos-apns-token');
      expect(
        url.queryParameters['push_url'],
        'https://api.discourse.org/api/publish_native_macos',
      );
    });

    test('anchors the endpoint at the site origin', () {
      final url = protocol.authUrl(
        siteUrl: 'https://forum.example:8443/old/path?stale=true#fragment',
        publicKeyPem: 'public',
        nonce: 'nonce',
        clientId: 'client',
        applicationName: 'App',
      );

      expect(url.origin, 'https://forum.example:8443');
      expect(url.path, '/user-api-key/new');
      expect(url.fragment, isEmpty);
      expect(url.queryParameters, isNot(contains('stale')));
    });

    test('rejects credentials embedded in the stored site URL', () {
      expect(
        () => protocol.authUrl(
          siteUrl: 'https://reader:password@forum.example',
          publicKeyPem: 'public',
          nonce: 'nonce',
          clientId: 'client',
          applicationName: 'App',
        ),
        throwsA(isA<UnsafeHttpTransportException>()),
      );
    });
  });

  group('payloadFromCallback', () {
    test('pulls the payload out of the redirect', () {
      expect(
        protocol.payloadFromCallback(
          'discourse://auth_redirect?payload=abc%3D',
        ),
        'abc=',
      );
    });

    test('rejects a callback with no payload', () {
      expect(
        () => protocol.payloadFromCallback('discourse://auth_redirect'),
        throwsA(isA<UserApiAuthException>()),
      );
    });

    test('rejects a callback from a different scheme or host', () {
      for (final callback in [
        'https://auth_redirect?payload=abc',
        'discourse://different?payload=abc',
      ]) {
        expect(
          () => protocol.payloadFromCallback(callback),
          throwsA(
            isA<UserApiAuthException>().having(
              (error) => error.failure,
              'failure',
              UserApiAuthFailure.badReply,
            ),
          ),
          reason: callback,
        );
      }
    });

    test('reports a malformed callback as a bad reply', () {
      expect(
        () => protocol.payloadFromCallback('discourse://[invalid?payload=abc'),
        throwsA(
          isA<UserApiAuthException>().having(
            (error) => error.failure,
            'failure',
            UserApiAuthFailure.badReply,
          ),
        ),
      );
    });

    test('accepts a callback at the protocol boundary', () {
      const prefix = 'discourse://auth_redirect?payload=abc%3D#';
      final callback = prefix.padRight(
        UserApiKeyProtocol.maximumCallbackUrlCodeUnits,
        'x',
      );

      expect(
        callback,
        hasLength(UserApiKeyProtocol.maximumCallbackUrlCodeUnits),
      );
      expect(protocol.payloadFromCallback(callback), 'abc=');
    });

    test('rejects an oversized callback without exposing its payload', () {
      const secret = 'must-not-enter-diagnostics';
      const prefix = 'discourse://auth_redirect?payload=$secret#';
      final callback = prefix.padRight(
        UserApiKeyProtocol.maximumCallbackUrlCodeUnits + 1,
        'x',
      );

      expect(
        () => protocol.payloadFromCallback(callback),
        throwsA(
          isA<UserApiAuthException>()
              .having(
                (error) => error.failure,
                'failure',
                UserApiAuthFailure.badReply,
              )
              .having(
                (error) => error.detail ?? '',
                'detail',
                allOf(
                  'callback URL exceeds protocol limit',
                  isNot(contains(secret)),
                ),
              ),
        ),
      );
    });
  });

  group('decodePayload', () {
    test('decrypts a reply produced the way Discourse produces it', () {
      final payload = wrapLikeDiscourseRuby(
        encryptLikeDiscourse({
          'key': 'the-api-key',
          'nonce': 'nonce-123',
          'push': false,
          'api': 4,
        }, pair.publicPem),
      );

      expect(
        payload.replaceAll('\n', ''),
        hasLength(UserApiKeyProtocol.maximumPayloadBase64Characters),
      );

      final credentials = protocol.decodePayload(
        payload: payload,
        privateKeyPem: pair.privatePem,
        expectedNonce: 'nonce-123',
      );

      expect(credentials.key, 'the-api-key');
      expect(credentials.apiVersion, 4);
      expect(credentials.push, isFalse);
    });

    test('rejects more than one block of significant Base64 input', () {
      final payload = List.filled(
        UserApiKeyProtocol.maximumPayloadBase64Characters + 1,
        'A',
      ).join();

      expect(
        () => protocol.decodePayload(
          payload: payload,
          privateKeyPem: pair.privatePem,
          expectedNonce: 'nonce-123',
        ),
        throwsA(
          isA<UserApiAuthException>().having(
            (error) => error.detail,
            'detail',
            contains('exceeds one RSA block'),
          ),
        ),
      );
    });

    test('rejects decoded ciphertexts that are not exactly one block', () {
      for (final byteLength in [
        UserApiKeyProtocol.encryptedPayloadBytes - 1,
        UserApiKeyProtocol.encryptedPayloadBytes + 1,
      ]) {
        final payload = base64Encode(List<int>.filled(byteLength, 0));

        expect(
          () => protocol.decodePayload(
            payload: payload,
            privateKeyPem: pair.privatePem,
            expectedNonce: 'nonce-123',
          ),
          throwsA(
            isA<UserApiAuthException>().having(
              (error) => error.detail,
              'detail',
              contains('exactly one RSA block'),
            ),
          ),
          reason: '$byteLength bytes',
        );
      }
    });

    test('rejects a multi-block ciphertext before decryption', () {
      final payload = base64Encode(
        List<int>.filled(UserApiKeyProtocol.encryptedPayloadBytes * 2, 0),
      );

      expect(
        () => protocol.decodePayload(
          payload: payload,
          privateKeyPem: pair.privatePem,
          expectedNonce: 'nonce-123',
        ),
        throwsA(
          isA<UserApiAuthException>().having(
            (error) => error.detail,
            'detail',
            contains('exceeds one RSA block'),
          ),
        ),
      );
    });

    test('a malformed decrypted reply never exposes its API key', () {
      const secret = 'must-not-enter-diagnostics';
      final payload = encryptTextLikeDiscourse(
        '{"key":"$secret","nonce":"nonce-123"',
        pair.publicPem,
      );

      expect(
        () => protocol.decodePayload(
          payload: payload,
          privateKeyPem: pair.privatePem,
          expectedNonce: 'nonce-123',
        ),
        throwsA(
          isA<UserApiAuthException>()
              .having(
                (error) => error.detail,
                'detail',
                isNot(contains(secret)),
              )
              .having((error) => '$error', 'toString', isNot(contains(secret))),
        ),
      );
    });

    test('rejects a reply answering a different nonce', () {
      final payload = encryptLikeDiscourse({
        'key': 'the-api-key',
        'nonce': 'someone-elses-nonce',
        'api': 4,
      }, pair.publicPem);

      expect(
        () => protocol.decodePayload(
          payload: payload,
          privateKeyPem: pair.privatePem,
          expectedNonce: 'nonce-123',
        ),
        throwsA(
          isA<UserApiAuthException>().having(
            (e) => e.failure,
            'failure',
            UserApiAuthFailure.badReply,
          ),
        ),
      );
    });

    test('rejects a reply encrypted for a different key pair', () {
      final other = AuthKeyPair.generate();
      final payload = encryptLikeDiscourse({
        'key': 'the-api-key',
        'nonce': 'nonce-123',
        'api': 4,
      }, other.publicPem);

      expect(
        () => protocol.decodePayload(
          payload: payload,
          privateKeyPem: pair.privatePem,
          expectedNonce: 'nonce-123',
        ),
        throwsA(isA<UserApiAuthException>()),
      );
    });

    test('rejects a reply with no key', () {
      final payload = encryptLikeDiscourse({
        'nonce': 'nonce-123',
        'api': 4,
      }, pair.publicPem);

      expect(
        () => protocol.decodePayload(
          payload: payload,
          privateKeyPem: pair.privatePem,
          expectedNonce: 'nonce-123',
        ),
        throwsA(isA<UserApiAuthException>()),
      );
    });

    test('reports a key with the wrong type as a bad reply', () {
      final payload = encryptLikeDiscourse({
        'key': 123,
        'nonce': 'nonce-123',
        'api': 4,
      }, pair.publicPem);

      expect(
        () => protocol.decodePayload(
          payload: payload,
          privateKeyPem: pair.privatePem,
          expectedNonce: 'nonce-123',
        ),
        throwsA(
          isA<UserApiAuthException>().having(
            (error) => error.failure,
            'failure',
            UserApiAuthFailure.badReply,
          ),
        ),
      );
    });
  });
}
