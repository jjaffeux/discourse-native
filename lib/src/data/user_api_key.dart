import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' show CryptoUtils;
import 'package:pointycastle/export.dart';

/// What a site hands back once the user authorizes the app.
class UserApiCredentials {
  const UserApiCredentials({
    required this.key,
    required this.apiVersion,
    required this.push,
  });

  /// Sent as the `User-Api-Key` header on every authenticated request.
  final String key;

  final int apiVersion;
  final bool push;
}

enum UserApiAuthFailure {
  /// The user closed the browser without authorizing.
  cancelled,

  /// The browser never opened, so the user was never asked.
  ///
  /// Distinct from [cancelled] because the user did not choose it and trying
  /// again will not help. On Linux this is a missing or broken WebKitGTK;
  /// anywhere else it is a plugin that did not answer.
  launchFailed,

  /// The reply did not decrypt, or its nonce was not the one we sent — either
  /// a mismatched key pair or a reply we did not ask for.
  badReply,
}

class UserApiAuthException implements Exception {
  const UserApiAuthException(this.failure, [this.detail]);

  final UserApiAuthFailure failure;
  final String? detail;

  String get message => switch (failure) {
    UserApiAuthFailure.cancelled => 'Connection cancelled.',
    UserApiAuthFailure.launchFailed =>
      'Could not open the sign-in window. Check that a web view is installed.',
    UserApiAuthFailure.badReply =>
      "The site's reply could not be verified. Please try again.",
  };

  @override
  String toString() => 'UserApiAuthException($failure, $detail)';
}

/// Builds and interprets Discourse's user API key handshake.
///
/// Mirrors DiscourseMobile's `SiteManager.generateAuthURL` /
/// `handleAuthPayload`: we send a public key and a nonce, the site sends back
/// an RSA-encrypted payload containing the API key and our nonce.
///
/// Pure: no I/O, no plugins, so the whole handshake is testable.
class UserApiKeyProtocol {
  const UserApiKeyProtocol();

  static const String redirectScheme = 'discourse';
  static const String redirectHost = 'auth_redirect';
  static const String redirectUrl = '$redirectScheme://$redirectHost';

  /// `session_info` gives us the username; `read`/`write` are what a client
  /// needs to be useful. No `push` scope — there is no push server yet.
  static const String scopes = 'read,write,session_info,notifications';

  Uri authUrl({
    required String siteUrl,
    required String publicKeyPem,
    required String nonce,
    required String clientId,
    required String applicationName,
  }) {
    return Uri.parse(siteUrl).replace(
      path: '/user-api-key/new',
      fragment: '',
      queryParameters: {
        'application_name': applicationName,
        'client_id': clientId,
        'scopes': scopes,
        'public_key': publicKeyPem,
        'nonce': nonce,
        'auth_redirect': redirectUrl,
      },
    );
  }

  /// Pulls the `payload` parameter out of the redirect we were sent back to.
  String payloadFromCallback(String callbackUrl) {
    final Uri callback;
    try {
      callback = Uri.parse(callbackUrl);
    } on FormatException catch (error) {
      throw UserApiAuthException(UserApiAuthFailure.badReply, '$error');
    }

    if (callback.scheme != redirectScheme || callback.host != redirectHost) {
      throw const UserApiAuthException(
        UserApiAuthFailure.badReply,
        'unexpected callback URL',
      );
    }

    final payload = callback.queryParameters['payload'];
    if (payload == null || payload.isEmpty) {
      throw const UserApiAuthException(
        UserApiAuthFailure.badReply,
        'no payload in callback',
      );
    }
    return payload;
  }

  /// Decrypts the reply and checks it answers the nonce we sent.
  UserApiCredentials decodePayload({
    required String payload,
    required String privateKeyPem,
    required String expectedNonce,
  }) {
    final Map<String, dynamic> decoded;
    try {
      final cipherText = base64Decode(payload.replaceAll(RegExp(r'\s'), ''));
      final privateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
      final plain = _decryptPkcs1(cipherText, privateKey);
      decoded = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } catch (e) {
      throw UserApiAuthException(UserApiAuthFailure.badReply, '$e');
    }

    // Guards against a reply being replayed at us from somewhere else.
    if (decoded['nonce'] != expectedNonce) {
      throw const UserApiAuthException(
        UserApiAuthFailure.badReply,
        'nonce mismatch',
      );
    }

    final key = decoded['key'];
    if (key is! String || key.isEmpty) {
      throw const UserApiAuthException(
        UserApiAuthFailure.badReply,
        'no key in payload',
      );
    }

    return UserApiCredentials(
      key: key,
      apiVersion: switch (decoded['api']) {
        final int v => v,
        final String v => int.tryParse(v) ?? 0,
        _ => 0,
      },
      push: decoded['push'] == true,
    );
  }

  /// Discourse encrypts with Ruby's `public_encrypt`, which is PKCS#1 v1.5 —
  /// not OAEP, and not the unpadded RSA that `basic_utils` would give us.
  Uint8List _decryptPkcs1(Uint8List cipherText, RSAPrivateKey privateKey) {
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    final out = <int>[];
    final blockSize = cipher.inputBlockSize;
    for (var offset = 0; offset < cipherText.length; offset += blockSize) {
      final end = (offset + blockSize).clamp(0, cipherText.length);
      out.addAll(cipher.process(cipherText.sublist(offset, end)));
    }
    return Uint8List.fromList(out);
  }
}

/// An RSA key pair in the PEM forms we need: the public one goes to the site,
/// the private one stays in the keychain.
class AuthKeyPair {
  const AuthKeyPair({required this.publicPem, required this.privatePem});

  final String publicPem;
  final String privatePem;

  RSAPrivateKey get privateKey => CryptoUtils.rsaPrivateKeyFromPem(privatePem);

  /// 2048-bit RSA generation takes seconds — call this inside an isolate so it
  /// does not stall the frame loop.
  static AuthKeyPair generate() {
    final pair = CryptoUtils.generateRSAKeyPair();
    return AuthKeyPair(
      publicPem: CryptoUtils.encodeRSAPublicKeyToPem(
        pair.publicKey as RSAPublicKey,
      ),
      privatePem: CryptoUtils.encodeRSAPrivateKeyToPem(
        pair.privateKey as RSAPrivateKey,
      ),
    );
  }
}
