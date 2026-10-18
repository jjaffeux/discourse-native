import 'site_preference_keys.dart';

final class BookmarkReminderStore {
  const BookmarkReminderStore();

  static const keys = SitePreferenceKey(
    'bookmark.last-custom',
    tail: SitePreferenceTail.name,
    retirement: SitePreferenceRetirement.managed,
  );
  static const preferences = OwnedSitePreferences(
    id: 'bookmark.last-custom',
    scope: SitePreferenceScope.account,
    value: SitePreferenceValue.string,
    operation: 'bookmarkReminders',
    legacy: keys,
  );

  Future<DateTime?> read(String siteUrl, String username) async {
    final value = await preferences.read(
      SitePreferenceIdentity.account(siteUrl, username.toLowerCase()),
    );
    return DateTime.tryParse(value ?? '')?.toUtc();
  }

  Future<void> write(String siteUrl, String username, DateTime value) =>
      preferences.write(
        SitePreferenceIdentity.account(siteUrl, username.toLowerCase()),
        value.toUtc().toIso8601String(),
      );
}
