import '../data/stored_forum_base.dart';
import 'json.dart';

final class DiscoverSite {
  const DiscoverSite({required this.url, required this.title, this.logoUrl});

  final String url;
  final String title;
  final String? logoUrl;

  static DiscoverSite? tryParse(Map<String, dynamic> json) {
    final url = tryStoredForumBase(json['featured_link']);
    final title = jsonTitle(json['title'], json['fancy_title']).trim();
    if (url == null || title.isEmpty) return null;
    return DiscoverSite(
      url: url,
      title: title,
      logoUrl: tryStoredForumBase(json['discover_entry_logo_url']),
    );
  }

  String get address => identity(url)!;

  /// Trailing slashes do not distinguish forums; subfolders and custom ports do.
  static String? identity(String url) {
    final base = tryStoredForumBase(url);
    if (base == null) return null;
    final uri = Uri.parse(base);
    return '${uri.authority}${uri.path}';
  }

  static List<DiscoverSite> suggestions(
    Iterable<DiscoverSite> sites,
    Iterable<String> addedUrls,
  ) {
    final seen = addedUrls.map(identity).whereType<String>().toSet();
    return [
      for (final site in sites)
        if (identity(site.url) case final String key)
          if (seen.add(key)) site,
    ].take(10).toList(growable: false);
  }
}
