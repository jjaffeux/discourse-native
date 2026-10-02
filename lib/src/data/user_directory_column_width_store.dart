import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'serial_operation_queue.dart';
import 'site_preference_keys.dart';
import 'store_diagnostics.dart';

abstract interface class UserDirectoryColumnWidthPersistence {
  Future<String?> readWidths({required String siteUrl});

  Future<bool> writeWidths({required String siteUrl, required String encoded});
}

final class SharedPreferencesUserDirectoryColumnWidthPersistence
    implements UserDirectoryColumnWidthPersistence {
  const SharedPreferencesUserDirectoryColumnWidthPersistence();

  static const keys = SitePreferenceKey(
    'discourse_native.user_directory_column_widths',
  );

  @override
  Future<String?> readWidths({required String siteUrl}) async =>
      (await SharedPreferences.getInstance()).getString(_key(siteUrl));

  @override
  Future<bool> writeWidths({
    required String siteUrl,
    required String encoded,
  }) async =>
      (await SharedPreferences.getInstance()).setString(_key(siteUrl), encoded);

  static String _key(String siteUrl) => keys.of(siteUrl);
}

@immutable
final class UserDirectoryColumnWidths {
  UserDirectoryColumnWidths(Map<String, double> widths)
    : widths = Map.unmodifiable(_validated(widths));

  const UserDirectoryColumnWidths.empty() : widths = const {};

  static const int _version = 1;
  static const int _maximumColumns = 256;
  static const int _maximumKeyLength = 200;
  static const double _minimumStoredWidth = 40;
  static const double _maximumStoredWidth = 4096;

  final Map<String, double> widths;

  double? operator [](String key) => widths[key];

  bool get isEmpty => widths.isEmpty;

  String encode() => jsonEncode({'version': _version, 'widths': widths});

  static UserDirectoryColumnWidths decode(String? encoded) {
    if (encoded == null || encoded.length > 65536) {
      return const UserDirectoryColumnWidths.empty();
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> || decoded['version'] != _version) {
      return const UserDirectoryColumnWidths.empty();
    }
    final rawWidths = decoded['widths'];
    if (rawWidths is! Map<String, dynamic>) {
      return const UserDirectoryColumnWidths.empty();
    }
    return UserDirectoryColumnWidths({
      for (final entry in rawWidths.entries)
        if (entry.value is num) entry.key: (entry.value as num).toDouble(),
    });
  }

  static Map<String, double> _validated(Map<String, double> widths) {
    final result = <String, double>{};
    for (final entry in widths.entries) {
      if (result.length >= _maximumColumns) break;
      final key = entry.key;
      final width = entry.value;
      if (key.isEmpty ||
          key.length > _maximumKeyLength ||
          !width.isFinite ||
          width < _minimumStoredWidth ||
          width > _maximumStoredWidth) {
        continue;
      }
      result[key] = width;
    }
    return result;
  }
}

final class UserDirectoryColumnWidthStore {
  const UserDirectoryColumnWidthStore({
    UserDirectoryColumnWidthPersistence? persistence,
  }) : _persistence =
           persistence ??
           const SharedPreferencesUserDirectoryColumnWidthPersistence();

  final UserDirectoryColumnWidthPersistence _persistence;
  static final ReadAfterWriteOperationQueue _operations =
      ReadAfterWriteOperationQueue();
  static final Expando<Map<String, Object>> _siteOwners = Expando();

  Map<String, Object> get _owners => _siteOwners[_persistence] ??= {};

  Object _owner(String siteUrl) => _owners.putIfAbsent(siteUrl, Object.new);

  bool _owns(String siteUrl, Object owner) =>
      identical(_owners[siteUrl], owner);

  /// Retires pending resizes and reads when [forgetSitePreferences] drops a
  /// forum. A re-add owns fresh operations in the same persistence queue.
  void forgetSites(ForgottenSites sites) => _owners.removeWhere(
    (site, _) => sites.includes(
      site,
      SharedPreferencesUserDirectoryColumnWidthPersistence.keys,
    ),
  );

  Future<UserDirectoryColumnWidths> read({required String siteUrl}) {
    final owner = _owner(siteUrl);
    return _operations.read(
      owner: _persistence,
      key: siteUrl,
      operation: () => _read(siteUrl, owner),
    );
  }

  Future<UserDirectoryColumnWidths> _read(String siteUrl, Object owner) async {
    try {
      final encoded = await _persistence.readWidths(siteUrl: siteUrl);
      if (!_owns(siteUrl, owner)) {
        return const UserDirectoryColumnWidths.empty();
      }
      return UserDirectoryColumnWidths.decode(encoded);
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'userDirectoryColumnWidths.read');
      return const UserDirectoryColumnWidths.empty();
    }
  }

  Future<void> write({
    required String siteUrl,
    required UserDirectoryColumnWidths widths,
  }) {
    final owner = _owner(siteUrl);
    return _operations.write<void>(
      owner: _persistence,
      key: siteUrl,
      operation: () async {
        if (!_owns(siteUrl, owner)) return;
        await _write(siteUrl: siteUrl, widths: widths);
      },
    );
  }

  Future<void> _write({
    required String siteUrl,
    required UserDirectoryColumnWidths widths,
  }) async {
    try {
      final saved = await _persistence.writeWidths(
        siteUrl: siteUrl,
        encoded: widths.encode(),
      );
      if (!saved) {
        throw StateError('Could not persist user directory column widths.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(
        error,
        stackTrace,
        'userDirectoryColumnWidths.write',
      );
    }
  }
}
