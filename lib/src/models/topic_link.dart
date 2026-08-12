import 'package:flutter/foundation.dart';

/// A URL that points at a topic on some Discourse site.
///
/// Which site is left to the caller: the same link means "open this here" or
/// "switch sites and open it there" depending on what the user has connected.
@immutable
class TopicLink {
  const TopicLink({
    required this.uri,
    required this.topicId,
    required this.slug,
    this.postNumber,
  });

  /// The link itself, so the caller can work out whose site it is.
  final Uri uri;

  final int topicId;

  /// Empty for the slugless permalinks Discourse also answers to.
  final String slug;

  /// The numbered post named by a slugged topic URL, if there is one.
  final int? postNumber;

  /// A generous boundary for server-authored links before URI parsing.
  /// Ordinary topic links are tiny; sharing the 2 KiB navigation boundary
  /// used for feed cursors prevents malformed cooked HTML from allocating an
  /// arbitrarily large URI and placeholder slug.
  static const int maximumUrlLength = 2048;

  /// The topic [url] points at, or null when it points at anything else.
  ///
  /// Discourse writes topic URLs as `/t/slug/12`, with a post number appended
  /// when the link names a post — `/t/slug/12/34` — and the same for the
  /// suffixed routes such as `/t/slug/12/last`. Permalinks drop the slug and
  /// leave `/t/12`.
  static TopicLink? parse(String url) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;

    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first != 't') return null;

    // Which segment holds the id is what tells the two shapes apart. A link
    // with three segments is read as `/t/slug/id` rather than `/t/id/post`,
    // which is how Discourse's own router resolves the ambiguity.
    final slugged = segments.length >= 3;
    final id = int.tryParse(slugged ? segments[2] : segments[1]);
    if (id == null || id <= 0) return null;

    final postNumber = slugged && segments.length >= 4
        ? int.tryParse(segments[3])
        : null;
    return TopicLink(
      uri: uri,
      topicId: id,
      slug: slugged ? segments[1] : '',
      postNumber: postNumber != null && postNumber > 0 ? postNumber : null,
    );
  }

  /// What to call the topic until the real title arrives with it.
  ///
  /// A slug is a title with the punctuation knocked out of it, which reads
  /// far better in the header than a placeholder would.
  String get placeholderTitle {
    final words = slug.replaceAll('-', ' ').trim();
    if (words.isEmpty) return 'Topic';
    return words.replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
  }
}
