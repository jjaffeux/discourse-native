import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'secure_store.dart';
import 'user_api_key.dart';

/// Opens [url] in a web auth session and returns the callback URL the site
/// redirects to. Injectable so the flow can be tested without a browser.
typedef WebAuthLauncher =
    Future<String> Function(String url, String callbackScheme);

Future<String> _launchWebAuth(String url, String callbackScheme) =>
    FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: callbackScheme);

/// Runs the user API key handshake and keeps what comes back.
class Authenticator {
  Authenticator({
    SecureStore? store,
    WebAuthLauncher? launcher,
    this.protocol = const UserApiKeyProtocol(),
    this.applicationName = 'Discourse Native',
  }) : store = store ?? SecureStore(),
       _launch = launcher ?? _launchWebAuth;

  final SecureStore store;
  final UserApiKeyProtocol protocol;
  final String applicationName;
  final WebAuthLauncher _launch;

  /// Sends the user to [siteUrl] to authorize, then stores the key it returns.
  Future<UserApiCredentials> connect(String siteUrl) async {
    final pair = await _ensureKeyPair();
    final clientId = await store.readOrCreateClientId();
    final nonce = SecureStore.randomToken();

    final url = protocol.authUrl(
      siteUrl: siteUrl,
      publicKeyPem: pair.publicPem,
      nonce: nonce,
      clientId: clientId,
      applicationName: applicationName,
    );

    final String callback;
    try {
      callback = await _launch(
        url.toString(),
        UserApiKeyProtocol.redirectScheme,
      );
    } on UserApiAuthException {
      rethrow;
    } catch (e) {
      // The plugin throws when the user dismisses the browser.
      throw UserApiAuthException(UserApiAuthFailure.cancelled, '$e');
    }

    final credentials = protocol.decodePayload(
      payload: protocol.payloadFromCallback(callback),
      privateKey: pair.privateKey,
      expectedNonce: nonce,
    );

    await store.writeApiKey(siteUrl, credentials.key);
    return credentials;
  }

  Future<String?> apiKeyFor(String siteUrl) => store.readApiKey(siteUrl);

  /// This install's client id.
  ///
  /// Exposed here rather than reached for through [store], because callers want
  /// the identity, not the storage it happens to live in.
  Future<String> clientId() => store.readOrCreateClientId();

  Future<void> disconnect(String siteUrl) => store.deleteApiKey(siteUrl);

  /// The key pair is per-install, not per-site: generated once, reused for
  /// every site the user connects.
  Future<AuthKeyPair> _ensureKeyPair() async {
    final existing = await store.readKeyPair();
    if (existing != null) return existing;

    // 2048-bit RSA takes seconds, so keep it off the frame loop.
    final pems = await compute(_generatePems, 0);
    final pair = AuthKeyPair(publicPem: pems[0], privatePem: pems[1]);
    await store.writeKeyPair(pair);
    return pair;
  }
}

/// Top-level so it can run in an isolate. Returns plain strings rather than
/// the key pair object, which keeps what crosses the isolate boundary simple.
List<String> _generatePems(int _) {
  final pair = AuthKeyPair.generate();
  return [pair.publicPem, pair.privatePem];
}
