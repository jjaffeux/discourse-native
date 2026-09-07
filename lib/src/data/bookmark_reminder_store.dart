import 'package:shared_preferences/shared_preferences.dart';

import 'store_diagnostics.dart';

final class BookmarkReminderStore {
  const BookmarkReminderStore();

  String _key(String siteUrl, String username) =>
      'bookmark.last-custom.${Uri.encodeComponent(siteUrl)}.'
      '${Uri.encodeComponent(username.toLowerCase())}';

  Future<DateTime?> read(String siteUrl, String username) async {
    try {
      final value = (await SharedPreferences.getInstance()).getString(
        _key(siteUrl, username),
      );
      return DateTime.tryParse(value ?? '')?.toUtc();
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'bookmarkReminders.read');
      return null;
    }
  }

  Future<void> write(String siteUrl, String username, DateTime value) async {
    try {
      final saved = await (await SharedPreferences.getInstance()).setString(
        _key(siteUrl, username),
        value.toUtc().toIso8601String(),
      );
      if (!saved) {
        throw StateError(
          'Could not persist the last custom bookmark reminder.',
        );
      }
    } catch (error, stackTrace) {
      reportStorageFailure(error, stackTrace, 'bookmarkReminders.write');
    }
  }
}
