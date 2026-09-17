import '../data/forum_settings_store.dart';
import '../data/preference_snapshots.dart';
import '../data/stored_forum_base.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/app_settings.dart';

final class ForumSettingsController extends FrameSafeNotifier {
  ForumSettingsController({required this.store});

  final ForumSettingsStore store;
  final _themeModes = PreferenceSnapshots<String, AppThemeMode>();

  AppThemeMode themeModeFor(String siteUrl) =>
      _themeModes.peek(requireStoredForumBase(siteUrl)) ?? AppThemeMode.system;

  Future<void> load(
    String siteUrl, {
    AppThemeMode initialMode = AppThemeMode.system,
  }) async {
    if (isDisposed) return;
    final site = requireStoredForumBase(siteUrl);
    await _themeModes.ensure(
      site,
      () => store.loadThemeMode(site, initialMode: initialMode),
    );
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
