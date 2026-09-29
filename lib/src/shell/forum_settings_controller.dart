import 'dart:async';
import 'dart:ui';

import '../data/forum_settings_store.dart';
import '../data/preference_snapshots.dart';
import '../data/serial_operation_queue.dart';
import '../data/site_preference_keys.dart';
import '../data/stored_forum_base.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/app_settings.dart';
import '../models/forum_theme.dart';
import '../models/forum_theme_library.dart';
import '../models/forum_theme_preferences.dart';
import '../models/shared_appearance.dart';
import '../models/site_appearance.dart';

final class ForumSettingsController extends FrameSafeNotifier {
  /// Local appearance identity for the Aggregate home workspace.
  static const homeSite = 'https://discourse.native.invalid/home';
  ForumSettingsController({required this.store});

  final ForumSettingsStore store;
  final _themeModes = PreferenceSnapshots<String, AppThemeMode>();

  final _themes = PreferenceSnapshots<String, ForumThemePreferences>();
  final _themeImports = SerialOperationQueue();
  final _themeEdits =
      <String, ({ForumThemePreferences before, ForumThemePreferences after})>{};
  final _themeWrites = <String, _Write<ForumThemePreferences>>{};
  final _previews = <String, _AppearancePreview>{};

  /// One document for every forum, so it shares the per-forum snapshots'
  /// rule that a choice made while it is read wins over what was read.
  final _shared = PreferenceSnapshots<String, SharedAppearance>();
  static const _everyForum = '';
  _Write<SharedAppearance>? _sharedWrite;

  ForumThemePreferences themesFor(String siteUrl) {
    final site = requireStoredForumBase(siteUrl);
    var library = store.themeLibrary.themes;
    for (final edit in _themeEdits.values) {
      library = ForumThemeLibrary.applyEdits(library, edit.before, edit.after);
    }
    return (_themes.peek(site) ?? store.themeLibrary.forSite(site)).withLibrary(
      library,
    );
  }

  /// Shared fonts and legacy effects; custom themes can override the effects.
  SharedAppearance get shared =>
      _shared.peek(_everyForum) ?? SharedAppearance.defaults;

  /// The mode the app shows while the Appearance page chooses colours for it,
  /// or null for the saved mode.
  Brightness? previewBrightnessFor(String siteUrl) =>
      _previews[requireStoredForumBase(siteUrl)]?.brightness;

  /// Shows [brightness] and a [draft] theme across the app while [owner], an
  /// open Appearance page, chooses or edits colours. Neither is stored.
  /// Passing neither ends [owner]'s preview and leaves another owner's alone.
  void preview(
    String siteUrl,
    Object owner, {
    Brightness? brightness,
    ForumTheme? draft,
  }) {
    if (isDisposed) return;
    final site = requireStoredForumBase(siteUrl);
    final current = _previews[site];
    if (brightness == null && draft == null) {
      if (current?.owner != owner) return;
      _previews.remove(site);
    } else {
      final next = (owner: owner, brightness: brightness, draft: draft);
      if (current == next) return;
      _previews[site] = next;
    }
    notifySafely();
  }

  SiteAppearance? appearanceFor(
    String siteUrl,
    SiteAppearance? forumAppearance,
  ) {
    final preferences = themesFor(siteUrl);
    final draft = _previews[requireStoredForumBase(siteUrl)]?.draft;
    final effects = shared.effects;
    final themes = {
      for (final mode in Brightness.values)
        mode: draft?.forBrightness(mode) ?? preferences.themeFor(mode),
    };
    if (effects.isPlain && themes.values.every((theme) => theme == null)) {
      return forumAppearance;
    }
    // A mode without its own choice keeps the forum's palette for that mode,
    // its colours exactly as published: only a theme tints.
    ResolvedSitePalette? palette(Brightness brightness) {
      final forum = forumAppearance?.paletteForBrightness(brightness);
      final theme = themes[brightness];
      if (theme == null) {
        return effects.isPlain ? forum : forum?.withEffects(effects);
      }
      return theme
          .copyWith(
            background:
                draft != null || preferences.source == ForumThemeSource.custom
                ? theme.background ?? effects
                : effects,
          )
          .resolve(
            brightness,
            forumPalette:
                forum ?? forumAppearance?.base ?? forumAppearance?.alternate,
          );
    }

    return SiteAppearance(
      base: palette(Brightness.light),
      alternate: palette(Brightness.dark),
    );
  }

  Future<void> setThemes(String siteUrl, ForumThemePreferences value) {
    final site = requireStoredForumBase(siteUrl);
    if (isDisposed) return Future.value();
    if (themesFor(site) == value) {
      return _themeWrites[site]?.completion.future ?? Future.value();
    }
    final existing = _themeWrites[site];
    final write = existing ?? _Write(themesFor(site));
    _themeWrites[site] = write;
    _themeEdits[site] = (before: write.saved, after: value);
    write.pending = value;
    _themes.remember(site, value);
    notifySafely();
    if (existing == null) {
      unawaited(
        _persist(
          write,
          (value) => store.writeThemes(site, value, previous: write.saved),
          revert: (saved) => _themes.remember(site, saved),
          done: () {
            _themeWrites.remove(site);
            _themeEdits.remove(site);
            if (!isDisposed) notifySafely();
          },
        ),
      );
    }
    return write.completion.future;
  }

  /// Loads shared fonts, effects, and every connected forum's saved themes.
  /// Legacy per-forum documents are migrated without changing selections.
  Future<void> loadShared(Iterable<String> siteUrls) async {
    if (isDisposed) return;
    final sites = [for (final url in siteUrls) requireStoredForumBase(url)];
    await _shared.ensure(_everyForum, () => store.loadAppearance(sites: sites));
    for (final site in sites) {
      if (isDisposed) return;
      await _themes.ensure(site, () => store.loadThemes(site));
    }
    if (!isDisposed) notifySafely();
  }

  Future<void> setShared(SharedAppearance value) {
    if (isDisposed) return Future.value();
    if (_shared.peek(_everyForum) == value) {
      return _sharedWrite?.completion.future ?? Future.value();
    }
    final existing = _sharedWrite;
    final write = existing ?? _Write(shared);
    _sharedWrite = write;
    write.pending = value;
    _shared.remember(_everyForum, value);
    notifySafely();
    if (existing == null) {
      unawaited(
        _persist(
          write,
          store.writeAppearance,
          revert: (saved) => _shared.remember(_everyForum, saved),
          done: () => _sharedWrite = null,
        ),
      );
    }
    return write.completion.future;
  }

  Future<void> _persist<T extends Object>(
    _Write<T> write,
    Future<void> Function(T value) save, {
    required void Function(T saved) revert,
    required void Function() done,
  }) async {
    while (write.pending != null) {
      final value = write.pending!;
      write.pending = null;
      try {
        await save(value);
        write.saved = value;
      } catch (error, stack) {
        // A newer live edit supersedes an obsolete failed write. Try that
        // latest value before reporting a failure or reverting the app.
        if (write.pending != null) continue;
        done();
        if (!isDisposed) {
          revert(write.saved);
          notifySafely();
        }
        write.completion.completeError(error, stack);
        return;
      }
    }
    done();
    write.completion.complete();
  }

  /// Shows [siteUrl]'s colours in each of [siteUrls], loading their selections
  /// first. The shared theme library is unchanged.
  Future<void> useThemesIn(String siteUrl, Iterable<String> siteUrls) {
    final source = requireStoredForumBase(siteUrl);
    final chosen = themesFor(source);
    return Future.wait([
      for (final site in {
        for (final url in siteUrls) requireStoredForumBase(url),
      }.where((site) => site != source))
        _themeImports.run(
          owner: this,
          key: site,
          operation: () async {
            await _themes.ensure(site, () => store.loadThemes(site));
            if (!isDisposed) {
              await setThemes(site, themesFor(site).showing(chosen));
            }
          },
        ),
    ]);
  }

  /// Loads the shared library before importing. Serial imports also retain
  /// simultaneous shares.
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

  /// Drops what was read or chosen for forums that left the rail for good, so
  /// one added again loads as new. Their stored themes go with the rest of
  /// their preferences; see [forgetSitePreferences].
  void forgetSites(ForgottenSites sites) {
    _themeModes.forgetWhere(sites.includes);
    _themes.forgetWhere(sites.includes);
    unawaited(
      store.forgetThemes(sites).catchError((Object _) {
        // Retain the library if persistence is temporarily unavailable.
      }),
    );
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

typedef _AppearancePreview = ({
  Object owner,
  Brightness? brightness,
  ForumTheme? draft,
});

final class _Write<T extends Object> {
  _Write(this.saved);
  T saved;
  T? pending;
  final completion = Completer<void>();
}
