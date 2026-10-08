import 'package:shared_preferences/shared_preferences.dart';

/// Local removal complements the server's whole-history reset endpoint.
/// The key is account-scoped; credentials and session tokens are never saved.
class RecentSearchStore {
  const RecentSearchStore();
  String _key(String site, String username) =>
      'search.removed.${Uri.encodeComponent(site)}.${Uri.encodeComponent(username)}';

  Future<Set<String>> read(String site, String username) async =>
      (await SharedPreferences.getInstance())
          .getStringList(_key(site, username))
          ?.toSet() ??
      {};

  Future<void> write(String site, String username, Set<String> terms) async {
    final preferences = await SharedPreferences.getInstance();
    if (terms.isEmpty) {
      await preferences.remove(_key(site, username));
    } else {
      await preferences.setStringList(
        _key(site, username),
        terms.take(100).toList(),
      );
    }
  }
}
