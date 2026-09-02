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
    Duration pushRegistrationRetryInterval = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : assert(pushRegistrationRetryInterval >= Duration.zero),
       store = store ?? SecureStore(),
       _launch = launcher ?? _launchWebAuth,
       _generateKeyPair = keyPairGenerator ?? _generateAuthKeyPair,
       _generateNonce = nonceGenerator ?? SecureStore.randomToken,
       _pushRegistrations =
           pushRegistrations ?? PlatformPushRegistrationProvider(),
       _pushRegistrationRetryInterval = pushRegistrationRetryInterval,
       _clock = clock ?? DateTime.now;

  final SecureStore store;
  final UserApiKeyProtocol protocol;
  final String applicationName;
  final WebAuthLauncher _launch;
  final AuthKeyPairGenerator _generateKeyPair;
  final String Function() _generateNonce;
  final PushRegistrationProvider _pushRegistrations;

  /// How long [clientId] keeps answering with the per-install client id after
  /// the platform reported no push registration before asking it again.
  final Duration _pushRegistrationRetryInterval;

  final DateTime Function() _clock;
  final Map<String, Object> _connectionGenerations = {};
  PushRegistration? _knownPushRegistration;
  DateTime? _pushRegistrationUnavailableAt;
  Future<PushRegistration?>? _pendingPushRegistration;

  static const _supersededConnection = UserApiAuthException(
    UserApiAuthFailure.cancelled,
    'connection superseded',
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
      // Connecting is when registration must be attempted, so the platform is
      // asked directly: an absence remembered by [clientId] is not trusted.
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

  @override
  Future<String> clientId() async {
    final pushRegistration = await _pushRegistration();
    if (pushRegistration != null) return pushRegistration.clientId;
    return store.readOrCreateClientId();
  }

  /// Reads the push registration for [clientId], asking the platform at most
  /// once at a time and, once it has answered that none is available, at most
  /// once per retry interval.
  ///
  /// A registration is kept for this authenticator's lifetime: the platform
  /// keeps the token it handed out, so the answer cannot change. An absence is
  /// believed only for the interval because the platform re-runs registration
  /// on the next read, and that read can wait its whole registration timeout
  /// while APNs is unreachable. Every authenticated request reads the client
  /// id, so that wait is paid once per interval rather than once per request.
  Future<PushRegistration?> _pushRegistration() {
    final known = _knownPushRegistration;
    if (known != null) return Future.value(known);
    final pending = _pendingPushRegistration;
    if (pending != null) return pending;
    final unavailableAt = _pushRegistrationUnavailableAt;
    if (unavailableAt != null &&
        _clock().difference(unavailableAt) <= _pushRegistrationRetryInterval) {
      return Future.value(null);
    }

    late final Future<PushRegistration?> read;
    read = _pushRegistrations
        .registration()
        .then((registration) {
          if (registration != null) {
            _knownPushRegistration = registration;
          } else {
            _pushRegistrationUnavailableAt = _clock();
          }
          return registration;
        })
        .whenComplete(() {
          if (identical(_pendingPushRegistration, read)) {
            _pendingPushRegistration = null;
          }
        });
    _pendingPushRegistration = read;
    return read;
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
