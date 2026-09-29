import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/forum_background.dart';
import '../models/forum_font.dart';
import '../models/forum_theme_library.dart';
import '../models/forum_theme_preferences.dart';
import '../models/shared_appearance.dart';
import 'scalar_preference_repository.dart';
import 'serial_operation_queue.dart';
import 'site_preference_keys.dart';
import 'store_diagnostics.dart';
import 'stored_forum_base.dart';

final class ForumSettingsStore {
  ForumSettingsStore({ScalarPreferencePersistence<String>? persistence})
    : _persistence = persistence ?? const _ForumSettingsPersistence();

  ForumSettingsStore.memory() : _persistence = _MemoryPersistence();

  final ScalarPreferencePersistence<String> _persistence;
  static final _operations = SerialOperationQueue();

  static const themeModeKeys = SitePreferenceKey(
    'discourse_native.forum_theme_mode',
  );

  static const themesKeys = SitePreferenceKey('discourse_native.forum_themes');

  static String themeModeKey(String siteUrl) =>
      themeModeKeys.of(requireStoredForumBase(siteUrl));

  static String themesKey(String siteUrl) =>
      themesKeys.of(requireStoredForumBase(siteUrl));

  static const appearanceKey = 'discourse_native.appearance';

  /// The font and effects every forum shares. Before anything is stored they
  /// come from what [sites] chose when both were per forum: the first site,
  /// in order, with a font of its own gives the font, and the first showing a
  /// saved theme with effects gives the effects. That is stored at once, so
  /// the forums' own documents are consulted only this one time.
  Future<SharedAppearance> loadAppearance({
    Iterable<String> sites = const [],
  }) => _operations.run(
    owner: _persistence,
    key: appearanceKey,
    operation: () async {
      try {
        final raw = await _persistence.read(appearanceKey);
        if (raw != null) {
          return SharedAppearance.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
        }
      } catch (error, stackTrace) {
        // Unreadable is not absent: adopting would replace a stored choice.
        reportStorageFailure(error, stackTrace, 'forumSettings.readAppearance');
        return SharedAppearance.defaults;
      }
      final adopted = await _adoptAppearance(sites);
      try {
        await _writeAppearance(adopted);
      } catch (_) {
        // Reported by the write; the adopted values still apply this session.
      }
      return adopted;
    },
  );

  Future<void> writeAppearance(SharedAppearance value) => _operations.run(
    owner: _persistence,
    key: appearanceKey,
    operation: () => _writeAppearance(value),
  );

  Future<void> _writeAppearance(SharedAppearance value) async {
    try {
      if (!await _persistence.write(
        appearanceKey,
        jsonEncode(value.toJson()),
      )) {
        throw StateError('Could not save the appearance.');
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'forumSettings.writeAppearance');
      rethrow;
    }
  }

  Future<SharedAppearance> _adoptAppearance(Iterable<String> sites) async {
    ForumFont? font;
    ForumBackground? effects;
    for (final site in sites) {
      if (font != null && effects != null) break;
      final Map<String, dynamic> json;
      try {
        final raw = await _operations.run(
          owner: _persistence,
          key: themesKey(site),
          operation: () => _persistence.read(themesKey(site)),
        );
        if (raw == null) continue;
        json = jsonDecode(raw) as Map<String, dynamic>;
      } catch (error, stackTrace) {
        reportStorageFailure(error, stackTrace, 'forumSettings.readThemes');
        continue;
      }
      final own = ForumFont.fromName(json['font']);
      if (own != ForumFont.system) font ??= own;
      try {
        final preferences = ForumThemePreferences.fromJson(json);
        final theme = preferences.source == ForumThemeSource.custom
            ? preferences.customTheme
            : null;
        final background = (theme?.background ?? theme?.alternate?.background)
            ?.toAccentTint()
            .copyWith(strength: 0);
        if (background != null && !background.isPlain) effects ??= background;
      } on FormatException {
        // A damaged document still gave its font.
      }
    }
    return SharedAppearance(
      font: font ?? ForumFont.system,
      effects: effects ?? const ForumBackground.appearance(),
    );
  }

  static const themeLibraryKey = 'discourse_native.theme_library';
  ForumThemeLibrary _themeLibrary = ForumThemeLibrary();
  final _pendingThemeMigrations = <String, ForumThemePreferences>{};
  ForumThemeLibrary get themeLibrary => _themeLibrary;

  Future<ForumThemeLibrary> _readThemeLibrary() async {
    final raw = await _persistence.read(themeLibraryKey);
    var library = raw == null
        ? ForumThemeLibrary()
        : ForumThemeLibrary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    for (final entry in _pendingThemeMigrations.entries) {
      library = library.migrate(entry.key, entry.value);
    }
    return library;
  }

  Future<ForumThemeLibrary> _migrateThemes(
    ForumThemeLibrary library,
    String site,
  ) async {
    if (library.forums.containsKey(site)) return library;
    final raw = await _persistence.read(themesKey(site));
    final legacy = raw == null
        ? ForumThemePreferences.defaults
        : ForumThemePreferences.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
    _pendingThemeMigrations[site] = legacy;
    return library.migrate(site, legacy);
  }

  Future<void> _writeThemeLibrary(ForumThemeLibrary library) async {
    if (!await _persistence.write(
      themeLibraryKey,
      jsonEncode(library.toJson()),
    )) {
      throw StateError('Could not save the theme library.');
    }
    _themeLibrary = library;
    _pendingThemeMigrations.removeWhere(
      (site, _) => library.forums.containsKey(site),
    );
  }

  Future<ForumThemePreferences> loadThemes(String siteUrl) => _operations.run(
    owner: _persistence,
    key: themeLibraryKey,
    operation: () async {
      final site = requireStoredForumBase(siteUrl);
      try {
        final library = await _readThemeLibrary();
        final migrated = await _migrateThemes(library, site);
        if (!identical(library, migrated) ||
            _pendingThemeMigrations.isNotEmpty) {
          // Keep the legacy document until the whole migration is durable.
          try {
            await _writeThemeLibrary(migrated);
          } catch (error, stackTrace) {
            reportStorageFailure(
              error,
              stackTrace,
              'forumSettings.migrateThemes',
            );
            // Keep showing the legacy choice and retry migration next load.
            _themeLibrary = migrated;
          }
        } else {
          _themeLibrary = library;
        }
        return migrated.forSite(site);
      } catch (error, stackTrace) {
        reportStorageFailure(error, stackTrace, 'forumSettings.readThemes');
        return _themeLibrary.forSite(site);
      }
    },
  );

  Future<void> writeThemes(
    String siteUrl,
    ForumThemePreferences value, {
    ForumThemePreferences? previous,
  }) => _operations.run<void>(
    owner: _persistence,
    key: themeLibraryKey,
    operation: () async {
      final site = requireStoredForumBase(siteUrl);
      try {
        final library = await _migrateThemes(await _readThemeLibrary(), site);
        await _writeThemeLibrary(
          library.update(
            site,
            value,
            previous: previous ?? library.forSite(site),
          ),
        );
      } catch (error, stackTrace) {
        reportStorageFailure(error, stackTrace, 'forumSettings.writeThemes');
        rethrow;
      }
    },
  );

  /// Disconnecting forgets selections but keeps the shared authored themes.
  Future<void> forgetThemes(ForgottenSites sites) => _operations.run<void>(
    owner: _persistence,
    key: themeLibraryKey,
    operation: () async {
      final library = await _readThemeLibrary();
      _pendingThemeMigrations.removeWhere((site, _) => sites.includes(site));
      await _writeThemeLibrary(
        ForumThemeLibrary(
          themes: library.themes,
          forums: Map.fromEntries(
            library.forums.entries.where((entry) => !sites.includes(entry.key)),
          ),
        ),
      );
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
