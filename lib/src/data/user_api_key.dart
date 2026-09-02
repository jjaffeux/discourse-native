import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' show CryptoUtils;
import 'package:pointycastle/export.dart';

import '../diagnostics/diagnostic_error_cause.dart';
import 'http_transport.dart';

class UserApiCredentials {
  const UserApiCredentials({
    required this.key,
    required this.apiVersion,
    required this.push,
  });

  final String key;

  final int apiVersion;
  final bool push;
}

enum UserApiAuthFailure {
  cancelled,

  /// Distinct from [cancelled] because the user did not choose it and trying
  /// again will not help. On Linux this is a missing or broken WebKitGTK;
  /// anywhere else it is a plugin that did not answer.
  launchFailed,

  /// The reply did not decrypt, or its nonce was not the one we sent — either
  /// a mismatched key pair or a reply we did not ask for.
  badReply,
}

class UserApiAuthException implements Exception, DiagnosticErrorCause {
  const UserApiAuthException(this.failure, [this.detail])
    : cause = null,
      causeStackTrace = null;

  const UserApiAuthException.caused(
    this.failure,
    this.detail,
    this.cause,
    this.causeStackTrace,
  );

  final UserApiAuthFailure failure;
  final String? detail;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  Object get diagnosticCause => cause ?? this;

  @override
  StackTrace? get diagnosticCauseStackTrace => causeStackTrace;

  String get message => switch (failure) {
    UserApiAuthFailure.cancelled => 'Connection cancelled.',
    UserApiAuthFailure.launchFailed =>
      'Could not open the sign-in window. Check that a web view is installed.',
    UserApiAuthFailure.badReply =>
      "The site's reply could not be verified. Please try again.",
  };

  @override
  String toString() => 'UserApiAuthException($failure)';
}

/// Mirrors DiscourseMobile's `SiteManager.generateAuthURL` /
/// `handleAuthPayload`: we send a public key and a nonce, the site sends back
/// an RSA-encrypted payload containing the API key and our nonce.
class UserApiKeyProtocol {
  const UserApiKeyProtocol();

  static const String redirectScheme = 'discourse';
  static const String redirectHost = 'auth_redirect';
  static const String redirectUrl = '$redirectScheme://$redirectHost';

  /// The key size used by the client and therefore the size of the one RSA
  /// ciphertext block returned by Discourse.
  static const int rsaKeyBits = 2048;
  static const int encryptedPayloadBytes = rsaKeyBits ~/ 8;

  /// Base64 expands the server's single 256-byte ciphertext block to 344
  /// significant characters. Ruby's `Base64.encode64` also inserts newlines,
  /// which are ignored below.
  static const int maximumPayloadBase64Characters =
      ((encryptedPayloadBytes + 2) ~/ 3) * 4;

  /// A legal callback is comfortably below this even if every character in
  /// Ruby's 350-code-unit wrapped Base64 output is percent-escaped.
  static const int maximumCallbackUrlCodeUnits = 2048;

  /// `session_info` gives us the username; `read`/`write` are what a client
  /// needs to be useful. `notifications` also authorizes an allowed push URL,
  /// so a separate `push` scope is unnecessary.
  static const String scopes = 'read,write,session_info,notifications';

  Uri authUrl({
    required String siteUrl,
    required String publicKeyPem,
    required String nonce,
    required String clientId,
    required String applicationName,
    String? pushUrl,
  }) {
    final site = requireSafeHttpUrl(Uri.parse(siteUrl));
    return site.replace(
      path: '/user-api-key/new',
      fragment: '',
      queryParameters: {
        'application_name': applicationName,
        'client_id': clientId,
        'push_url': ?pushUrl,
        'scopes': scopes,
        'public_key': publicKeyPem,
        'nonce': nonce,
        'auth_redirect': redirectUrl,
      },
    );
  }

  String payloadFromCallback(String callbackUrl) {
    if (callbackUrl.length > maximumCallbackUrlCodeUnits) {
      throw const UserApiAuthException(
        UserApiAuthFailure.badReply,
        'callback URL exceeds protocol limit',
      );
    }

    final Uri callback;
    final String? payload;
    try {
      callback = Uri.parse(callbackUrl);
      if (callback.scheme != redirectScheme || callback.host != redirectHost) {
        throw const UserApiAuthException(
          UserApiAuthFailure.badReply,
          'unexpected callback URL',
        );
      }
      // Percent-escapes are decoded when the query is read, not when the URL
      // is parsed, so an undecodable one fails here.
      payload = callback.queryParameters['payload'];
    } on FormatException catch (error) {
      throw UserApiAuthException(
        UserApiAuthFailure.badReply,
        _safeAuthFailureDetail(error),
      );
    }

    if (payload == null || payload.isEmpty) {
      throw const UserApiAuthException(
        UserApiAuthFailure.badReply,
        'no payload in callback',
      );
    }
    return payload;
  }

  UserApiCredentials decodePayload({
    required String payload,
    required String privateKeyPem,
    required String expectedNonce,
  }) {
    final Map<String, dynamic> decoded;
    try {
      final cipherText = base64Decode(_compactPayload(payload));
      if (cipherText.length != encryptedPayloadBytes) {
        throw const FormatException(
          'encrypted payload must contain exactly one RSA block',
        );
      }
      final privateKey = CryptoUtils.rsaPrivateKeyFromPem(privateKeyPem);
      final plain = _decryptPkcs1(cipherText, privateKey);
      decoded = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } catch (error) {
      // The exception may retain the decrypted JSON as FormatException.source,
      // including the API key. Keep only classification and a source-free
      // parser message at this trust boundary.
      throw UserApiAuthException(
        UserApiAuthFailure.badReply,
        _safeAuthFailureDetail(error),
      );
    }

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
    return cipher.process(cipherText);
  }

  String _compactPayload(String payload) {
    // decodePayload is public, so bound a direct caller as well as values that
    // already passed through payloadFromCallback.
    if (payload.length > maximumCallbackUrlCodeUnits) {
      throw const FormatException('encrypted payload exceeds protocol limit');
    }

    final compact = StringBuffer();
    var significantCharacters = 0;
    for (final codeUnit in payload.codeUnits) {
      if (_isWhitespaceCodeUnit(codeUnit)) continue;

      significantCharacters += 1;
      if (significantCharacters > maximumPayloadBase64Characters) {
        throw const FormatException('encrypted payload exceeds one RSA block');
      }
      compact.writeCharCode(codeUnit);
    }
    return compact.toString();
  }
}

// Dart regular expressions follow ECMAScript's definition of `\s`. Keeping
// the same set here preserves accepted wrapped payloads without allocating an
// unbounded replacement string before checking the protocol limit.
bool _isWhitespaceCodeUnit(int codeUnit) =>
    (codeUnit >= 0x0009 && codeUnit <= 0x000d) ||
    codeUnit == 0x0020 ||
    codeUnit == 0x00a0 ||
    codeUnit == 0x1680 ||
    (codeUnit >= 0x2000 && codeUnit <= 0x200a) ||
    codeUnit == 0x2028 ||
    codeUnit == 0x2029 ||
    codeUnit == 0x202f ||
    codeUnit == 0x205f ||
    codeUnit == 0x3000 ||
    codeUnit == 0xfeff;

String _safeAuthFailureDetail(Object error) => switch (error) {
  FormatException(:final message, :final offset) =>
    'FormatException: $message${offset == null ? '' : ' at $offset'}',
  _ => error.runtimeType.toString(),
};

class AuthKeyPair {
  const AuthKeyPair({required this.publicPem, required this.privatePem});

  final String publicPem;
  final String privatePem;

  RSAPrivateKey get privateKey => CryptoUtils.rsaPrivateKeyFromPem(privatePem);

  /// 2048-bit RSA generation takes seconds — call this inside an isolate so it
  /// does not stall the frame loop.
  static AuthKeyPair generate() {
    final pair = CryptoUtils.generateRSAKeyPair(
      keySize: UserApiKeyProtocol.rsaKeyBits,
    );
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
