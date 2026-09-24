import 'dart:async';
import 'dart:ui';

import '../data/forum_settings_store.dart';
import '../data/preference_snapshots.dart';
import '../data/serial_operation_queue.dart';
import '../data/stored_forum_base.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/app_settings.dart';
import '../models/forum_theme.dart';
import '../models/forum_theme_preferences.dart';
import '../models/site_appearance.dart';

final class ForumSettingsController extends FrameSafeNotifier {
  ForumSettingsController({required this.store});

  final ForumSettingsStore store;
  final _themeModes = PreferenceSnapshots<String, AppThemeMode>();

  final _themes = PreferenceSnapshots<String, ForumThemePreferences>();
  final _themeImports = SerialOperationQueue();
  final _themeWrites = <String, _ThemeWrite>{};

  ForumThemePreferences themesFor(String siteUrl) =>
      _themes.peek(requireStoredForumBase(siteUrl)) ??
      ForumThemePreferences.defaults;

  SiteAppearance? appearanceFor(
    String siteUrl,
    SiteAppearance? forumAppearance,
  ) {
    final preferences = themesFor(siteUrl);
    final themes = {
      for (final mode in Brightness.values) mode: preferences.themeFor(mode),
    };
    if (themes.values.every((theme) => theme == null)) return forumAppearance;
    // A mode without its own choice keeps the forum's palette for that mode.
    ResolvedSitePalette? palette(Brightness brightness) =>
        themes[brightness]?.resolve(
          brightness,
          forumPalette:
              forumAppearance?.paletteForBrightness(brightness) ??
              forumAppearance?.base ??
              forumAppearance?.alternate,
        ) ??
        forumAppearance?.paletteForBrightness(brightness);
    return SiteAppearance(
      base: palette(Brightness.light),
      alternate: palette(Brightness.dark),
    );
  }

  Future<void> setThemes(String siteUrl, ForumThemePreferences value) {
    final site = requireStoredForumBase(siteUrl);
    if (isDisposed) return Future.value();
    if (_themes.peek(site) == value) {
      return _themeWrites[site]?.completion.future ?? Future.value();
    }
    final existing = _themeWrites[site];
    final write = existing ?? _ThemeWrite(themesFor(site));
    _themeWrites[site] = write;
    write.pending = value;
    _themes.remember(site, value);
    notifySafely();
    if (existing == null) unawaited(_persistThemes(site, write));
    return write.completion.future;
  }

  Future<void> _persistThemes(String site, _ThemeWrite write) async {
    while (write.pending != null) {
      final value = write.pending!;
      write.pending = null;
      try {
        await store.writeThemes(site, value);
        write.saved = value;
      } catch (error, stack) {
        // A newer live edit supersedes an obsolete failed write. Try that
        // latest value before reporting a failure or reverting the app.
        if (write.pending != null) continue;
        _themeWrites.remove(site);
        if (!isDisposed) {
          _themes.remember(site, write.saved);
          notifySafely();
        }
        write.completion.completeError(error, stack);
        return;
      }
    }
    _themeWrites.remove(site);
    write.completion.complete();
  }

  /// Loads the destination library before importing, preserving its font and
  /// other custom themes. Serial imports also retain simultaneous shares.
  Future<ForumThemePreferences> importTheme(String siteUrl, ForumTheme theme) {
    final site = requireStoredForumBase(siteUrl);
    return _themeImports.run(
      owner: this,
      key: site,
      operation: () async {
        await _themes.ensure(site, () => store.loadThemes(site));
        final previous = themesFor(site);
        if (!isDisposed) await setThemes(site, previous.importTheme(theme));
        return previous;
      },
    );
  }

  AppThemeMode themeModeFor(String siteUrl) =>
      _themeModes.peek(requireStoredForumBase(siteUrl)) ?? AppThemeMode.system;

  Future<void> load(
    String siteUrl, {
    AppThemeMode initialMode = AppThemeMode.system,
  }) async {
    if (isDisposed) return;
    final site = requireStoredForumBase(siteUrl);
    await Future.wait([
      _themeModes.ensure(
        site,
        () => store.loadThemeMode(site, initialMode: initialMode),
      ),
      _themes.ensure(site, () => store.loadThemes(site)),
    ]);
    if (!isDisposed) notifySafely();
  }

  Future<void> setThemeMode(String siteUrl, AppThemeMode mode) {
    final site = requireStoredForumBase(siteUrl);
    if (isDisposed || _themeModes.peek(site) == mode) {
      return Future<void>.value();
    }
    _themeModes.remember(site, mode);
    final saving = store.writeThemeMode(site, mode);
    notifySafely();
    return saving;
  }
}

final class _ThemeWrite {
  _ThemeWrite(this.saved);
  ForumThemePreferences saved;
  ForumThemePreferences? pending;
  final completion = Completer<void>();
}
