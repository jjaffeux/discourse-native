import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../foundation/private_file_permissions.dart';

/// Exact-key persistence for data which must not be mixed into the app's public
/// preferences.
abstract interface class PrivateStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// A private store whose contents can be enumerated without crossing a system
/// authorization boundary.
///
/// Only file stores implement this. Keychain enumeration is deliberately not
/// exposed: the legacy macOS keychain authorizes every item separately, so a
/// broad read can create one password prompt per credential or draft.
abstract interface class EnumerablePrivateStorage implements PrivateStorage {
  Future<Map<String, String>> readAll();
}

const String appleCredentialService = 'org.discourse.native.credentials';
const String appleDevelopmentCredentialService =
    'org.discourse.native.dev.credentials';
const String legacyAppleStorageService = 'flutter_secure_storage_service';

Future<File> _appleCredentialMigrationLockFile() async {
  final support = await getApplicationSupportDirectory();
  return File('${support.path}/keychain-migration-v1.lock');
}

final _PlatformPrivateStorage _platformStorage =
    _PlatformPrivateStorage.create();

/// Credential storage: Data Protection Keychain in distributed Apple builds,
/// an isolated login-keychain service in custom-signed macOS development
/// builds, and the existing mode-0600 XDG file on Linux.
final PrivateStorage platformCredentialStorage = _platformStorage.credentials;

/// Local document storage used by Linux drafts. Apple drafts have their own
/// Application Support persistence in `draft_store.dart`.
final EnumerablePrivateStorage platformEnumerablePrivateStorage =
    _platformStorage.enumerable;

/// The old Apple service, available only to release builds for exact-item lazy
/// migration. Development and profile builds must never query production's
/// legacy login-keychain ACLs.
final PrivateStorage? platformLegacyAppleStorage = _platformStorage.legacyApple;

/// Source used only to move the old non-secret client id into preferences.
/// It intentionally bypasses the credential migrator so `client_id` is never
/// copied into the new Keychain namespace.
final PrivateStorage? platformLegacyClientIdStorage =
    _platformStorage.legacyClientIds;

/// Backwards-compatible name for callers which only need exact-key credential
/// operations.
final PrivateStorage platformPrivateStorage = platformCredentialStorage;

final class _PlatformPrivateStorage {
  const _PlatformPrivateStorage({
    required this.credentials,
    required this.enumerable,
    required this.legacyApple,
    required this.legacyClientIds,
  });

  final PrivateStorage credentials;
  final EnumerablePrivateStorage enumerable;
  final PrivateStorage? legacyApple;
  final PrivateStorage? legacyClientIds;

  factory _PlatformPrivateStorage.create() {
    if (Platform.isLinux) {
      final storage = LinuxFileStorage();
      return _PlatformPrivateStorage(
        credentials: storage,
        enumerable: storage,
        legacyApple: null,
        legacyClientIds: storage,
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      // The local macOS certificate has no provisioning profile/application
      // identifier, so it cannot use the Data Protection Keychain. Keep those
      // builds on a namespaced legacy service which cannot collide with or
      // request access to TestFlight credentials. iOS remains provisioned and
      // the option is ignored there by the plugin.
      final isCustomSignedMacDevelopment = Platform.isMacOS && !kReleaseMode;
      final current = AppleKeychainStorage(
        service: isCustomSignedMacDevelopment
            ? appleDevelopmentCredentialService
            : appleCredentialService,
        usesDataProtectionKeychain: !isCustomSignedMacDevelopment,
      );
      final legacy = kReleaseMode
          ? AppleKeychainStorage(
              service: legacyAppleStorageService,
              usesDataProtectionKeychain: false,
            )
          : null;
      return _PlatformPrivateStorage(
        credentials: legacy == null
            ? current
            : MigratingPrivateStorage(
                primary: current,
                legacy: legacy,
                lockFile: _appleCredentialMigrationLockFile,
              ),
        // This is never used for Apple drafts. Supplying a file-only interface
        // here keeps the platform aggregate total without exposing Keychain
        // enumeration; any accidental use fails immediately.
        enumerable: const _UnavailableEnumerablePrivateStorage(),
        legacyApple: legacy,
        legacyClientIds: legacy,
      );
    }
    throw UnsupportedError('Private storage is unavailable on this platform');
  }
}

final class _UnavailableEnumerablePrivateStorage
    implements EnumerablePrivateStorage {
  const _UnavailableEnumerablePrivateStorage();

  Never _unsupported() => throw UnsupportedError(
    'Enumerable private storage is unavailable on Apple platforms',
  );

  @override
  Future<void> delete(String key) => _unsupported();

  @override
  Future<String?> read(String key) => _unsupported();

  @override
  Future<Map<String, String>> readAll() => _unsupported();

  @override
  Future<void> write(String key, String value) => _unsupported();
}

/// Calls the Darwin implementation directly, without depending on the
/// umbrella plugin that automatically links libsecret into Linux builds.
final class AppleKeychainStorage implements PrivateStorage {
  AppleKeychainStorage({
    MethodChannel? channel,
    this.service = appleCredentialService,
    this.usesDataProtectionKeychain = true,
  }) : _channel =
           channel ??
           const MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final MethodChannel _channel;
  final String service;
  final bool usesDataProtectionKeychain;

  Map<String, String> get _options => {
    'accountName': service,
    'accessibility': 'unlocked',
    'synchronizable': 'false',
    'useSecureEnclave': 'false',
    // Parsed but ignored on iOS. Sending it on both Apple platforms makes the
    // storage identity explicit and keeps injected-channel tests deterministic.
    'usesDataProtectionKeychain': '$usesDataProtectionKeychain',
  };

  @override
  Future<String?> read(String key) =>
      _channel.invokeMethod<String?>('read', {'key': key, 'options': _options});

  @override
  Future<void> write(String key, String value) async {
    if (!usesDataProtectionKeychain) {
      // The plugin's legacy `containsKey` probes the synchronizable (DPK)
      // variant first and mistakes -34018 for absence, so updating an existing
      // file-keychain item otherwise becomes a duplicate-item failure.
      await delete(key);
    }
    await _channel.invokeMethod<void>('write', {
      'key': key,
      'value': value,
      'options': _options,
    });
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _channel.invokeMethod<void>('delete', {
        'key': key,
        'options': _options,
      });
    } on PlatformException catch (error) {
      // In legacy mode the plugin also issues a synchronizable delete. A
      // missing item can therefore report the Data Protection entitlement
      // error even though there is nothing to remove. Confirm the exact miss
      // before treating that legacy-plugin quirk as an idempotent delete.
      if (!usesDataProtectionKeychain &&
          error.code == 'Unexpected security result code' &&
          error.details == -34018 &&
          await read(key) == null) {
        return;
      }
      rethrow;
    }
  }
}

/// Lazily moves one exact item at a time from the legacy Apple login keychain
/// into the app's Data Protection Keychain service.
///
/// Operations are serialized in-process and, in the platform instance, under
/// an owner-only advisory file lock shared by app processes. Without that
/// boundary a slow legacy read could finish after a newer write/delete and
/// resurrect stale credentials as a migration side effect.
final class MigratingPrivateStorage implements PrivateStorage {
  MigratingPrivateStorage({
    required this.primary,
    required this.legacy,
    this.lockFile,
  });

  final PrivateStorage primary;
  final PrivateStorage legacy;
  final Future<File> Function()? lockFile;
  Future<void> _tail = Future<void>.value();

  static const String _migrationStatePrefix =
      'discourse_native.migration_state::';
  static const String _active = 'active';
  static const String _deleted = 'deleted';

  static String _stateKey(String key) => '$_migrationStatePrefix$key';

  @override
  Future<String?> read(String key) => _serialize(() async {
    final state = await primary.read(_stateKey(key));
    if (state == _deleted) return null;

    final current = await primary.read(key);
    if (current != null) {
      // Repair a crash between the value write and its authoritative-state
      // write before returning the credential.
      if (state != _active) await primary.write(_stateKey(key), _active);
      return current;
    }
    // A current write or prior migration makes the modern namespace
    // authoritative even if its value is unexpectedly absent. Never resurrect
    // an older bearer token after that boundary.
    if (state == _active) return null;

    final previous = await legacy.read(key);
    if (previous == null) return null;

    await primary.write(key, previous);
    await primary.write(_stateKey(key), _active);
    // Do not delete the ACL-protected item here. A user who chose plain
    // "Allow" for the read could otherwise receive a second password prompt.
    // The active state makes the old copy permanently non-authoritative.
    return previous;
  });

  @override
  Future<void> write(String key, String value) => _serialize(() async {
    // Make the replacement durable before lifting a deletion tombstone. If
    // the state write fails, an older tombstone continues hiding the key.
    await primary.write(key, value);
    await primary.write(_stateKey(key), _active);
  });

  @override
  Future<void> delete(String key) => _serialize(() async {
    // This is the logical deletion. It is durable before either physical copy
    // is touched, so an ACL refusal or cleanup failure cannot leave an active
    // credential or resurrect the old service's value.
    await primary.write(_stateKey(key), _deleted);
    await _bestEffortPrimaryDelete(key);
    // Do not query legacy here. Disconnecting an item whose old ACL belongs to
    // another signature must not display a password dialog; the tombstone
    // permanently makes that inaccessible copy non-authoritative.
  });

  Future<void> _bestEffortPrimaryDelete(String key) async {
    try {
      await primary.delete(key);
    } catch (_) {
      // The tombstone is the authoritative deletion. Leaving an unreachable
      // value behind is cleanup debt, not an active credential.
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        final lockFile = this.lockFile;
        result.complete(
          lockFile == null
              ? await operation()
              : await _withFileLock(await lockFile(), operation),
        );
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  static Future<T> _withFileLock<T>(
    File file,
    Future<T> Function() operation,
  ) => withPrivateAdvisoryFileLock(file, operation);
}

/// A serialized JSON store at
/// `$XDG_DATA_HOME/discourse-native/private-storage.json`.
///
/// The containing directory is mode 0700 and the file is mode 0600. Updates
/// are flushed to a same-directory temporary file before an atomic rename, so
/// interruption cannot leave half-written JSON behind.
final class LinuxFileStorage implements EnumerablePrivateStorage {
  LinuxFileStorage({Directory? directory}) : _providedDirectory = directory;

  static const _fileName = 'private-storage.json';
  static const _formatVersion = 1;
  static final Map<String, _LinuxFileStorageCoordinator> _coordinators = {};

  final Directory? _providedDirectory;
  final Random _random = Random.secure();

  @override
  Future<String?> read(String key) =>
      _serialize(() async => (await _readValues())[key]);

  @override
  Future<Map<String, String>> readAll() =>
      _serialize(() async => Map.unmodifiable(await _readValues()));

  @override
  Future<void> write(String key, String value) => _serialize(() async {
    final values = await _readValues();
    values[key] = value;
    await _writeValues(values);
  });

  @override
  Future<void> delete(String key) => _serialize(() async {
    final values = await _readValues();
    if (values.remove(key) != null) await _writeValues(values);
  });

  Future<T> _serialize<T>(Future<T> Function() operation) async {
    final file = await _file();
    final path = file.absolute.path;
    final coordinator = _coordinators.putIfAbsent(
      path,
      () => _LinuxFileStorageCoordinator(File(path)),
    );
    return coordinator.run(operation);
  }

  Future<Directory> _directory() async {
    final provided = _providedDirectory;
    if (provided != null) return provided;

    final environment = Platform.environment;
    final xdg = environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty && xdg.startsWith('/')) {
      return Directory('$xdg/discourse-native');
    }

    final home = environment['HOME'];
    if (home == null || home.isEmpty || !home.startsWith('/')) {
      throw StateError('HOME does not name an absolute directory');
    }
    return Directory('$home/.local/share/discourse-native');
  }

  Future<File> _file() async {
    final directory = await _directory();
    await ensurePrivateDirectory(directory);
    return File('${directory.path}/$_fileName');
  }

  Future<Map<String, String>> _readValues() async {
    final file = await _file();
    if (!await file.exists()) return {};
    restrictPrivateFile(file);

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw FormatException('Invalid private storage: ${error.message}');
    }

    if (decoded case {
      'version': final int version,
      'values': final Map<Object?, Object?> rawValues,
    } when version == _formatVersion) {
      final values = <String, String>{};
      for (final MapEntry(:key, :value) in rawValues.entries) {
        if (key is! String || value is! String) {
          throw const FormatException(
            'Invalid private storage: values must be strings',
          );
        }
        values[key] = value;
      }
      return values;
    }
    throw const FormatException('Invalid private storage format');
  }

  Future<void> _writeValues(Map<String, String> values) async {
    final file = await _file();
    final suffix = List<int>.generate(
      12,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final temporary = File('${file.path}.$pid.$suffix.tmp');

    try {
      await ensurePrivateFile(temporary);
      await temporary.writeAsString(
        jsonEncode({'version': _formatVersion, 'values': values}),
        flush: true,
      );
      await temporary.rename(file.path);
      restrictPrivateFile(file);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

/// Serializes full-file transactions across storage instances and processes.
final class _LinuxFileStorageCoordinator {
  _LinuxFileStorageCoordinator(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(
          await withPrivateAdvisoryFileLock(
            File('${file.path}.lock'),
            operation,
          ),
        );
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
