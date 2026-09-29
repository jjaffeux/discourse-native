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
  final String? _applicationName;
  String get applicationName => _applicationName ?? appL10n.discourseNative;
  final WebAuthLauncher _launch;
  final AuthKeyPairGenerator _generateKeyPair;
  final String Function() _generateNonce;
  final PushRegistrationProvider _pushRegistrations;

  /// How long [clientId] keeps answering without a live push registration
  /// after the platform reported none before asking it again.
  final Duration _pushRegistrationRetryInterval;

  final DateTime Function() _clock;
  final Map<String, Object> _connectionGenerations = {};
  PushRegistration? _knownPushRegistration;
  DateTime? _pushRegistrationUnavailableAt;
  Future<PushRegistration?>? _pendingPushRegistration;

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
      // Connecting is when registration must be attempted, so the platform is
      // asked directly: an absence remembered by [clientId] is not trusted.
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

  @override
  Future<String> clientId() async {
    await _pushRegistration();
    return _readClientId();
  }

  /// Answers the live push registration, else the newest one this install has
  /// recorded, else the per-install id.
  ///
  /// Discourse moves a key to a newly created client row whenever a request
  /// names a different client id, and keeps the row it left. Naming an older
  /// id again would create that row a second time, which its unique index
  /// refuses on every request. The id therefore only moves forward: the
  /// per-install id until the first registration, then each newer token, even
  /// while the platform cannot currently answer.
  Future<String> _readClientId() async {
    if (_knownPushRegistration case final known?) return known.clientId;
    final recorded = await store.readPushClientId();
    // An overlapping registration can succeed while storage is read.
    if (_knownPushRegistration case final known?) return known.clientId;
    if (recorded != null) return recorded;
    final fallback = await store.readOrCreateClientId();
    return _knownPushRegistration?.clientId ?? fallback;
  }

  /// Records [registration] before any request can name it, so a relaunch
  /// that cannot reach the platform still answers this id, never an older one.
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
    _pushRegistrationUnavailableAt = null;
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
        .then((registration) async {
          await _rememberPushRegistration(registration);
          if (_knownPushRegistration == null) {
            _pushRegistrationUnavailableAt = _clock();
          }
          return _knownPushRegistration;
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
