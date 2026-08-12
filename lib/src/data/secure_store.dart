import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import 'private_storage.dart';
import 'serial_operation_queue.dart';

abstract interface class ClientIdPersistence {
  Future<String?> read();

  Future<void> write(String value);
}

final class PreferencesClientIdPersistence implements ClientIdPersistence {
  const PreferencesClientIdPersistence();

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
/// API keys use [PrivateStorage]: the Data Protection Keychain on Apple, and a
/// mode-0600 XDG data file on Linux. The non-secret client id lives in
/// preferences.
class SecureStore {
  SecureStore({
    PrivateStorage? storage,
    PrivateStorage? legacyClientIds,
    ClientIdPersistence? clientIds,
    String Function()? tokenGenerator,
  }) : _storage = storage ?? platformCredentialStorage,
       _legacyClientIds =
           legacyClientIds ?? storage ?? platformLegacyClientIdStorage,
       _clientIds = clientIds ?? _defaultClientIds,
       _tokenGenerator = tokenGenerator ?? randomToken;

  static const String _legacyClientIdEntry = 'client_id';
  static const ClientIdPersistence _defaultClientIds =
      PreferencesClientIdPersistence();
  static final SerialOperationQueue _clientIdOperations =
      SerialOperationQueue();

  final PrivateStorage _storage;
  final PrivateStorage? _legacyClientIds;
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

    // App dependency replacement can create a second store while the first is
    // still reading preferences. Serialize the whole read-create-write cycle
    // so both stores cannot mint and return different per-install identities.
    // Injected persistence objects remain independent unless they deliberately
    // share the same identity.
    final request = _clientIdOperations.run<String>(
      owner: _clientIds,
      key: _legacyClientIdEntry,
      operation: _readOrCreateClientId,
    );
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
    // in Keychain. Copy it out, but leave the now-inert old item alone: deleting
    // an ACL-protected item after reading it can cause a second macOS prompt.
    final legacyStorage = _legacyClientIds;
    if (legacyStorage == null) {
      final created = _tokenGenerator();
      await _clientIds.write(created);
      return created;
    }

    final legacy = await legacyStorage.read(_legacyClientIdEntry);
    if (legacy != null && legacy.isNotEmpty) {
      await _clientIds.write(legacy);
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

  /// Invalidates the credential locally, including a durable migration
  /// tombstone on distributed Apple builds.
  Future<void> deleteApiKey(String siteUrl) async {
    final version = Object();
    _apiKeyVersions[siteUrl] = version;
    _apiKeys.remove(siteUrl);
    final _ = _apiKeyRequests.remove(siteUrl);
    final previous = _apiKeyMutations[siteUrl];
    final mutation = _deleteApiKeyAfter(previous, siteUrl, version);
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
    Object version,
  ) async {
    await _ignorePreviousFailure(previous);
    await _storage.delete(_apiKeyEntry(siteUrl));
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
