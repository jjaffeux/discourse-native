import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/diagnostics_controller.dart';
import 'private_storage.dart';

abstract interface class DraftPersistence {
  Future<String?> read(String key);

  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> delete(String key);
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
  PrivateDraftPersistence({PrivateStorage? storage})
    : _storage = storage ?? platformPrivateStorage;

  final PrivateStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> write(String key, String value) => _storage.write(key, value);

  @override
  Future<void> delete(String key) => _storage.delete(key);
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
    : _persistence = persistence ?? PrivateDraftPersistence();

  static const String _prefix = 'discourse_native.draft::';

  final DraftPersistence _persistence;
  final Map<String, Future<void>> _siteOperations = {};

  static void _report(
    Object error,
    StackTrace stackTrace,
    String operation, {
    DiagnosticSeverity severity = DiagnosticSeverity.warning,
  }) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'storage',
      severity: severity,
      handled: true,
      degraded: true,
    );
  }

  static String _key(String siteUrl, String draftKey) =>
      '$_prefix$siteUrl::$draftKey';

  Future<String?> read(String siteUrl, String draftKey) =>
      _serialize(siteUrl, () => _read(siteUrl, draftKey));

  Future<String?> _read(String siteUrl, String draftKey) async {
    final key = _key(siteUrl, draftKey);

    final String? stored;
    try {
      stored = await _persistence.read(key);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'draft.readSecure');
      // A failed read does not prove the private copy is absent. Keep the
      // plaintext fallback available, but do not let it overwrite an unknown
      // private value or remove the only copy we can currently read.
      return (await _preferences())?.getString(key);
    }

    if (stored != null) {
      await _removeLegacy(key);
      return stored;
    }

    final prefs = await _preferences();
    final legacy = prefs?.getString(key);
    if (legacy == null) return null;

    try {
      await _persistence.write(key, legacy);
      await prefs?.remove(key);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'draft.migrateLegacy');
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
      _report(
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
      _report(error, stackTrace, 'draft.removeLegacy');
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
      _report(error, stackTrace, 'draft.clearSecure');
    }
    try {
      await prefs?.remove(key);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'draft.clearLegacy');
    }
  }

  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) =>
      _serialize(siteUrl, () => _clearSite(siteUrl, ifCurrent: ifCurrent));

  Future<void> _clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    final prefix = '$_prefix$siteUrl::';
    Map<String, String> stored = const {};
    try {
      stored = await _persistence.readAll();
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'draft.readAllSecure');
    }
    final prefs = await _preferences();
    if (ifCurrent != null && !ifCurrent()) return;

    try {
      await Future.wait([
        for (final key in stored.keys)
          if (key.startsWith(prefix)) _persistence.delete(key),
      ]);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'draft.clearSiteSecure');
    }
    if (prefs != null) {
      try {
        await Future.wait([
          for (final key in prefs.getKeys())
            if (key.startsWith(prefix)) prefs.remove(key),
        ]);
      } catch (error, stackTrace) {
        _report(error, stackTrace, 'draft.clearSiteLegacy');
      }
    }
  }

  Future<SharedPreferences?> _preferences() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'draft.openPreferences');
      return null;
    }
  }

  Future<void> _removeLegacy(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'draft.removeLegacy');
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
