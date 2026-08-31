import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import '../foundation/private_file_document.dart';
import 'private_storage.dart';
import 'store_diagnostics.dart';

typedef DraftPersistenceRead = ({String? value, bool allowPreferenceFallback});
typedef DraftStoreRead = ({String? value, bool succeeded});

const int _draftFileFormatVersion = 1;

abstract interface class DraftPersistence {
  Future<DraftPersistenceRead> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<void> deletePrefix(String prefix);
}

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
  Future<void> deletePrefix(String prefix) => _storage.deletePrefix(prefix);
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

  final File? _providedFile;
  final PrivateStorage? _legacyStorage;
  late final PrivateFileDocument<_DraftFileState> _document =
      PrivateFileDocument(
        target: _file,
        empty: _DraftFileState.new,
        decode: _decodeState,
        encode: (state) => jsonEncode(state.toJson()),
      );

  @override
  Future<DraftPersistenceRead> read(String key) async {
    final first = await _document.read(
      (state) => PrivateFileResult(_probe(state, key)),
    );
    if (first.value != null || first.blocked) return _result(first);

    final legacy = _legacyStorage;
    if (legacy == null) {
      return (value: null, allowPreferenceFallback: true);
    }

    // Do not hold the file queue while macOS may be presenting an ACL dialog.
    final legacyValue = await legacy.read(key);
    return _document.update((state) {
      final latest = _probe(state, key);
      if (latest.value != null || latest.blocked) {
        return PrivateFileResult(_result(latest));
      }
      if (legacyValue == null) {
        return PrivateFileResult((value: null, allowPreferenceFallback: true));
      }

      state.values[key] = legacyValue;
      state.blockedLegacyKeys.add(key);
      return PrivateFileResult((
        value: legacyValue,
        allowPreferenceFallback: false,
      ));
    });
  }

  @override
  Future<void> write(String key, String value) => _document.update((state) {
    state.values[key] = value;
    state.blockedLegacyKeys.add(key);
    return PrivateFileResult.done;
  });

  @override
  Future<void> delete(String key) => _document.update((state) {
    state.values.remove(key);
    state.blockedLegacyKeys.add(key);
    return PrivateFileResult.done;
  });

  @override
  Future<void> deletePrefix(String prefix) => _document.update((state) {
    state.values.removeWhere((key, _) => key.startsWith(prefix));
    state.blockedLegacyKeys.removeWhere((key) => key.startsWith(prefix));
    state.blockedLegacyPrefixes.add(prefix);
    return PrivateFileResult.done;
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

  _DraftFileState _decodeState(String contents) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException catch (error) {
      throw FormatException('Invalid draft storage: ${error.message}');
    }
    return _DraftFileState.decode(decoded);
  }
}

typedef _DraftProbe = ({String? value, bool blocked});

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

/// Presence means the site has not received this text, so restore prefers it
/// without comparing timestamps. Reads and cleanup are best-effort, but writes
/// fail rather than claim that rejected text is safely stored on the device.
class DraftStore {
  DraftStore({DraftPersistence? persistence})
    : _persistence = persistence ?? _platformDraftPersistence();

  static const String _prefix = 'discourse_native.draft::';

  final DraftPersistence _persistence;
  final Map<String, Future<void>> _siteOperations = {};

  static String _key(String siteUrl, String draftKey) =>
      '$_prefix$siteUrl::$draftKey';

  Future<String?> read(String siteUrl, String draftKey) async =>
      (await readChecked(siteUrl, draftKey)).value;

  Future<DraftStoreRead> readChecked(String siteUrl, String draftKey) =>
      _serialize(siteUrl, () => _read(siteUrl, draftKey));

  Future<DraftStoreRead> _read(String siteUrl, String draftKey) async {
    final key = _key(siteUrl, draftKey);

    final DraftPersistenceRead stored;
    try {
      stored = await _persistence.read(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.readSecure');
      // A failed read means durable key/site blockers are also unknown. Fail
      // closed: a preference value could belong to an account that was cleared
      // while this backend was healthy. Leave it untouched for a later retry.
      return (value: null, succeeded: false);
    }

    if (stored.value case final value?) {
      await _removeLegacy(key);
      return (value: value, succeeded: true);
    }
    if (!stored.allowPreferenceFallback) {
      await _removeLegacy(key);
      return (value: null, succeeded: true);
    }

    final preferences = await _preferencesChecked();
    if (!preferences.succeeded) {
      return (value: null, succeeded: false);
    }
    final prefs = preferences.value;
    final legacy = prefs?.getString(key);
    if (legacy == null) return (value: null, succeeded: true);

    try {
      await _persistence.write(key, legacy);
      await prefs?.remove(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.migrateLegacy');
    }
    return (value: legacy, succeeded: true);
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
  }) async {
    await clearChecked(siteUrl, draftKey, ifCurrent: ifCurrent);
  }

  Future<bool> clearChecked(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) => _serialize(
    siteUrl,
    () => _clear(siteUrl, draftKey, ifCurrent: ifCurrent),
  );

  Future<bool> _clear(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    final key = _key(siteUrl, draftKey);
    final preferences = await _preferencesChecked();
    final prefs = preferences.value;
    if (ifCurrent != null && !ifCurrent()) return false;

    var succeeded = preferences.succeeded;
    try {
      await _persistence.delete(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.clearSecure');
      succeeded = false;
    }
    try {
      await prefs?.remove(key);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.clearLegacy');
      succeeded = false;
    }
    return succeeded;
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
    return (await _preferencesChecked()).value;
  }

  Future<({SharedPreferences? value, bool succeeded})>
  _preferencesChecked() async {
    try {
      return (value: await SharedPreferences.getInstance(), succeeded: true);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'draft.openPreferences');
      return (value: null, succeeded: false);
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
