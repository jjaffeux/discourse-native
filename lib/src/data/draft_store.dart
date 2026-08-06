import 'package:shared_preferences/shared_preferences.dart';

/// The copy of a draft the site has not got yet.
///
/// Server drafts are for carrying a reply to another device. This is the other
/// half: what makes quitting and reopening safe when the site could not be
/// reached, which is exactly when losing what someone wrote hurts most.
///
/// It is written on every autosave and deleted the moment the server has the
/// same text, so its presence means one thing only — there is writing here the
/// site has not seen. That is what lets a restore prefer it without needing a
/// timestamp to compare.
///
/// Every operation swallows its failures. A draft mirror that cannot be
/// written is a worse draft mirror; a draft mirror that throws into the
/// composer is a broken composer.
class DraftStore {
  static String _key(String siteUrl, String draftKey) =>
      'discourse_native.draft::$siteUrl::$draftKey';

  Future<String?> read(String siteUrl, String draftKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(siteUrl, draftKey));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String siteUrl, String draftKey, String data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(siteUrl, draftKey), data);
    } catch (_) {
      // Nothing to do about it, and nothing that should reach the user.
    }
  }

  Future<void> clear(String siteUrl, String draftKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(siteUrl, draftKey));
    } catch (_) {
      // As above.
    }
  }
}
