import 'package:flutter/material.dart';

import 'emoji.dart';
import 'site_emoji_image.dart';

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

  static final RegExp _shortcode = RegExp(r':([a-z0-9_+-]+(?::t[1-6])?):');

  @override
  Widget build(BuildContext context) {
    final matches = _shortcode.allMatches(title).toList();
    if (matches.isEmpty) {
      return Text(
        title,
        maxLines: maxLines,
        overflow: overflow,
        style: style,
        textAlign: textAlign,
      );
    }

    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final size = (effectiveStyle.fontSize ?? 14) * emojiScale;
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: title.substring(cursor, match.start)));
      }
      final name = match.group(1)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SiteEmojiImage(
            siteUrl: siteUrl,
            name: name,
            size: size,
            alt: match.group(0)!,
            style: effectiveStyle,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < title.length) {
      spans.add(TextSpan(text: title.substring(cursor)));
    }

    // The artwork is decorative to assistive technology; the original title
    // remains the clearest single reading of the row.
    return Semantics(
      label: title,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(children: spans),
          maxLines: maxLines,
          overflow: overflow,
          style: style,
          textAlign: textAlign,
        ),
      ),
    );
  }
}
