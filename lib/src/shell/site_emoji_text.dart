import 'package:flutter/material.dart';

import 'emoji.dart';
import 'site_emoji_image.dart';

/// One styled run in prose that may contain Discourse emoji shortcodes.
@immutable
class SiteEmojiTextRun {
  const SiteEmojiTextRun(this.text, {this.style});

  final String text;
  final TextStyle? style;
}

/// Native text with `:shortcodes:` drawn using one site's emoji artwork.
///
/// Runs are joined before shortcodes are found so server formatting, such as a
/// search highlight around the emoji name, cannot split a shortcode into
/// pieces that remain visible as punctuation.
class SiteEmojiText extends StatelessWidget {
  const SiteEmojiText(
    this.runs, {
    super.key,
    required this.siteUrl,
    this.maxLines,
    this.overflow,
    this.style,
    this.textAlign,
  });

  SiteEmojiText.plain(
    String text, {
    super.key,
    required this.siteUrl,
    this.maxLines,
    this.overflow,
    this.style,
    this.textAlign,
  }) : runs = [SiteEmojiTextRun(text)];

  final List<SiteEmojiTextRun> runs;
  final String siteUrl;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextStyle? style;
  final TextAlign? textAlign;

  static final RegExp _shortcode = RegExp(r':([a-z0-9_+-]+(?::t[1-6])?):');

  @override
  Widget build(BuildContext context) {
    final text = runs.map((run) => run.text).join();
    final matches = _shortcode.allMatches(text).toList();
    if (matches.isEmpty && runs.length == 1 && runs.single.style == null) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        style: style,
        textAlign: textAlign,
      );
    }

    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in matches) {
      _appendText(spans, cursor, match.start);
      final name = match.group(1)!;
      final emojiStyle = effectiveStyle.merge(_styleAt(match.start));
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SiteEmojiImage(
            siteUrl: siteUrl,
            name: name,
            size: (emojiStyle.fontSize ?? 14) * emojiScale,
            alt: match.group(0)!,
            style: emojiStyle,
          ),
        ),
      );
      cursor = match.end;
    }
    _appendText(spans, cursor, text.length);

    // The artwork is decorative to assistive technology; the original text is
    // the clearest single reading of the row.
    return Semantics(
      label: text,
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

  void _appendText(List<InlineSpan> spans, int start, int end) {
    if (start >= end) return;
    var runStart = 0;
    for (final run in runs) {
      final runEnd = runStart + run.text.length;
      final sliceStart = start.clamp(runStart, runEnd);
      final sliceEnd = end.clamp(runStart, runEnd);
      if (sliceStart < sliceEnd) {
        spans.add(
          TextSpan(
            text: run.text.substring(
              sliceStart - runStart,
              sliceEnd - runStart,
            ),
            style: run.style,
          ),
        );
      }
      runStart = runEnd;
      if (runStart >= end) return;
    }
  }

  TextStyle? _styleAt(int offset) {
    var runEnd = 0;
    for (final run in runs) {
      runEnd += run.text.length;
      if (offset < runEnd) return run.style;
    }
    return null;
  }
}
