import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'user_api_key.dart';

/// Keychain-backed storage for anything that must not sit in plain
/// preferences: the RSA key pair and the per-site API keys.
///
/// Note DiscourseMobile keeps these in AsyncStorage, which is not encrypted.
/// There is no reason to copy that.
class SecureStore {
  SecureStore({
    FlutterSecureStorage? storage,
    String Function()? tokenGenerator,
  }) : _storage = storage ?? platformStorage(),
       _tokenGenerator = tokenGenerator ?? randomToken;

  /// macOS only. The data protection keychain — the plugin's default — requires
  /// the `keychain-access-groups` entitlement, which in turn requires signing
  /// with a real development certificate; without one every read fails with
  /// `errSecMissingEntitlement` (-34018).
  ///
  /// The file-based keychain is still the system keychain, just the older API,
  /// and needs no entitlement. Switch this back once the macOS target is signed
  /// with a team, and add the entitlement at the same time.
  static const AppleOptions _macOptions = MacOsOptions(
    usesDataProtectionKeychain: false,
  );

  /// Creates storage with the platform configuration shared by all sensitive
  /// data stores in the app.
  static FlutterSecureStorage platformStorage() =>
      const FlutterSecureStorage(mOptions: _macOptions);

  static const String _publicKeyEntry = 'rsa_public_key';
  static const String _privateKeyEntry = 'rsa_private_key';
  static const String _keyPairEntry = 'rsa_key_pair_v2';
  static const String _clientIdEntry = 'client_id';

  final FlutterSecureStorage _storage;
  final String Function() _tokenGenerator;
  bool _legacyKeyPairCleanupChecked = false;

  String? _clientId;
  Future<String>? _clientIdRequest;
  final Map<String, String?> _apiKeys = {};
  final Map<String, Future<String?>> _apiKeyRequests = {};
  final Map<String, Future<void>> _apiKeyMutations = {};
  final Map<String, Object> _apiKeyVersions = {};

  static String _apiKeyEntry(String siteUrl) => 'api_key::$siteUrl';

  Future<AuthKeyPair?> readKeyPair() async {
    final encoded = await _storage.read(key: _keyPairEntry);
    final current = encoded == null ? null : _decodeKeyPair(encoded);
    if (current != null) {
      await _cleanupLegacyKeyPair();
      return current;
    }

    final public = await _storage.read(key: _publicKeyEntry);
    final private = await _storage.read(key: _privateKeyEntry);
    if (public == null || private == null) return null;
    final pair = AuthKeyPair(publicPem: public, privatePem: private);
    try {
      await writeKeyPair(pair);
    } catch (_) {
      // The atomic record is either complete or the legacy pair remains.
      return pair;
    }
    await _deleteKnownLegacyKeyPair();
    return pair;
  }

  Future<void> _deleteKnownLegacyKeyPair() async {
    var complete = true;
    for (final key in const [_publicKeyEntry, _privateKeyEntry]) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        complete = false;
      }
    }
    _legacyKeyPairCleanupChecked = complete;
  }

  Future<void> _cleanupLegacyKeyPair() async {
    if (_legacyKeyPairCleanupChecked) return;

    var complete = true;
    for (final key in const [_publicKeyEntry, _privateKeyEntry]) {
      try {
        if (await _storage.read(key: key) != null) {
          await _storage.delete(key: key);
        }
      } catch (_) {
        complete = false;
      }
    }
    _legacyKeyPairCleanupChecked = complete;
  }

  Future<void> writeKeyPair(AuthKeyPair pair) => _storage.write(
    key: _keyPairEntry,
    value: jsonEncode({'public': pair.publicPem, 'private': pair.privatePem}),
  );

  static AuthKeyPair? _decodeKeyPair(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded case {
        'public': final String public,
        'private': final String private,
      }) {
        if (public.isNotEmpty && private.isNotEmpty) {
          return AuthKeyPair(publicPem: public, privatePem: private);
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Stable per-install id, sent as `client_id` so a site can tell our
  /// installs apart and revoke one.
  Future<String> readOrCreateClientId() async {
    final held = _clientId;
    if (held != null) return held;

    final pending = _clientIdRequest;
    if (pending != null) return pending;

    final request = _readOrCreateClientId();
    _clientIdRequest = request;
    try {
      return _clientId = await request;
    } finally {
      if (identical(_clientIdRequest, request)) _clientIdRequest = null;
    }
  }

  Future<String> _readOrCreateClientId() async {
    final existing = await _storage.read(key: _clientIdEntry);
    if (existing != null && existing.isNotEmpty) return existing;

    final created = _tokenGenerator();
    await _storage.write(key: _clientIdEntry, value: created);
    return created;
  }

  /// Reads a site's key once per process and coalesces the initial lookup.
  ///
  /// API calls ask for credentials independently, often several at launch.
  /// The keychain is an I/O boundary, not an in-memory map, so keeping the
  /// stable result here avoids paying for the same platform round trip before
  /// every request. Writes and deletes invalidate pending reads synchronously.
  Future<String?> readApiKey(String siteUrl) async {
    if (_apiKeys.containsKey(siteUrl)) return _apiKeys[siteUrl];

    final mutation = _apiKeyMutations[siteUrl];
    if (mutation != null) {
      await mutation;
      return readApiKey(siteUrl);
    }

    final pending = _apiKeyRequests[siteUrl];
    if (pending != null) {
      final version = _apiKeyVersions.putIfAbsent(siteUrl, Object.new);
      final String? key;
      try {
        key = await pending;
      } catch (error, stackTrace) {
        if (!identical(_apiKeyVersions[siteUrl], version)) {
          return _readApiKeyAfterCurrentMutation(siteUrl);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (!identical(_apiKeyVersions[siteUrl], version)) {
        return _readApiKeyAfterCurrentMutation(siteUrl);
      }
      return key;
    }

    final version = _apiKeyVersions.putIfAbsent(siteUrl, Object.new);
    final request = _storage.read(key: _apiKeyEntry(siteUrl));
    _apiKeyRequests[siteUrl] = request;
    try {
      final String? key;
      try {
        key = await request;
      } catch (error, stackTrace) {
        if (!identical(_apiKeyVersions[siteUrl], version) ||
            !identical(_apiKeyRequests[siteUrl], request)) {
          return _readApiKeyAfterCurrentMutation(siteUrl);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (!identical(_apiKeyVersions[siteUrl], version) ||
          !identical(_apiKeyRequests[siteUrl], request)) {
        return _readApiKeyAfterCurrentMutation(siteUrl);
      }
      _apiKeys[siteUrl] = key;
      return key;
    } finally {
      if (identical(_apiKeyRequests[siteUrl], request)) {
        final _ = _apiKeyRequests.remove(siteUrl);
      }
    }
  }

  Future<String?> _readApiKeyAfterCurrentMutation(String siteUrl) async {
    final mutation = _apiKeyMutations[siteUrl];
    if (mutation != null) await mutation;
    return readApiKey(siteUrl);
  }

  Future<void> writeApiKey(String siteUrl, String key) async {
    final version = Object();
    _apiKeyVersions[siteUrl] = version;
    _apiKeys.remove(siteUrl);
    final _ = _apiKeyRequests.remove(siteUrl);
    final previous = _apiKeyMutations[siteUrl];
    final mutation = _writeApiKeyAfter(previous, siteUrl, key, version);
    _apiKeyMutations[siteUrl] = mutation;
    try {
      await mutation;
    } finally {
      if (identical(_apiKeyMutations[siteUrl], mutation)) {
        final _ = _apiKeyMutations.remove(siteUrl);
      }
    }
  }

  Future<void> _writeApiKeyAfter(
    Future<void>? previous,
    String siteUrl,
    String key,
    Object version,
  ) async {
    await _ignorePreviousFailure(previous);
    await _storage.write(key: _apiKeyEntry(siteUrl), value: key);
    if (identical(_apiKeyVersions[siteUrl], version)) {
      _apiKeys[siteUrl] = key;
    }
  }

  /// Looks before deleting, because on macOS deleting nothing is not free.
  ///
  /// The plugin deletes twice, once for each synchronizable variant, and the
  /// synchronizable query needs the data protection keychain we deliberately
  /// do not use (see [_macOptions]) — so it answers `errSecMissingEntitlement`
  /// (-34018). That is harmless while the other delete succeeds, since either
  /// one succeeding is reported as success. When there is no entry to delete
  /// the other one only finds nothing, and -34018 becomes the answer.
  ///
  /// Which makes removing a site that was never connected — the one case where
  /// there is certainly no key — the case that fails. A read is exact where a
  /// delete is not, so ask first.
  Future<void> deleteApiKey(String siteUrl) async {
    final version = Object();
    _apiKeyVersions[siteUrl] = version;
    final hadCachedValue = _apiKeys.containsKey(siteUrl);
    final cachedValue = _apiKeys[siteUrl];
    _apiKeys.remove(siteUrl);
    final _ = _apiKeyRequests.remove(siteUrl);
    final previous = _apiKeyMutations[siteUrl];
    final mutation = _deleteApiKeyAfter(
      previous,
      siteUrl,
      version,
      hadCachedValue: hadCachedValue,
      cachedValue: cachedValue,
    );
    _apiKeyMutations[siteUrl] = mutation;
    try {
      await mutation;
    } finally {
      if (identical(_apiKeyMutations[siteUrl], mutation)) {
        final _ = _apiKeyMutations.remove(siteUrl);
      }
    }
  }

  Future<void> _deleteApiKeyAfter(
    Future<void>? previous,
    String siteUrl,
    Object version, {
    required bool hadCachedValue,
    required String? cachedValue,
  }) async {
    await _ignorePreviousFailure(previous);
    final existing = previous == null && hadCachedValue
        ? cachedValue
        : await _storage.read(key: _apiKeyEntry(siteUrl));
    if (existing != null) {
      await _storage.delete(key: _apiKeyEntry(siteUrl));
    }
    if (identical(_apiKeyVersions[siteUrl], version)) {
      _apiKeys[siteUrl] = null;
    }
  }

  static Future<void> _ignorePreviousFailure(Future<void>? previous) async {
    if (previous == null) return;
    try {
      await previous;
    } catch (_) {
      // A newer credential operation must still get a chance to repair state.
    }
  }

  /// URL-safe random token, used for both the client id and the nonce.
  static String randomToken([int bytes = 16]) {
    final random = Random.secure();
    final values = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }
}
