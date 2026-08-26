import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'api_credentials.dart';
import 'push_registration.dart';
import 'secure_store.dart';
import 'user_api_key.dart';

/// Opens [url] in a web auth session and returns the callback URL the site
/// redirects to. Injectable so the flow can be tested without a browser.
typedef WebAuthLauncher =
    Future<String> Function(String url, String callbackScheme);

typedef AuthKeyPairGenerator = Future<AuthKeyPair> Function();

Future<String> _launchWebAuth(String url, String callbackScheme) =>
    FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: callbackScheme);

/// Runs the user API key handshake and keeps what comes back.
class Authenticator implements ApiCredentialReader {
  Authenticator({
    SecureStore? store,
    WebAuthLauncher? launcher,
    AuthKeyPairGenerator? keyPairGenerator,
    String Function()? nonceGenerator,
    PushRegistrationProvider? pushRegistrations,
    this.protocol = const UserApiKeyProtocol(),
    this.applicationName = 'Discourse Native',
  }) : store = store ?? SecureStore(),
       _launch = launcher ?? _launchWebAuth,
       _generateKeyPair = keyPairGenerator ?? _generateAuthKeyPair,
       _generateNonce = nonceGenerator ?? SecureStore.randomToken,
       _pushRegistrations =
           pushRegistrations ?? PlatformPushRegistrationProvider();

  final SecureStore store;
  final UserApiKeyProtocol protocol;
  final String applicationName;
  final WebAuthLauncher _launch;
  final AuthKeyPairGenerator _generateKeyPair;
  final String Function() _generateNonce;
  final PushRegistrationProvider _pushRegistrations;
  final Map<String, Object> _connectionGenerations = {};

  static const _supersededConnection = UserApiAuthException(
    UserApiAuthFailure.cancelled,
    'connection superseded',
  );

  /// Sends the user to [siteUrl] to authorize, then stores the key it returns.
  Future<UserApiCredentials> connect(String siteUrl) async {
    final generation = Object();
    _connectionGenerations[siteUrl] = generation;
    try {
      final pushRegistration = await _pushRegistrations.registration();
      final clientId =
          pushRegistration?.clientId ?? await store.readOrCreateClientId();
      _ensureCurrent(siteUrl, generation);
      // The private half is needed only to decrypt this callback. Keeping it
      // transient avoids persisting another secret and prevents one pair from
      // becoming a permanent identity shared by every connected site.
      final pair = await _generateKeyPair();
      _ensureCurrent(siteUrl, generation);
      final nonce = _generateNonce();

      final url = protocol.authUrl(
        siteUrl: siteUrl,
        publicKeyPem: pair.publicPem,
        nonce: nonce,
        clientId: clientId,
        applicationName: applicationName,
        pushUrl: pushRegistration?.pushUrl,
      );

      final String callback;
      try {
        callback = await _launch(
          url.toString(),
          UserApiKeyProtocol.redirectScheme,
        );
      } on UserApiAuthException {
        rethrow;
      } on PlatformException catch (e, stackTrace) {
        // Every implementation agrees on this code when the user dismisses the
        // browser: the ASWebAuthenticationSession bridges on iOS and macOS, the
        // auth tab on Android, and both the webview and the loopback server on
        // Linux and Windows. Anything else means the session never got as far as
        // showing a page, which the user cannot fix by trying again — so it has
        // to be said out loud rather than folded into a silent cancellation.
        final failure = e.code == 'CANCELED'
            ? UserApiAuthFailure.cancelled
            : UserApiAuthFailure.launchFailed;
        if (failure == UserApiAuthFailure.cancelled) {
          throw UserApiAuthException(failure, '${e.code}: ${e.message}');
        }
        throw UserApiAuthException.caused(
          failure,
          '${e.code}: ${e.message}',
          e,
          stackTrace,
        );
      } catch (e, stackTrace) {
        throw UserApiAuthException.caused(
          UserApiAuthFailure.launchFailed,
          '$e',
          e,
          stackTrace,
        );
      }

      _ensureCurrent(siteUrl, generation);
      final credentials = protocol.decodePayload(
        payload: protocol.payloadFromCallback(callback),
        privateKeyPem: pair.privatePem,
        expectedNonce: nonce,
      );
      _ensureCurrent(siteUrl, generation);

      await store.writeApiKey(siteUrl, credentials.key);
      _ensureCurrent(siteUrl, generation);
      return credentials;
    } catch (_) {
      if (!_isCurrent(siteUrl, generation)) throw _supersededConnection;
      rethrow;
    } finally {
      if (_isCurrent(siteUrl, generation)) {
        _connectionGenerations.remove(siteUrl);
      }
    }
  }

  bool _isCurrent(String siteUrl, Object generation) =>
      identical(_connectionGenerations[siteUrl], generation);

  void _ensureCurrent(String siteUrl, Object generation) {
    if (!_isCurrent(siteUrl, generation)) throw _supersededConnection;
  }

  @override
  Future<String?> apiKeyFor(String siteUrl) => store.readApiKey(siteUrl);

  /// This install's client id.
  ///
  /// Exposed here rather than reached for through [store], because callers want
  /// the identity, not the storage it happens to live in.
  @override
  Future<String> clientId() async {
    final pushRegistration = await _pushRegistrations.registration();
    if (pushRegistration != null) return pushRegistration.clientId;
    return store.readOrCreateClientId();
  }

  Future<void> disconnect(String siteUrl) {
    // Invalidate before the platform delete suspends. A browser callback which
    // was already queued must not be able to recreate the credential after
    // this operation requested the disconnected state.
    _connectionGenerations.remove(siteUrl);
    return store.deleteApiKey(siteUrl);
  }
}

Future<AuthKeyPair> _generateAuthKeyPair() async {
  final pems = await compute(_generatePems, 0);
  return AuthKeyPair(publicPem: pems[0], privatePem: pems[1]);
}

/// Top-level so it can run in an isolate. Returns plain strings rather than
/// the key pair object, which keeps what crosses the isolate boundary simple.
List<String> _generatePems(int _) {
  final pair = AuthKeyPair.generate();
  return [pair.publicPem, pair.privatePem];
}
