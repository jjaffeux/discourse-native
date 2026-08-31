/// Leases are additive. Releasing one lease never affects another plugin (or
/// another lease from the same plugin) retaining the same site.
abstract interface class PluginBackgroundRetentionLease {
  String get siteUrl;

  bool get isReleased;

  void release();
}

/// The runtime gives every consuming module a private, owner-scoped wrapper.
/// It can acquire and release only its own leases.
abstract interface class PluginBackgroundRetentionHost {
  PluginBackgroundRetentionLease retain(String siteUrl);
}
