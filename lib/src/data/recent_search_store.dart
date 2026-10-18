import 'site_preference_keys.dart';

/// Local removal complements the server's whole-history reset endpoint.
/// The key is account-scoped; credentials and session tokens are never saved.
class RecentSearchStore {
  const RecentSearchStore();

  static const keys = SitePreferenceKey(
    'search.removed',
    tail: SitePreferenceTail.name,
    retirement: SitePreferenceRetirement.managed,
  );
  static const preferences = OwnedSitePreferences(
    id: 'search.removed',
    scope: SitePreferenceScope.account,
    value: SitePreferenceValue.stringList,
    operation: 'recentSearch',
    legacy: keys,
  );

  Future<Set<String>> read(String site, String username) async =>
      (await preferences.read(
        SitePreferenceIdentity.account(site, username),
      ))?.toSet() ??
      {};

  Future<void> write(String site, String username, Set<String> terms) =>
      preferences.write(
        SitePreferenceIdentity.account(site, username),
        terms.take(100).toList(),
      );
}
