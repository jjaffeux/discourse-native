import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'api_credentials.dart';
import 'push_registration.dart';
import 'secure_store.dart';
import 'store_diagnostics.dart';
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
    this._applicationName,
  }) : store = store ?? SecureStore(),
       _launch = launcher ?? _launchWebAuth,
       _generateKeyPair = keyPairGenerator ?? _generateAuthKeyPair,
       _generateNonce = nonceGenerator ?? SecureStore.randomToken,
       _pushRegistrations =
           pushRegistrations ?? PlatformPushRegistrationProvider();

  final SecureStore store;
  final UserApiKeyProtocol protocol;
  final String? _applicationName;
  String get applicationName => _applicationName ?? appL10n.discourseNative;
  final WebAuthLauncher _launch;
  final AuthKeyPairGenerator _generateKeyPair;
  final String Function() _generateNonce;
  final PushRegistrationProvider _pushRegistrations;

  final Map<String, Object> _connectionGenerations = {};
  PushRegistration? _knownPushRegistration;

  static UserApiAuthException get _supersededConnection => UserApiAuthException(
    UserApiAuthFailure.cancelled,
    appL10n.connectionSuperseded,
  );

  Future<UserApiCredentials> connect(String siteUrl) =>
      _runConnection(siteUrl, persist: true);

  /// Completes the user API key handshake without changing local credentials.
  ///
  /// Account transitions use this boundary to make their signed-out snapshot
  /// durable before the newly-authorized key can replace an existing account.
  Future<UserApiCredentials> authorize(String siteUrl) =>
      _runConnection(siteUrl, persist: false);

  Future<UserApiCredentials> _runConnection(
    String siteUrl, {
    required bool persist,
  }) async {
    final generation = Object();
    _connectionGenerations[siteUrl] = generation;
    try {
      // Push identity is registered only through the authorization handshake.
      await _rememberPushRegistration(await _pushRegistrations.registration());
      final clientId = await _readClientId();
      // Only a registration the platform has answered vouches for a push URL.
      // A recorded token can outlive the permission that produced it.
      final pushRegistration = _knownPushRegistration;
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

      if (persist) {
        await persistCredentials(siteUrl, credentials);
        _ensureCurrent(siteUrl, generation);
      }
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

  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) => store.writeApiKey(siteUrl, credentials.key);

  bool _isCurrent(String siteUrl, Object generation) =>
      identical(_connectionGenerations[siteUrl], generation);

  void _ensureCurrent(String siteUrl, Object generation) {
    if (!_isCurrent(siteUrl, generation)) throw _supersededConnection;
  }

  @override
  Future<String?> apiKeyFor(String siteUrl) => store.readApiKey(siteUrl);

  /// Ordinary requests must preserve the client associated with their API key.
  /// Discourse interprets a different User-Api-Client-Id as a client migration,
  /// creating a row even if that ID already exists. A live APNs token is not
  /// necessarily the token used to authorize this key (notably across iOS
  /// build environments), and concurrent migrations can also collide.
  /// An empty ID tells transports to omit the optional header. Sign-in still
  /// registers the push token; token changes require a new authorization.
  @override
  Future<String> clientId() async => '';

  /// The client identity for a new authorization, never for ordinary requests.
  Future<String> _readClientId() async {
    if (_knownPushRegistration case final known?) return known.clientId;
    final recorded = await store.readPushClientId();
    // An overlapping registration can succeed while storage is read.
    if (_knownPushRegistration case final known?) return known.clientId;
    if (recorded != null) return recorded;
    final fallback = await store.readOrCreateClientId();
    return _knownPushRegistration?.clientId ?? fallback;
  }

  /// Records [registration] for subsequent authorization attempts.
  ///
  /// The store completes these writes in call order, so memory and storage
  /// settle on the same, latest registration.
  Future<void> _rememberPushRegistration(PushRegistration? registration) async {
    // A late absence must not replace a successful overlapping registration.
    if (registration == null) return;
    try {
      await store.writePushClientId(registration.clientId);
    } catch (error, stackTrace) {
      // The registration still works for this launch; only a relaunch that
      // cannot reach the platform loses it.
      reportStorageFailure(error, stackTrace, 'credentials.pushClientId');
    }
    _knownPushRegistration = registration;
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
