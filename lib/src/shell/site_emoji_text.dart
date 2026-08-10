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
    this.trailing = const [],
  });

  SiteEmojiText.plain(
    String text, {
    super.key,
    required this.siteUrl,
    this.maxLines,
    this.overflow,
    this.style,
    this.textAlign,
    this.trailing = const [],
  }) : runs = [SiteEmojiTextRun(text)];

  final List<SiteEmojiTextRun> runs;
  final String siteUrl;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Widgets that participate in the final line of text.
  ///
  /// Topic rows use this for unread state, where placing the marker beside the
  /// paragraph would center it against all of a wrapped title instead of
  /// leaving it immediately after the title's final word.
  final List<Widget> trailing;

  static final RegExp _shortcode = RegExp(r':([a-z0-9_+-]+(?::t[1-6])?):');

  @override
  Widget build(BuildContext context) {
    final text = runs.map((run) => run.text).join();
    final matches = _shortcode.allMatches(text).toList();
    if (matches.isEmpty &&
        runs.length == 1 &&
        runs.single.style == null &&
        trailing.isEmpty) {
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
    spans.addAll(
      trailing.map(
        (widget) => _TrailingWidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: widget,
        ),
      ),
    );

    final richText = Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
      style: style,
      textAlign: textAlign,
    );

    // A trailing WidgetSpan carries meaningful semantics of its own. Keep
    // those descendants exposed; ordinary emoji-only prose still gets one
    // clean label rather than being announced as several fragments.
    if (trailing.isNotEmpty) return richText;

    // The artwork is decorative to assistive technology; the original text is
    // the clearest single reading of the row.
    return Semantics(
      label: text,
      child: ExcludeSemantics(child: richText),
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

/// An inline widget that is absent from the title's plain-text value.
///
/// Flutter normally flattens every [WidgetSpan] to an object-replacement
/// character. These widgets are state appended to the title rather than title
/// content, so omitting that character preserves text lookup, selection and
/// copying as the topic title alone.
class _TrailingWidgetSpan extends WidgetSpan {
  const _TrailingWidgetSpan({required super.child, super.alignment});

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) {}
}
