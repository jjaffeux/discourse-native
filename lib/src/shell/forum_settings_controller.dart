import 'dart:ui';

import '../data/forum_settings_store.dart';
import '../data/preference_snapshots.dart';
import '../data/stored_forum_base.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/app_settings.dart';
import '../models/forum_theme_preferences.dart';
import '../models/site_appearance.dart';

final class ForumSettingsController extends FrameSafeNotifier {
  ForumSettingsController({required this.store});

  final ForumSettingsStore store;
  final _themeModes = PreferenceSnapshots<String, AppThemeMode>();

  final _themes = PreferenceSnapshots<String, ForumThemePreferences>();

  ForumThemePreferences themesFor(String siteUrl) =>
      _themes.peek(requireStoredForumBase(siteUrl)) ??
      ForumThemePreferences.defaults;

  SiteAppearance? appearanceFor(
    String siteUrl,
    SiteAppearance? forumAppearance,
  ) {
    final selected = themesFor(siteUrl).selectedTheme;
    if (selected == null) return forumAppearance;
    ResolvedSitePalette palette(Brightness brightness) => selected.resolve(
      brightness,
      forumPalette:
          forumAppearance?.paletteForBrightness(brightness) ??
          forumAppearance?.base ??
          forumAppearance?.alternate,
    );
    return SiteAppearance(
      base: palette(Brightness.light),
      alternate: palette(Brightness.dark),
    );
  }

  Future<void> setThemes(String siteUrl, ForumThemePreferences value) async {
    final site = requireStoredForumBase(siteUrl);
    if (isDisposed || _themes.peek(site) == value) return;
    await store.writeThemes(site, value);
    if (isDisposed) return;
    _themes.remember(site, value);
    notifySafely();
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
