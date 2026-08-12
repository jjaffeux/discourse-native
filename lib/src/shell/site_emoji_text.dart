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
    final matches = _shortcode.allMatches(text).iterator;
    final hasMatch = matches.moveNext();
    if (!hasMatch &&
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
    final cursor = _StyledRunCursor(runs);

    if (hasMatch) {
      do {
        final match = matches.current;
        cursor.appendText(spans, match.start);
        final name = match.group(1)!;
        final emojiStyle = effectiveStyle.merge(cursor.style);
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
        cursor.skipTo(match.end);
      } while (matches.moveNext());
    }
    cursor.appendText(spans, text.length);
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
}

/// Walks styled runs alongside the shortcode matcher without rescanning runs.
///
/// Search excerpts can split almost every word into a separate run. Advancing
/// monotonically keeps a row with many emoji linear in its text and run count,
/// while still allowing one shortcode to cross any number of style boundaries.
class _StyledRunCursor {
  _StyledRunCursor(this.runs);

  final List<SiteEmojiTextRun> runs;

  int _runIndex = 0;
  int _runOffset = 0;
  int _textOffset = 0;

  TextStyle? get style {
    _skipEmptyRuns();
    return _runIndex < runs.length ? runs[_runIndex].style : null;
  }

  void appendText(List<InlineSpan> spans, int end) =>
      _advanceTo(end, spans: spans);

  void skipTo(int end) => _advanceTo(end);

  void _advanceTo(int end, {List<InlineSpan>? spans}) {
    assert(end >= _textOffset);
    while (_textOffset < end) {
      _skipEmptyRuns();
      if (_runIndex >= runs.length) return;

      final run = runs[_runIndex];
      final available = run.text.length - _runOffset;
      final remaining = end - _textOffset;
      final length = remaining < available ? remaining : available;
      if (spans != null) {
        spans.add(
          TextSpan(
            text: run.text.substring(_runOffset, _runOffset + length),
            style: run.style,
          ),
        );
      }

      _runOffset += length;
      _textOffset += length;
      if (_runOffset == run.text.length) {
        _runIndex++;
        _runOffset = 0;
      }
    }
  }

  void _skipEmptyRuns() {
    while (_runIndex < runs.length && runs[_runIndex].text.isEmpty) {
      _runIndex++;
      _runOffset = 0;
    }
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
