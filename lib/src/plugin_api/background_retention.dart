/// A revocable claim that keeps one configured site's live connection active
/// while the application is backgrounded.
///
/// Leases are additive. Releasing one lease never affects another plugin (or
/// another lease from the same plugin) retaining the same site.
abstract interface class PluginBackgroundRetentionLease {
  String get siteUrl;

  bool get isReleased;

  void release();
}

/// Least-privilege authority for a plugin to retain background connectivity.
///
/// The runtime gives every consuming module a private, owner-scoped wrapper.
/// It can acquire and release only its own leases and receives no polling,
/// tracker, or other plugin's claim controls.
abstract interface class PluginBackgroundRetentionHost {
  PluginBackgroundRetentionLease retain(String siteUrl);
}
