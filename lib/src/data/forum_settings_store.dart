import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/forum_theme_preferences.dart';
import 'scalar_preference_repository.dart';
import 'serial_operation_queue.dart';
import 'store_diagnostics.dart';
import 'stored_forum_base.dart';

final class ForumSettingsStore {
  ForumSettingsStore({ScalarPreferencePersistence<String>? persistence})
    : _persistence = persistence ?? const _ForumSettingsPersistence();

  ForumSettingsStore.memory() : _persistence = _MemoryPersistence();

  final ScalarPreferencePersistence<String> _persistence;
  static final _operations = SerialOperationQueue();

  static String themeModeKey(String siteUrl) =>
      'discourse_native.forum_theme_mode.'
      '${Uri.encodeComponent(requireStoredForumBase(siteUrl))}';

  static String themesKey(String siteUrl) =>
      'discourse_native.forum_themes.'
      '${Uri.encodeComponent(requireStoredForumBase(siteUrl))}';

  Future<ForumThemePreferences> loadThemes(String siteUrl) => _operations.run(
    owner: _persistence,
    key: themesKey(siteUrl),
    operation: () async {
      try {
        final raw = await _persistence.read(themesKey(siteUrl));
        if (raw == null) return ForumThemePreferences.defaults;
        return ForumThemePreferences.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (error, stackTrace) {
        reportStorageFailure(error, stackTrace, 'forumSettings.readThemes');
        return ForumThemePreferences.defaults;
      }
    },
  );

  Future<void> writeThemes(String siteUrl, ForumThemePreferences value) =>
      _operations.run<void>(
        owner: _persistence,
        key: themesKey(siteUrl),
        operation: () async {
          try {
            if (!await _persistence.write(
              themesKey(siteUrl),
              jsonEncode(value.toJson()),
            )) {
              throw StateError('Could not save the forum theme.');
            }
          } catch (error, stackTrace) {
            reportStorageFailure(
              error,
              stackTrace,
              'forumSettings.writeThemes',
            );
            rethrow;
          }
        },
      );

  /// Seeds a previously unconfigured forum once, preserving the old app choice
  /// for existing forums and using System for newly connected forums.
  Future<AppThemeMode> loadThemeMode(
    String siteUrl, {
    AppThemeMode initialMode = AppThemeMode.system,
  }) {
    final key = themeModeKey(siteUrl);
    return _operations.run(
      owner: _persistence,
      key: key,
      operation: () async {
        try {
          final stored = await _persistence.read(key);
          if (stored == null) {
            await _persist(key, initialMode);
            return initialMode;
          }
          return AppThemeMode.values.firstWhere(
            (mode) => mode.name == stored,
            orElse: () => AppThemeMode.system,
          );
        } catch (error, stackTrace) {
          reportStorageFailure(
            error,
            stackTrace,
            'forumSettings.readThemeMode',
          );
          return initialMode;
        }
      },
    );
  }

  Future<void> writeThemeMode(String siteUrl, AppThemeMode mode) {
    final key = themeModeKey(siteUrl);
    return _operations.run<void>(
      owner: _persistence,
      key: key,
      operation: () => _persist(key, mode),
    );
  }

  Future<void> _persist(String key, AppThemeMode mode) async {
    try {
      if (!await _persistence.write(key, mode.name)) {
        throw StateError('Could not persist the forum theme mode.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'forumSettings.writeThemeMode');
    }
  }
}

final class _ForumSettingsPersistence
    extends SharedPreferencesScalarPreferencePersistence<String> {
  const _ForumSettingsPersistence();

  @override
  String? readValue(SharedPreferences preferences, String key) =>
      preferences.getString(key);

  @override
  Future<bool> writeValue(
    SharedPreferences preferences,
    String key,
    String value,
  ) => preferences.setString(key, value);
}

final class _MemoryPersistence implements ScalarPreferencePersistence<String> {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<bool> write(String key, String value) async {
    _values[key] = value;
    return true;
  }
}
