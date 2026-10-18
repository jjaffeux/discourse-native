/// Explicit ownership for adapters that do not store individual site keys.
/// Individual site preferences declare `SitePreferenceKey` beside their writer.
final class PreferenceStorage {
  const PreferenceStorage.device(this.contract);
  const PreferenceStorage.document(this.contract);
  const PreferenceStorage.adapter(this.contract);

  final String contract;
}
