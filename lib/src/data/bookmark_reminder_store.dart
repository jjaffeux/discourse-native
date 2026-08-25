import 'package:shared_preferences/shared_preferences.dart';

final class BookmarkReminderStore {
  const BookmarkReminderStore();

  String _key(String siteUrl, String username) =>
      'bookmark.last-custom.${Uri.encodeComponent(siteUrl)}.'
      '${Uri.encodeComponent(username.toLowerCase())}';

  Future<DateTime?> read(String siteUrl, String username) async {
    final value = (await SharedPreferences.getInstance()).getString(
      _key(siteUrl, username),
    );
    return DateTime.tryParse(value ?? '')?.toUtc();
  }

  Future<void> write(String siteUrl, String username, DateTime value) async {
    await (await SharedPreferences.getInstance()).setString(
      _key(siteUrl, username),
      value.toUtc().toIso8601String(),
    );
  }
}
