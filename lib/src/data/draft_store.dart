import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';

abstract interface class DraftPersistence {
  Future<String?> read(String key);

  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class SecureDraftPersistence implements DraftPersistence {
  SecureDraftPersistence({FlutterSecureStorage? storage})
    : _storage = storage ?? SecureStore.platformStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
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
/// Every operation swallows its failures. A draft mirror that cannot be
/// written is a worse draft mirror; a draft mirror that throws into the
/// composer is a broken composer.
class DraftStore {
  DraftStore({DraftPersistence? persistence})
    : _persistence = persistence ?? SecureDraftPersistence();

  static const String _prefix = 'discourse_native.draft::';

  final DraftPersistence _persistence;
  final Map<String, Future<void>> _siteOperations = {};

  static String _key(String siteUrl, String draftKey) =>
      '$_prefix$siteUrl::$draftKey';

  Future<String?> read(String siteUrl, String draftKey) =>
      _serialize(siteUrl, () => _read(siteUrl, draftKey));

  Future<String?> _read(String siteUrl, String draftKey) async {
    final key = _key(siteUrl, draftKey);

    final String? stored;
    try {
      stored = await _persistence.read(key);
    } catch (_) {
      // A failed read does not prove the secure copy is absent. Keep the
      // plaintext fallback available, but do not let it overwrite an unknown
      // secure value or remove the only copy we can currently read.
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
    } catch (_) {}
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
      await prefs?.remove(key);
    } catch (_) {}
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
    } catch (_) {}
    try {
      await prefs?.remove(key);
    } catch (_) {}
  }

  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) =>
      _serialize(siteUrl, () => _clearSite(siteUrl, ifCurrent: ifCurrent));

  Future<void> _clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    final prefix = '$_prefix$siteUrl::';
    Map<String, String> stored = const {};
    try {
      stored = await _persistence.readAll();
    } catch (_) {}
    final prefs = await _preferences();
    if (ifCurrent != null && !ifCurrent()) return;

    try {
      await Future.wait([
        for (final key in stored.keys)
          if (key.startsWith(prefix)) _persistence.delete(key),
      ]);
    } catch (_) {}
    if (prefs != null) {
      try {
        await Future.wait([
          for (final key in prefs.getKeys())
            if (key.startsWith(prefix)) prefs.remove(key),
        ]);
      } catch (_) {}
    }
  }

  Future<SharedPreferences?> _preferences() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeLegacy(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
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
