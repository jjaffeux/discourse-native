import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/l10n/strings.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../foundation/private_file_document.dart';
import 'preference_storage_scope.dart';
import 'private_storage.dart';

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

  static const _retiredKeyPrefix = 'discourse_native.retired_draft_key::';
  static const _retiredPrefixPrefix = 'discourse_native.retired_draft_prefix::';

  final EnumerablePrivateStorage _storage;

  @override
  Future<DraftPersistenceRead> read(String key) async {
    final values = await _storage.readAll();
    final retired =
        values.containsKey('$_retiredKeyPrefix$key') ||
        values.keys.any(
          (storedKey) =>
              storedKey.startsWith(_retiredPrefixPrefix) &&
              key.startsWith(storedKey.substring(_retiredPrefixPrefix.length)),
        );
    return (value: values[key], allowPreferenceFallback: !retired);
  }

  @override
  Future<void> write(String key, String value) => _storage.write(key, value);

  @override
  Future<void> delete(String key) async {
    await _storage.write('$_retiredKeyPrefix$key', '');
    await _storage.delete(key);
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    await _storage.write('$_retiredPrefixPrefix$prefix', '');
    await _storage.deletePrefix(prefix);
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

  final File? _providedFile;
  final PrivateStorage? _legacyStorage;
  late final PrivateFileDocument<_DraftFileState> _document =
      PrivateFileDocument(
        target: _file,
        empty: _DraftFileState.new,
        decode: _decodeDraftFileState,
        encode: _encodeDraftFileState,
        snapshot: _DraftFileSnapshot.new,
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
      state.blockLegacyKey(key);
      return PrivateFileResult((
        value: legacyValue,
        allowPreferenceFallback: false,
      ));
    });
  }

  @override
  Future<void> write(String key, String value) => _document.update((state) {
    state.values[key] = value;
    state.blockLegacyKey(key);
    return PrivateFileResult.done;
  });

  @override
  Future<void> delete(String key) => _document.update((state) {
    state.values.remove(key);
    state.blockLegacyKey(key);
    return PrivateFileResult.done;
  });

  @override
  Future<void> deletePrefix(String prefix) => _document.update((state) {
    state.values.removeWhere((key, _) => key.startsWith(prefix));
    state.blockedLegacyKeys.removeWhere((key) => key.startsWith(prefix));
    state.blockedLegacyPrefixes.add(prefix);
    return PrivateFileResult.done;
  });

  _DraftProbe _probe(_DraftFileState state, String key) =>
      (value: state.values[key], blocked: state.blocksLegacy(key));

  static DraftPersistenceRead _result(_DraftProbe probe) =>
      (value: probe.value, allowPreferenceFallback: !probe.blocked);

  Future<File> _file() async {
    final provided = _providedFile;
    if (provided != null) return provided;
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/$directoryName/$fileName');
  }
}

Future<_DraftFileState> _decodeDraftFileState(String contents) {
  final locale = Intl.getCurrentLocale();
  return _DraftFileCodecs.run(
    () =>
        Intl.withLocale<_DraftFileState>(locale, () {
              final Object? decoded;
              try {
                decoded = jsonDecode(contents);
              } on FormatException catch (error) {
                throw FormatException(
                  appL10n.invalidDraftStorage((error.message).toString()),
                );
              }
              return _DraftFileState.decode(decoded);
            })
            as _DraftFileState,
  );
}

Future<String> _encodeDraftFileState(_DraftFileState state) {
  final snapshot = _DraftFileSnapshot(state);
  return _DraftFileCodecs.run(() => jsonEncode(snapshot.toJson()));
}

abstract final class _DraftFileCodecs {
  static Future<void> _tail = Future<void>.value();

  static Future<T> run<T>(T Function() computation) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    await previous;
    try {
      return await Isolate.run(computation, debugName: 'draft-file-codec');
    } finally {
      released.complete();
    }
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
          throw FormatException(appL10n.invalidDraftStorageValuesMustBeStrings);
        }
        values[key] = value;
      }
      if (rawKeys.any((value) => value is! String) ||
          rawPrefixes.any((value) => value is! String)) {
        throw FormatException(appL10n.invalidDraftStorageBlockersMustBeStrings);
      }
      final state = _DraftFileState(
        values: values,
        blockedLegacyKeys: rawKeys.cast<String>().toSet(),
        blockedLegacyPrefixes: rawPrefixes.cast<String>().toSet(),
      );
      return state..blockedLegacyKeys.removeWhere(state._coveredBySite);
    }
    throw FormatException(appL10n.invalidDraftStorageFormat);
  }

  bool blocksLegacy(String key) =>
      blockedLegacyKeys.contains(key) || _coveredBySite(key);

  /// Site blockers are never lifted, so a key blocker under one cannot change
  /// what [blocksLegacy] answers. Recording it anyway would permanently grow,
  /// by one entry per draft ever saved or cleared, the file which each
  /// composer autosave rereads and rewrites.
  void blockLegacyKey(String key) {
    if (!_coveredBySite(key)) blockedLegacyKeys.add(key);
  }

  bool _coveredBySite(String key) => blockedLegacyPrefixes.any(key.startsWith);
}

final class _DraftFileSnapshot {
  _DraftFileSnapshot(_DraftFileState state)
    : values = Map.unmodifiable(state.values),
      blockedLegacyKeys = Set.unmodifiable(state.blockedLegacyKeys),
      blockedLegacyPrefixes = Set.unmodifiable(state.blockedLegacyPrefixes);

  final Map<String, String> values;
  final Set<String> blockedLegacyKeys;
  final Set<String> blockedLegacyPrefixes;

  Map<String, Object> toJson() => {
    'version': _draftFileFormatVersion,
    'values': values,
    'blockedLegacyKeys': blockedLegacyKeys.toList()..sort(),
    'blockedLegacyPrefixes': blockedLegacyPrefixes.toList()..sort(),
  };

  @override
  bool operator ==(Object other) {
    if (other is! _DraftFileSnapshot ||
        values.length != other.values.length ||
        blockedLegacyKeys.length != other.blockedLegacyKeys.length ||
        blockedLegacyPrefixes.length != other.blockedLegacyPrefixes.length ||
        !blockedLegacyKeys.containsAll(other.blockedLegacyKeys) ||
        !blockedLegacyPrefixes.containsAll(other.blockedLegacyPrefixes)) {
      return false;
    }
    final entries = other.values.entries.iterator;
    for (final MapEntry(:key, :value) in values.entries) {
      entries.moveNext();
      if (entries.current.key != key || entries.current.value != value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(
      values.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(blockedLegacyKeys),
    Object.hashAllUnordered(blockedLegacyPrefixes),
  );
}

/// Presence means the site has not received this text, so restore prefers it
/// without comparing timestamps. Reads and cleanup are best-effort, but writes
/// fail rather than claim that rejected text is safely stored on the device.
@PreferenceStorage.document(
  'DraftStore.clearSite retires private drafts and legacy preference fallback together.',
)
class DraftStore {
  DraftStore({DraftPersistence? persistence})
    : _persistence = persistence ?? _platformDraftPersistence();

  static const String _prefix = 'discourse_native.draft::';
  static const String _accountPrefix = 'discourse_native.account_draft::';
  static const String _accountSitePrefix =
      'discourse_native.account_draft_site::';

  /// A local storage address only. It must never be sent to the forum.
  static String accountSiteKey(String siteUrl, String? account) =>
      account == null
      ? siteUrl
      : '${accountSiteKeyPrefix(siteUrl)}${Uri.encodeComponent(account)}';

  static String accountSiteKeyPrefix(String siteUrl) =>
      '$_accountSitePrefix${Uri.encodeComponent(siteUrl)}::';

  static String realSiteUrl(String localSite) => _address(localSite).siteUrl;

  static ({String siteUrl, String? account}) _address(String localSite) {
    if (!localSite.startsWith(_accountSitePrefix)) {
      return (siteUrl: localSite, account: null);
    }
    final value = localSite.substring(_accountSitePrefix.length);
    final separator = value.indexOf('::');
    return (
      siteUrl: Uri.decodeComponent(value.substring(0, separator)),
      account: Uri.decodeComponent(value.substring(separator + 2)),
    );
  }

  final DraftPersistence _persistence;
  final Map<String, Future<void>> _siteOperations = {};

  static String _key(String localSite, String draftKey) {
    final address = _address(localSite);
    final account = address.account;
    return account == null
        ? '$_prefix${address.siteUrl}::$draftKey'
        : '$_accountPrefix${Uri.encodeComponent(address.siteUrl)}::${Uri.encodeComponent(account)}::$draftKey';
  }

  Future<String?> read(String siteUrl, String draftKey) async =>
      (await readChecked(siteUrl, draftKey)).value;

  Future<DraftStoreRead> readChecked(String siteUrl, String draftKey) =>
      _serialize(siteUrl, () => _read(siteUrl, draftKey));

  Future<DraftStoreRead> _read(String siteUrl, String draftKey) async {
    final key = _key(siteUrl, draftKey);

    final DraftPersistenceRead stored;
    try {
      stored = await _persistence.read(key);
    } catch (error) {
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
    final String? legacy;
    try {
      legacy = prefs?.getString(key);
    } catch (error) {
      // An unreadable legacy value is an unknown draft, not an empty one.
      // Leave it untouched so a later read can retry.
      return (value: null, succeeded: false);
    }
    if (legacy == null) return (value: null, succeeded: true);

    try {
      await _persistence.write(key, legacy);
      await prefs?.remove(key);
    } catch (_) {}
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
      Error.throwWithStackTrace(DraftWriteException(error), stackTrace);
    }
    try {
      await prefs?.remove(key);
    } catch (_) {}
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
    } catch (error) {
      succeeded = false;
    }
    try {
      await prefs?.remove(key);
    } catch (error) {
      succeeded = false;
    }
    return succeeded;
  }

  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) =>
      _serialize(siteUrl, () => _clearSite(siteUrl, ifCurrent: ifCurrent));

  Future<void> _clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    final address = _address(siteUrl);
    final legacyPrefix = '$_prefix${address.siteUrl}::';
    final accountPrefix =
        '$_accountPrefix${Uri.encodeComponent(address.siteUrl)}::';
    final prefixes = address.account == null
        ? [accountPrefix, legacyPrefix]
        : [legacyPrefix, accountPrefix];
    final preferences = await _preferencesChecked();
    final prefs = preferences.value;
    if (ifCurrent != null && !ifCurrent()) return;

    if (_persistence is PrivateDraftPersistence) {
      if (!preferences.succeeded || prefs == null) {
        throw StateError('Legacy draft preferences unavailable');
      }
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(prefixes.last)) continue;
        if (ifCurrent?.call() == false) return;
        final stored = await _persistence.read(key);
        if (ifCurrent?.call() == false) return;
        if (stored.value != null || !stored.allowPreferenceFallback) continue;
        final legacy = prefs.get(key);
        if (legacy is String) await _persistence.write(key, legacy);
      }
    }

    try {
      for (final prefix in prefixes) {
        if (ifCurrent?.call() == false) return;
        await _persistence.deletePrefix(prefix);
      }
    } catch (error, stackTrace) {
      // This is an account boundary. Continuing without a durable site blocker
      // could expose the previous account's text after reconnecting.
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (prefs != null) {
      try {
        await Future.wait([
          for (final key in prefs.getKeys())
            if (prefixes.any(key.startsWith)) prefs.remove(key),
        ]);
      } catch (_) {}
    }
  }

  Future<SharedPreferences?> _preferences() async {
    return (await _preferencesChecked()).value;
  }

  Future<({SharedPreferences? value, bool succeeded})>
  _preferencesChecked() async {
    try {
      return (value: await SharedPreferences.getInstance(), succeeded: true);
    } catch (error) {
      return (value: null, succeeded: false);
    }
  }

  Future<void> _removeLegacy(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  Future<T> _serialize<T>(String siteUrl, Future<T> Function() operation) {
    siteUrl = realSiteUrl(siteUrl);
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
