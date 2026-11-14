import 'dart:async';

import 'package:flutter/material.dart';

import '../models/site_emoji.dart';
import '../theme/discourse_typography.dart';
import 'emoji.dart';
import 'search_words.dart';
import 'site_emoji_image.dart';
import 'site_presentation_scope.dart';

@immutable
class SiteEmojiTextRun {
  const SiteEmojiTextRun(this.text, {this.style, this.literal = false});

  final String text;
  final TextStyle? style;
  final bool literal;
}

class SiteEmojiText extends StatelessWidget {
  const SiteEmojiText(
    this.runs, {
    super.key,
    required this.siteUrl,
    this.maxLines,
    this.overflow,
    this.style,
    this.textAlign,
    this.resolveUnicode = false,
    this.ellipsisAtWordBoundary = false,
    this.leading = const [],
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
    this.resolveUnicode = false,
    this.ellipsisAtWordBoundary = false,
    this.leading = const [],
    this.trailing = const [],
  }) : runs = [SiteEmojiTextRun(text)];

  final List<SiteEmojiTextRun> runs;
  final String siteUrl;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool resolveUnicode;
  final bool ellipsisAtWordBoundary;

  /// Inline markers participate in text flow so later lines use the full width.
  final List<Widget> leading;
  final List<Widget> trailing;

  static final shortcodePattern = siteEmojiShortcodePattern;
  static Iterable<RegExpMatch> shortcodeMatches(String text) =>
      siteEmojiShortcodeMatches(text);

  @override
  Widget build(BuildContext context) {
    final text = runs.map((run) => run.text).join();
    var offset = 0;
    final literalRanges = <TextRange>[];
    for (final run in runs) {
      if (run.literal) {
        literalRanges.add(
          TextRange(start: offset, end: offset + run.text.length),
        );
      }
      offset += run.text.length;
    }
    final matches =
        [
          for (final match in shortcodeMatches(text))
            (start: match.start, end: match.end, name: match.group(1)!),
          if (resolveUnicode) ...siteUnicodeEmojiMatches(text),
        ]..removeWhere(
          (match) => literalRanges.any(
            (range) => range.start < match.end && range.end > match.start,
          ),
        );
    if (resolveUnicode) matches.sort((a, b) => a.start.compareTo(b.start));
    if (matches.isEmpty) return _resolved(context, text, const []);

    final controller = SitePresentationScope.maybeOf(context);
    if (controller == null) return _resolved(context, text, const []);
    return ListenableBuilder(
      listenable: controller.emojiChangesFor(siteUrl),
      builder: (context, _) {
        if (controller.emojiCatalogFor(siteUrl) == null) {
          unawaited(controller.ensureEmojiCatalog(siteUrl));
        }
        unawaited(controller.ensureEmojiSearchAliases(siteUrl));
        return _resolved(context, text, [
          for (final match in matches)
            if (controller.emojiNameFor(siteUrl, match.name) case final name?)
              (start: match.start, end: match.end, name: name),
        ]);
      },
    );
  }

  Widget _resolved(
    BuildContext context,
    String text,
    List<({int start, int end, String name})> emoji,
  ) {
    final query = SearchWords.of(context);
    final runs = query.isEmpty
        ? this.runs
        : [
            for (final run in this.runs)
              for (final span in searchTextSpans(
                run.text,
                query,
                searchHitStyle(context),
              ))
                SiteEmojiTextRun(
                  span.text ?? '',
                  style: run.style?.merge(span.style) ?? span.style,
                ),
          ];
    final wrapExcerpt =
        ellipsisAtWordBoundary &&
        maxLines != null &&
        overflow == TextOverflow.ellipsis &&
        leading.isEmpty &&
        trailing.isEmpty;
    if (!wrapExcerpt &&
        emoji.isEmpty &&
        runs.length == 1 &&
        runs.single.style == null &&
        leading.isEmpty &&
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
    final spans = <InlineSpan>[
      for (final marker in leading)
        _MarkerWidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: marker,
        ),
    ];
    final cursor = _StyledRunCursor(runs);
    final emojiDimensions = <PlaceholderDimensions>[];
    final scaler = MediaQuery.textScalerOf(context);

    for (final match in emoji) {
      cursor.appendText(spans, match.start);
      final emojiStyle = effectiveStyle.merge(cursor.style);
      final fontSize = emojiStyle.fontSize ?? DiscourseTypography.sm;
      if (wrapExcerpt) {
        emojiDimensions.add(
          PlaceholderDimensions(
            size: Size.square(scaler.scale(fontSize) * emojiScale),
            alignment: PlaceholderAlignment.middle,
          ),
        );
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SiteEmojiImage(
            siteUrl: siteUrl,
            name: match.name,
            size: fontSize * emojiScale,
            alt: text.substring(match.start, match.end),
            style: emojiStyle,
          ),
        ),
      );
      cursor.skipTo(match.end);
    }
    cursor.appendText(spans, text.length);
    spans.addAll(
      trailing.map(
        (marker) => _MarkerWidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: marker,
        ),
      ),
    );

    Widget buildText(List<InlineSpan> visible) => Text.rich(
      TextSpan(children: visible),
      maxLines: maxLines,
      overflow: overflow,
      style: style,
      textAlign: textAlign,
    );
    final richText = wrapExcerpt
        ? LayoutBuilder(
            builder: (context, constraints) => buildText(
              _trimExcerpt(
                spans,
                emojiDimensions,
                style: MediaQuery.boldTextOf(context)
                    ? effectiveStyle.merge(
                        const TextStyle(fontWeight: FontWeight.bold),
                      )
                    : effectiveStyle,
                maxWidth: constraints.maxWidth,
                lines: maxLines!,
                direction: Directionality.of(context),
                locale: Localizations.maybeLocaleOf(context),
                scaler: scaler,
              ),
            ),
          )
        : buildText(spans);

    // Inline markers carry meaningful semantics of their own. Keep
    // those descendants exposed; ordinary emoji-only prose still gets one
    // clean label rather than being announced as several fragments.
    if (leading.isNotEmpty || trailing.isNotEmpty) {
      return richText;
    }

    // The artwork is decorative to assistive technology; the original text is
    // the clearest single reading of the row.
    return Semantics(
      label: text,
      child: ExcludeSemantics(child: richText),
    );
  }
}

// SkParagraph's built-in ellipsis may leave part of the final word. The
// preview still uses its shaped line breaks, including the inline emoji boxes.
List<InlineSpan> _trimExcerpt(
  List<InlineSpan> spans,
  List<PlaceholderDimensions> placeholderDimensions, {
  required TextStyle style,
  required double maxWidth,
  required int lines,
  required TextDirection direction,
  required Locale? locale,
  required TextScaler scaler,
}) {
  if (maxWidth <= 0 || !maxWidth.isFinite) return spans;
  final shaped = TextSpan(style: style, children: spans);
  final painter = TextPainter(
    text: shaped,
    textDirection: direction,
    locale: locale,
    textScaler: scaler,
    maxLines: lines,
  );
  try {
    painter
      ..setPlaceholderDimensions(placeholderDimensions)
      ..layout(maxWidth: maxWidth);
    if (!painter.didExceedMaxLines) return spans;
    final last = painter.computeLineMetrics().last;
    final position = painter.getPositionForOffset(
      Offset(last.left + last.width / 2, last.baseline - 1),
    );
    final line = painter.getLineBoundary(position);
    final plain = shaped.toPlainText(includeSemanticsLabels: false);
    var end = plain.substring(0, line.end).trimRight().length;
    if (end <= line.start) return spans;
    final word = painter.getWordBoundary(TextPosition(offset: end - 1));
    if (word.end > end) end = plain.substring(0, word.start).trimRight().length;
    while (end > line.start) {
      final truncated = <InlineSpan>[];
      var offset = 0;
      var placeholders = 0;
      for (final span in spans) {
        if (offset >= end) break;
        if (span is TextSpan) {
          final text = span.text!;
          final remaining = end - offset;
          truncated.add(
            remaining >= text.length
                ? span
                : TextSpan(
                    text: text.substring(0, remaining),
                    style: span.style,
                  ),
          );
          offset += text.length;
        } else {
          truncated.add(span);
          placeholders++;
          offset++;
        }
      }
      truncated.add(const TextSpan(text: '…'));
      painter
        ..text = TextSpan(style: style, children: truncated)
        ..setPlaceholderDimensions(
          placeholderDimensions.take(placeholders).toList(growable: false),
        )
        ..layout(maxWidth: maxWidth);
      if (!painter.didExceedMaxLines) return truncated;
      // The ellipsis took room from the final word. Keep the preceding one
      // when it fits, or let the engine truncate an unbroken string itself.
      end = plain.substring(0, end).lastIndexOf(RegExp(r'\s'));
      if (end > 0) end = plain.substring(0, end).trimRight().length;
    }
    return spans;
  } finally {
    painter.dispose();
  }
}

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

class _MarkerWidgetSpan extends WidgetSpan {
  const _MarkerWidgetSpan({required super.child, super.alignment});

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) {}
}
