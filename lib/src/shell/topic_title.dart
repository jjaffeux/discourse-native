import 'package:flutter/material.dart';

import 'site_emoji_text.dart';

/// A topic title with Discourse emoji shortcodes drawn as site emoji.
///
/// Topic payloads deliberately use the plain `title` rather than the HTML
/// `fancy_title`, so entities remain text a native widget can understand. The
/// plain title keeps emoji as `:shortcodes:`, though, and those need the same
/// site-aware artwork resolution as emoji in cooked posts.
class TopicTitle extends StatelessWidget {
  const TopicTitle(
    this.title, {
    super.key,
    required this.siteUrl,
    this.maxLines,
    this.overflow,
    this.style,
    this.textAlign,
  });

  final String title;
  final String siteUrl;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => SiteEmojiText.plain(
    title,
    siteUrl: siteUrl,
    maxLines: maxLines,
    overflow: overflow,
    style: style,
    textAlign: textAlign,
  );
}
