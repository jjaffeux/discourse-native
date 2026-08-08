import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../models/topic_link.dart';
import '../../inline.dart';

/// An inline onebox pointing at a topic — the shape Discourse's
/// `InlineOneboxer` writes for internal links, with the topic's title (and
/// the post number, when the link names one) in place of the URL.
///
/// The chip opens the link through the usual route, which lands a topic on a
/// site in the rail on that site's view of it.
class DiscourseTopicInlineOnebox {
  static bool matches(dom.Element anchor) =>
      TopicLink.parse(anchor.attributes['href'] ?? '') != null;

  static Widget from(dom.Element anchor, {String? siteUrl}) => InlineOneboxChip(
    href: anchor.attributes['href']!,
    siteUrl: siteUrl,
    child: TextSpan(text: anchor.text.trim()),
  );
}
