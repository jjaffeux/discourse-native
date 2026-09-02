import 'package:flutter/foundation.dart';
import 'discourse_instance.dart';

@immutable
class TopicLink {
  const TopicLink({
    required this.uri,
    required this.topicId,
    required this.slug,
    this.postNumber,
  });

  final Uri uri;

  final int topicId;

  final String slug;

  final int? postNumber;

  static const int maximumUrlLength = 2048;

  /// Reads a topic link. A forum served from a subfolder writes its links
  /// under that path; [siteUrl] names the forum so the base is required and
  /// then skipped, and a link under some other path is not a topic of it.
  static TopicLink? parse(String url, {String? siteUrl}) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;

    final segments = siteUrl == null
        ? uri.pathSegments
        : DiscourseInstance.pathSegmentsWithin(siteUrl, uri);
    if (segments == null || segments.length < 2 || segments.first != 't') {
      return null;
    }

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

  String get placeholderTitle {
    final words = slug.replaceAll('-', ' ').trim();
    if (words.isEmpty) return 'Topic';
    return words.replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
  }
}
