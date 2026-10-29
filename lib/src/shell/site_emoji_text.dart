import 'dart:async';

import 'package:flutter/material.dart';

import '../models/site_emoji.dart';
import '../theme/discourse_typography.dart';
import 'emoji.dart';
import 'search_words.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';

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
    this.leading = const [],
    this.trailing = const [],
  }) : runs = [SiteEmojiTextRun(text)];

  final List<SiteEmojiTextRun> runs;
  final String siteUrl;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextStyle? style;
  final TextAlign? textAlign;

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
    final matches = shortcodeMatches(text)
        .where(
          (match) => !literalRanges.any(
            (range) => range.start < match.end && range.end > match.start,
          ),
        )
        .toList(growable: false);
    if (matches.isEmpty) return _resolved(context, text, const []);

    final controller = ShellScope.maybeIdentityOf(context);
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
            if (controller.emojiNameFor(siteUrl, match.group(1)!)
                case final name?)
              (match: match, name: name),
        ]);
      },
    );
  }

  Widget _resolved(
    BuildContext context,
    String text,
    List<({RegExpMatch match, String name})> emoji,
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
    if (emoji.isEmpty &&
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

    for (final resolved in emoji) {
      final match = resolved.match;
      cursor.appendText(spans, match.start);
      final emojiStyle = effectiveStyle.merge(cursor.style);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SiteEmojiImage(
            siteUrl: siteUrl,
            name: resolved.name,
            size: (emojiStyle.fontSize ?? DiscourseTypography.sm) * emojiScale,
            alt: match.group(0)!,
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

    final richText = Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
      style: style,
      textAlign: textAlign,
    );

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
