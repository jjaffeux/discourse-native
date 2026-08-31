import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'api_credentials.dart';
import 'push_registration.dart';
import 'secure_store.dart';
import 'user_api_key.dart';

typedef WebAuthLauncher =
    Future<String> Function(String url, String callbackScheme);

typedef AuthKeyPairGenerator = Future<AuthKeyPair> Function();

Future<String> _launchWebAuth(String url, String callbackScheme) =>
    FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: callbackScheme);

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
        // Every platform reports `CANCELED` only for browser dismissal. Other
        // codes mean the browser failed to launch and must not be treated as a
        // silent user cancellation.
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

List<String> _generatePems(int _) {
  final pair = AuthKeyPair.generate();
  return [pair.publicPem, pair.privatePem];
}
