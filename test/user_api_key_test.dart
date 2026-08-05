import 'dart:convert';

import 'package:basic_utils/basic_utils.dart' show CryptoUtils;
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

/// Encrypts the way Discourse does: Ruby's `public_encrypt`, i.e. PKCS#1 v1.5.
String encryptLikeDiscourse(Map<String, dynamic> payload, String publicPem) {
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(
      true,
      PublicKeyParameter<RSAPublicKey>(CryptoUtils.rsaPublicKeyFromPem(publicPem)),
    );
  return base64Encode(cipher.process(utf8.encode(jsonEncode(payload))));
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
        publicKeyPem: '-----BEGIN PUBLIC KEY-----\nabc\n-----END PUBLIC KEY-----',
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
      // The PEM survives being put through query encoding.
      expect(url.queryParameters['public_key'], contains('BEGIN PUBLIC KEY'));
    });
  });

  group('payloadFromCallback', () {
    test('pulls the payload out of the redirect', () {
      expect(
        protocol.payloadFromCallback('discourse://auth_redirect?payload=abc%3D'),
        'abc=',
      );
    });

    test('rejects a callback with no payload', () {
      expect(
        () => protocol.payloadFromCallback('discourse://auth_redirect'),
        throwsA(isA<UserApiAuthException>()),
      );
    });
  });

  group('decodePayload', () {
    test('decrypts a reply produced the way Discourse produces it', () {
      final payload = encryptLikeDiscourse({
        'key': 'the-api-key',
        'nonce': 'nonce-123',
        'push': false,
        'api': 4,
      }, pair.publicPem);

      final credentials = protocol.decodePayload(
        payload: payload,
        privateKey: pair.privateKey,
        expectedNonce: 'nonce-123',
      );

      expect(credentials.key, 'the-api-key');
      expect(credentials.apiVersion, 4);
      expect(credentials.push, isFalse);
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
          privateKey: pair.privateKey,
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
          privateKey: pair.privateKey,
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
          privateKey: pair.privateKey,
          expectedNonce: 'nonce-123',
        ),
        throwsA(isA<UserApiAuthException>()),
      );
    });
  });
}
