import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../foundation/private_file_permissions.dart';
import 'private_storage.dart';
import 'store_diagnostics.dart';

typedef DraftPersistenceRead = ({String? value, bool allowPreferenceFallback});

const int _draftFileFormatVersion = 1;

abstract interface class DraftPersistence {
  Future<DraftPersistenceRead> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<void> deletePrefix(String prefix);
}

/// The device could not retain the newest draft revision.
final class DraftWriteException implements Exception {
  const DraftWriteException([this.cause]);

  final Object? cause;

  @override
  String toString() => cause == null
      ? 'DraftWriteException'
      : 'DraftWriteException(${cause.runtimeType})';
}

final class PrivateDraftPersistence implements DraftPersistence {
  PrivateDraftPersistence({EnumerablePrivateStorage? storage})
    : _storage = storage ?? platformEnumerablePrivateStorage;

  final EnumerablePrivateStorage _storage;

  @override
  Future<DraftPersistenceRead> read(String key) async =>
      (value: await _storage.read(key), allowPreferenceFallback: true);

  @override
  Future<void> write(String key, String value) => _storage.write(key, value);

  @override
  Future<void> delete(String key) => _storage.delete(key);

  @override
  Future<void> deletePrefix(String prefix) async {
    final stored = await _storage.readAll();
    await Future.wait([
      for (final key in stored.keys)
        if (key.startsWith(prefix)) _storage.delete(key),
    ]);
  }
}

DraftPersistence _platformDraftPersistence() {
  if (Platform.isLinux) return PrivateDraftPersistence();
  if (Platform.isIOS || Platform.isMacOS) {
    return AppleFileDraftPersistence();
  }
  throw UnsupportedError('Draft persistence is unavailable on this platform');
}

/// Versioned, owner-only draft storage in the Apple application-support
/// container.
///
/// Old Keychain drafts are recovered lazily by exact key in release builds.
/// Durable blockers ensure a cleared or newly written draft can never be
/// resurrected from an inaccessible legacy item. No operation enumerates the
/// old Keychain service.
final class AppleFileDraftPersistence implements DraftPersistence {
  AppleFileDraftPersistence({File? file, PrivateStorage? legacyStorage})
    : _providedFile = file,
      _legacyStorage = legacyStorage ?? platformLegacyAppleStorage;

  static const String directoryName = 'drafts';
  static const String fileName = 'drafts-v1.json';
  static final Map<String, _DraftFileCoordinator> _coordinators = {};

  final File? _providedFile;
  final PrivateStorage? _legacyStorage;
  final Random _random = Random.secure();

  @override
  Future<DraftPersistenceRead> read(String key) async {
    final first = await _serialize(
      (file) async => _probe(await _readState(file), key),
    );
    if (first.value != null || first.blocked) return _result(first);

    final legacy = _legacyStorage;
    if (legacy == null) {
      return (value: null, allowPreferenceFallback: true);
    }

    // Do not hold the file queue while macOS may be presenting an ACL dialog.
    final legacyValue = await legacy.read(key);
    return _serialize((file) async {
      final state = await _readState(file);
      final latest = _probe(state, key);
      if (latest.value != null || latest.blocked) {
        return _result(latest);
      }
      if (legacyValue == null) {
        return (value: null, allowPreferenceFallback: true);
      }

      state.values[key] = legacyValue;
      state.blockedLegacyKeys.add(key);
      await _writeState(file, state);
      return (value: legacyValue, allowPreferenceFallback: false);
    });
  }

  @override
  Future<void> write(String key, String value) => _serialize((file) async {
    final state = await _readState(file);
    state.values[key] = value;
    state.blockedLegacyKeys.add(key);
    await _writeState(file, state);
  });

  @override
  Future<void> delete(String key) => _serialize((file) async {
    final state = await _readState(file);
    state.values.remove(key);
    state.blockedLegacyKeys.add(key);
    await _writeState(file, state);
  });

  @override
  Future<void> deletePrefix(String prefix) => _serialize((file) async {
    final state = await _readState(file);
    state.values.removeWhere((key, _) => key.startsWith(prefix));
    state.blockedLegacyKeys.removeWhere((key) => key.startsWith(prefix));
    state.blockedLegacyPrefixes.add(prefix);
    await _writeState(file, state);
  });

  _DraftProbe _probe(_DraftFileState state, String key) => (
    value: state.values[key],
    blocked:
        state.blockedLegacyKeys.contains(key) ||
        state.blockedLegacyPrefixes.any(key.startsWith),
  );

  static DraftPersistenceRead _result(_DraftProbe probe) =>
      (value: probe.value, allowPreferenceFallback: !probe.blocked);

  Future<File> _file() async {
    final provided = _providedFile;
    if (provided != null) return provided;
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/$directoryName/$fileName');
  }

  Future<_DraftFileState> _readState(File file) async {
    if (!await file.exists()) return _DraftFileState();
    await ensurePrivateDirectory(file.parent);
    restrictPrivateFile(file);

    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (error) {
      throw FormatException('Invalid draft storage: ${error.message}');
    }
    return _DraftFileState.decode(decoded);
  }

  Future<void> _writeState(File file, _DraftFileState state) async {
    final suffix = List<int>.generate(
      12,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final temporary = File('${file.path}.$pid.$suffix.tmp');

    try {
      await ensurePrivateFile(temporary);
      await temporary.writeAsString(jsonEncode(state.toJson()), flush: true);
      await temporary.rename(file.path);
      restrictPrivateFile(file);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<T> _serialize<T>(Future<T> Function(File file) operation) async {
    final file = await _file();
    final path = file.absolute.path;
    final coordinator = _coordinators.putIfAbsent(
      path,
      () => _DraftFileCoordinator(File(path)),
    );
    return coordinator.run(operation);
  }
}

typedef _DraftProbe = ({String? value, bool blocked});

/// Serializes complete-file replacements across persistence instances and
/// holds an advisory sidecar lock so a second process cannot overwrite a
/// snapshot read by the first.
final class _DraftFileCoordinator {
  _DraftFileCoordinator(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function(File file) operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await _withLock(operation));
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<T> _withLock<T>(Future<T> Function(File file) operation) async {
    final lockFile = File('${file.path}.lock');
    return withPrivateAdvisoryFileLock(lockFile, () => operation(file));
  }
}

final class _DraftFileState {
  _DraftFileState({
    Map<String, String>? values,
    Set<String>? blockedLegacyKeys,
    Set<String>? blockedLegacyPrefixes,
  }) : values = values ?? {},
       blockedLegacyKeys = blockedLegacyKeys ?? {},
       blockedLegacyPrefixes = blockedLegacyPrefixes ?? {};

  final Map<String, String> values;
  final Set<String> blockedLegacyKeys;
  final Set<String> blockedLegacyPrefixes;

  factory _DraftFileState.decode(Object? decoded) {
    if (decoded case {
      'version': _draftFileFormatVersion,
      'values': final Map<Object?, Object?> rawValues,
      'blockedLegacyKeys': final List<Object?> rawKeys,
      'blockedLegacyPrefixes': final List<Object?> rawPrefixes,
    }) {
      final values = <String, String>{};
      for (final MapEntry(:key, :value) in rawValues.entries) {
        if (key is! String || value is! String) {
          throw const FormatException(
            'Invalid draft storage: values must be strings',
          );
        }
        values[key] = value;
      }
      if (rawKeys.any((value) => value is! String) ||
          rawPrefixes.any((value) => value is! String)) {
        throw const FormatException(
          'Invalid draft storage: blockers must be strings',
        );
      }
      return _DraftFileState(
        values: values,
        blockedLegacyKeys: rawKeys.cast<String>().toSet(),
        blockedLegacyPrefixes: rawPrefixes.cast<String>().toSet(),
      );
    }
    throw const FormatException('Invalid draft storage format');
  }

  Map<String, Object> toJson() => {
    'version': _draftFileFormatVersion,
    'values': values,
    'blockedLegacyKeys': blockedLegacyKeys.toList()..sort(),
    'blockedLegacyPrefixes': blockedLegacyPrefixes.toList()..sort(),
  };
}

/// The copy of a draft the site has not got yet.
///
/// Server drafts are for carrying a reply to another device. This is the other
/// half: what makes quitting and reopening safe when the site could not be
/// reached, which is exactly when losing what someone wrote hurts most.
///
/// It is written on every autosave and deleted the moment the server has the
/// same text, so its presence means one thing only — there is writing here the
/// site has not seen. That is what lets a restore prefer it without needing a
/// timestamp to compare.
///
/// Reads and cleanup are best-effort so storage trouble cannot break the
/// composer. Writes surface [DraftWriteException]: claiming that text is safe
/// on this device when private storage rejected it would risk losing that text.
class DraftStore {
  DraftStore({DraftPersistence? persistence})
    : _persistence = persistence ?? _platformDraftPersistence();

  static const String _prefix = 'discourse_native.draft::';

  final DraftPersistence _persistence;
  final Map<String, Future<void>> _siteOperations = {};

  static String _key(String siteUrl, String draftKey) =>
      '$_prefix$siteUrl::$draftKey';

  Future<String?> read(String siteUrl, String draftKey) =>
      _serialize(siteUrl, () => _read(siteUrl, draftKey));

  Future<String?> _read(String siteUrl, String draftKey) async {
    final key = _key(siteUrl, draftKey);

    final DraftPersistenceRead stored;
    try {
      stored = await _persistence.read(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.readSecure');
      // A failed read means durable key/site blockers are also unknown. Fail
      // closed: a preference value could belong to an account that was cleared
      // while this backend was healthy. Leave it untouched for a later retry.
      return null;
    }

    if (stored.value case final value?) {
      await _removeLegacy(key);
      return value;
    }
    if (!stored.allowPreferenceFallback) {
      await _removeLegacy(key);
      return null;
    }

    final prefs = await _preferences();
    final legacy = prefs?.getString(key);
    if (legacy == null) return null;

    try {
      await _persistence.write(key, legacy);
      await prefs?.remove(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.migrateLegacy');
    }
    return legacy;
  }

  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) => _serialize(
    siteUrl,
    () => _write(siteUrl, draftKey, data, ifCurrent: ifCurrent),
  );

  Future<void> _write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    final key = _key(siteUrl, draftKey);
    final prefs = await _preferences();
    if (ifCurrent != null && !ifCurrent()) return;

    try {
      await _persistence.write(key, data);
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'draft.writeSecure',
        severity: DiagnosticSeverity.error,
      );
      Error.throwWithStackTrace(DraftWriteException(error), stackTrace);
    }
    try {
      await prefs?.remove(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.removeLegacy');
    }
  }

  Future<void> clear(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) => _serialize(
    siteUrl,
    () => _clear(siteUrl, draftKey, ifCurrent: ifCurrent),
  );

  Future<void> _clear(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    final key = _key(siteUrl, draftKey);
    final prefs = await _preferences();
    if (ifCurrent != null && !ifCurrent()) return;

    try {
      await _persistence.delete(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.clearSecure');
    }
    try {
      await prefs?.remove(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.clearLegacy');
    }
  }

  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) =>
      _serialize(siteUrl, () => _clearSite(siteUrl, ifCurrent: ifCurrent));

  Future<void> _clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    final prefix = '$_prefix$siteUrl::';
    final prefs = await _preferences();
    if (ifCurrent != null && !ifCurrent()) return;

    try {
      await _persistence.deletePrefix(prefix);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.clearSiteSecure');
      // This is an account boundary. Continuing without a durable site blocker
      // could expose the previous account's text after reconnecting.
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (prefs != null) {
      try {
        await Future.wait([
          for (final key in prefs.getKeys())
            if (key.startsWith(prefix)) prefs.remove(key),
        ]);
      } catch (error, stackTrace) {
        reportStorageFailure(error, stackTrace, 'draft.clearSiteLegacy');
      }
    }
  }

  Future<SharedPreferences?> _preferences() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.openPreferences');
      return null;
    }
  }

  Future<void> _removeLegacy(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.removeLegacy');
    }
  }

  Future<T> _serialize<T>(String siteUrl, Future<T> Function() operation) {
    final result = Completer<T>();
    final previous = _siteOperations[siteUrl] ?? Future<void>.value();
    final current = previous.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    _siteOperations[siteUrl] = current;
    unawaited(
      current.whenComplete(() {
        if (identical(_siteOperations[siteUrl], current)) {
          final _ = _siteOperations.remove(siteUrl);
        }
      }),
    );
    return result.future;
  }
}
