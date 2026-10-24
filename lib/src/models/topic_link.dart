import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../foundation/uri_path.dart';
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

  static const int lastPostNumber = 99_999_999;

  /// Reads a topic link. A forum served from a subfolder writes its links
  /// under that path; [siteUrl] names the forum so the base is required and
  /// then skipped, and a link under some other path is not a topic of it.
  static TopicLink? parse(String url, {String? siteUrl}) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;

    var segments = siteUrl == null
        ? tryUriPathSegments(uri)
        : DiscourseInstance.pathSegmentsWithin(siteUrl, uri);
    if (segments != null && segments.isNotEmpty && segments.last.isEmpty) {
      segments = segments.sublist(0, segments.length - 1);
    }
    if (segments == null || segments.length < 2 || segments.first != 't') {
      return null;
    }

    // `/t/id/post` and `/t/slug/id` have the same length, so the second
    // segment tells them apart: core never writes an all-digit slug, Rails
    // routes such a link as `/t/id/post`, and the web client redirects an
    // all-digit "slug" to the topic it names. Core writes the slugless shape
    // when it titles a quote of a topic anonymous users cannot see.
    final slugless = segments.length == 2 || _allDigits.hasMatch(segments[1]);
    final idIndex = slugless ? 1 : 2;
    final id = int.tryParse(segments[idIndex]);
    if (id == null || id <= 0) return null;

    final postIndex = idIndex + 1;
    if (segments.length > postIndex + 1) return null;
    final suffix = segments.length > postIndex ? segments[postIndex] : null;
    final postNumber = suffix == 'last'
        ? lastPostNumber
        : suffix != null && _allDigits.hasMatch(suffix)
        ? int.tryParse(suffix)
        : null;
    if (suffix != null && (postNumber == null || postNumber <= 0)) return null;
    return TopicLink(
      uri: uri,
      topicId: id,
      slug: slugless ? '' : segments[1],
      postNumber: postNumber,
    );
  }

  static final _allDigits = RegExp(r'^[0-9]+$');

  String get placeholderTitle {
    final words = slug.replaceAll('-', ' ').trim();
    if (words.isEmpty) return appL10n.topic;
    return words.replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
  }
}
