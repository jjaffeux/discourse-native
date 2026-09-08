import '../foundation/uri_path.dart';

enum ListKind { category, tag }

class ListLink {
  const ListLink({
    required this.uri,
    required this.kind,
    required this.slug,
    required this.feedPath,
    this.id,
  });

  final Uri uri;

  final ListKind kind;

  final String slug;

  final String feedPath;

  final int? id;

  static const int maximumUrlLength = 2048;

  static ListLink? parse(String url) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;

    // A trailing slash leaves an empty last segment, which would otherwise
    // read as "not an id" and refuse a perfectly ordinary link.
    final decoded = tryUriPathSegments(uri);
    if (decoded == null) return null;
    final segments = [...decoded]..removeWhere((segment) => segment.isEmpty);
    if (segments.length < 2) return null;

    final kind = switch (segments.first) {
      'c' => ListKind.category,
      'tag' => ListKind.tag,
      _ => null,
    };
    if (kind == null) return null;

    try {
      final _ = uri.queryParametersAll;
    } on FormatException {
      return null;
    }

    // Rebuilt from the segments rather than taken from `uri.path`, so a
    // trailing slash or a query string cannot end up inside the filename.
    // Re-encode each segment so decoded punctuation remains part of its name.
    final path = Uri(
      pathSegments: [
        '',
        ...segments.take(segments.length - 1),
        '${segments.last}.json',
      ],
      query: uri.hasQuery ? uri.query : null,
    ).toString();
    final rest = segments.sublist(1);

    // Anything past the id is a filter — `/l/top`, `/none`, `/subcategories` —
    // and none of them are this list.
    final id = int.tryParse(rest.last);
    if (id == null) {
      // Discourse resolves single-slug category and tag links without an ID.
      if (rest.length != 1) return null;
      return ListLink(uri: uri, kind: kind, slug: rest.first, feedPath: path);
    }
    if (id <= 0) return null;

    // `/c/12` and `/tag/12` name a record without naming it.
    final slug = rest.length >= 2 ? rest[rest.length - 2] : '';

    return ListLink(uri: uri, kind: kind, slug: slug, feedPath: path, id: id);
  }

  String get placeholderTitle {
    final words = slug.replaceAll('-', ' ').trim();
    if (words.isEmpty) return kind == ListKind.category ? 'Category' : 'Tag';
    return words.replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
  }
}
