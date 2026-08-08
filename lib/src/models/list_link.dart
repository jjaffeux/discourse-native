/// A link to a filtered topic list — a category or a tag.
///
/// The sibling of [TopicLink], and shaped like it for the same reason: the
/// shell needs to know whose site a link belongs to before it can decide what
/// to do with it, so the [Uri] is kept alongside what was parsed out of it.
///
/// Hashtags are what produce these. Discourse cooks `#support` as an anchor to
/// `/c/support/5` and `#bug` as one to `/tag/bug/12`, and those are the only
/// two shapes here — everything under them (`/c/x/5/l/top`, `/c/x/5/none`) is a
/// filter this app has no screen for and belongs in the browser.
library;

import 'topic_link.dart';

enum ListKind { category, tag }

class ListLink {
  const ListLink({
    required this.uri,
    required this.kind,
    required this.slug,
    required this.feedPath,
    this.id,
  });

  /// The link itself, so the caller can work out whose site it is.
  final Uri uri;

  final ListKind kind;

  /// The last slug segment — `child` of `/c/parent/child/12`. What the route is
  /// titled with until the real name is found.
  final String slug;

  /// Where the list's JSON lives, site-relative.
  ///
  /// The href with `.json` appended, and deliberately not rebuilt from [slug]
  /// and [id]: a category's slug path is arbitrarily deep, and a tag with no
  /// slug is written `/tag/12-tag/12`. Reassembling either is how a link that
  /// worked in the browser stops working here.
  final String feedPath;

  /// The record id, where the URL carries one. Absent on the legacy
  /// `/tag/{name}` form, which is still what older posts contain.
  final int? id;

  /// The list [url] points at, or null for anything else.
  static ListLink? parse(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // A trailing slash leaves an empty last segment, which would otherwise
    // read as "not an id" and refuse a perfectly ordinary link.
    final segments = [...uri.pathSegments]
      ..removeWhere((segment) => segment.isEmpty);
    if (segments.length < 2) return null;

    final kind = switch (segments.first) {
      'c' => ListKind.category,
      'tag' => ListKind.tag,
      _ => null,
    };
    if (kind == null) return null;

    // Rebuilt from the segments rather than taken from `uri.path`, so a
    // trailing slash or a query string cannot end up inside the filename.
    final path = '/${segments.join('/')}.json';
    final rest = segments.sublist(1);

    // Anything past the id is a filter — `/l/top`, `/none`, `/subcategories` —
    // and none of them are this list.
    final id = int.tryParse(rest.last);
    if (id == null) {
      // The only idless form Discourse still writes is `/tag/{name}`.
      if (kind != ListKind.tag || rest.length != 1) return null;
      return ListLink(uri: uri, kind: kind, slug: rest.first, feedPath: path);
    }
    if (id <= 0) return null;

    // `/c/12` and `/tag/12` name a record without naming it.
    final slug = rest.length >= 2 ? rest[rest.length - 2] : '';

    return ListLink(uri: uri, kind: kind, slug: slug, feedPath: path, id: id);
  }

  /// What to call the list until the site says otherwise.
  ///
  /// The same bargain [TopicLink.placeholderTitle] makes: a slug is a name with
  /// the punctuation knocked out of it, which reads far better in the header
  /// than a placeholder would.
  String get placeholderTitle {
    final words = slug.replaceAll('-', ' ').trim();
    if (words.isEmpty) return kind == ListKind.category ? 'Category' : 'Tag';
    return words.replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
  }
}
