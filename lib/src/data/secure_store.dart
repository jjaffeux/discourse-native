import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import 'private_storage.dart';

abstract interface class ClientIdPersistence {
  Future<String?> read();

  Future<void> write(String value);
}

final class PreferencesClientIdPersistence implements ClientIdPersistence {
  static const _key = 'discourse_native.client_id';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(_key, value)) {
      throw StateError('Could not persist the client id');
    }
  }
}

/// Persistent per-install identity and per-site API keys.
///
/// API keys use [PrivateStorage]: Keychain on Apple, and a mode-0600 XDG data
/// file on Linux. The non-secret client id lives in preferences.
class SecureStore {
  SecureStore({
    PrivateStorage? storage,
    ClientIdPersistence? clientIds,
    String Function()? tokenGenerator,
  }) : _storage = storage ?? platformPrivateStorage,
       _clientIds = clientIds ?? PreferencesClientIdPersistence(),
       _tokenGenerator = tokenGenerator ?? randomToken;

  static const String _legacyClientIdEntry = 'client_id';

  final PrivateStorage _storage;
  final ClientIdPersistence _clientIds;
  final String Function() _tokenGenerator;

  String? _clientId;
  Future<String>? _clientIdRequest;
  final Map<String, String?> _apiKeys = {};
  final Map<String, Future<String?>> _apiKeyRequests = {};
  final Map<String, Future<void>> _apiKeyMutations = {};
  final Map<String, Object> _apiKeyVersions = {};

  static void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'storage',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }

  static String _apiKeyEntry(String siteUrl) => 'api_key::$siteUrl';

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
    final existing = await _clientIds.read();
    if (existing != null && existing.isNotEmpty) return existing;

    // Apple releases before the Linux file backend kept this non-secret value
    // in Keychain. Move it out after the new preference write is durable.
    final legacy = await _storage.read(_legacyClientIdEntry);
    if (legacy != null && legacy.isNotEmpty) {
      await _clientIds.write(legacy);
      try {
        await _storage.delete(_legacyClientIdEntry);
      } catch (_) {}
      return legacy;
    }

    final created = _tokenGenerator();
    await _clientIds.write(created);
    return created;
  }

  /// Reads a site's key once per process and coalesces the initial lookup.
  ///
  /// API calls ask for credentials independently, often several at launch.
  /// Persistent storage is an I/O boundary, not an in-memory map, so keeping the
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
    final request = _storage.read(_apiKeyEntry(siteUrl));
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
    await _storage.write(_apiKeyEntry(siteUrl), key);
    if (identical(_apiKeyVersions[siteUrl], version)) {
      _apiKeys[siteUrl] = key;
    }
  }

  /// Looks before deleting, because on macOS deleting nothing is not free.
  ///
  /// The plugin deletes twice, once for each synchronizable variant, and the
  /// synchronizable query needs the data protection keychain we deliberately
  /// do not use (see [AppleKeychainStorage]) — so it answers
  /// `errSecMissingEntitlement`
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
        : await _storage.read(_apiKeyEntry(siteUrl));
    if (existing != null) {
      await _storage.delete(_apiKeyEntry(siteUrl));
    }
    if (identical(_apiKeyVersions[siteUrl], version)) {
      _apiKeys[siteUrl] = null;
    }
  }

  static Future<void> _ignorePreviousFailure(Future<void>? previous) async {
    if (previous == null) return;
    try {
      await previous;
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'credentials.previousMutation');
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
