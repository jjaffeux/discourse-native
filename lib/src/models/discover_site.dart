import '../data/http_transport.dart';
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
      logoUrl: _logoUrl(json['discover_entry_logo_url']),
    );
  }

  static String? _logoUrl(Object? value) {
    if (value is! String) return null;
    try {
      return requireSafeHttpUrl(Uri.parse(value)).toString();
    } on FormatException {
      return null;
    } on UnsafeHttpTransportException {
      return null;
    }
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
    return sites
        .where((site) {
          final key = identity(site.url);
          return key != null && seen.add(key);
        })
        .take(10)
        .toList(growable: false);
  }
}
