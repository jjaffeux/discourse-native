import 'dart:async';

import 'package:flutter/material.dart';

import 'emoji.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
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
///
/// Only shortcodes the site is known to register are drawn, the way the web
/// client replaces only registered codes: prose is full of colon-delimited
/// tokens — `10:30:45` matches the pattern — and giving one a placeholder
/// shifts the layout while a request for artwork that cannot exist goes out.
/// Until the site's catalog has answered, every shortcode stays literal text
/// for the same reason.
class SiteEmojiText extends StatefulWidget {
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
  State<SiteEmojiText> createState() => _SiteEmojiTextState();
}

class _SiteEmojiTextState extends State<SiteEmojiText> {
  ShellController? _askedController;
  String? _askedSite;

  @override
  Widget build(BuildContext context) {
    final text = widget.runs.map((run) => run.text).join();
    if (!SiteEmojiText._shortcode.hasMatch(text)) {
      return _resolved(context, text, const []);
    }

    // The catalog deliberately loads without presentation churn — see
    // `presentationTokenFor` — so its arrival rebuilds through this state's
    // own request below, while custom uploads and settings changes arrive
    // through the token like every other presentation dependency.
    return ShellSelector<Object>(
      select: (controller) => controller.presentationTokenFor(widget.siteUrl),
      builder: (context, _, _) {
        final controller = ShellScope.read(context);
        if (controller.emojiCatalogFor(widget.siteUrl) == null) {
          _requestCatalog(controller);
        }
        return _resolved(context, text, [
          for (final match in SiteEmojiText._shortcode.allMatches(text))
            if (controller.knowsEmoji(widget.siteUrl, match.group(1)!)) match,
        ]);
      },
    );
  }

  /// Asks for the catalog once per (controller, site) this element has seen.
  ///
  /// The controller already shares and bounds the fetch; this guard exists
  /// because a permanently failed catalog answers null immediately, and asking
  /// again from the rebuild that follows each answer would loop build →
  /// microtask → build for as long as the row is on screen.
  ///
  /// A null answer releases the guard without asking again. Nothing rebuilds
  /// from here, so there is no loop to start; it only means that if a catalog
  /// reaches the site by some other route — reselecting it retries the fetch —
  /// the next rebuild is allowed to notice.
  void _requestCatalog(ShellController controller) {
    if (identical(_askedController, controller) &&
        _askedSite == widget.siteUrl) {
      return;
    }
    _askedController = controller;
    _askedSite = widget.siteUrl;
    unawaited(
      controller.ensureEmojiCatalog(widget.siteUrl).then((catalog) {
        if (!mounted) return;
        if (catalog != null) {
          setState(() {});
        } else if (identical(_askedController, controller) &&
            _askedSite == widget.siteUrl) {
          _askedController = null;
          _askedSite = null;
        }
      }),
    );
  }

  Widget _resolved(BuildContext context, String text, List<RegExpMatch> emoji) {
    final runs = widget.runs;
    if (emoji.isEmpty &&
        runs.length == 1 &&
        runs.single.style == null &&
        widget.trailing.isEmpty) {
      return Text(
        text,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        style: widget.style,
        textAlign: widget.textAlign,
      );
    }

    final effectiveStyle = DefaultTextStyle.of(
      context,
    ).style.merge(widget.style);
    final spans = <InlineSpan>[];
    final cursor = _StyledRunCursor(runs);

    for (final match in emoji) {
      cursor.appendText(spans, match.start);
      final name = match.group(1)!;
      final emojiStyle = effectiveStyle.merge(cursor.style);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SiteEmojiImage(
            siteUrl: widget.siteUrl,
            name: name,
            size: (emojiStyle.fontSize ?? 14) * emojiScale,
            alt: match.group(0)!,
            style: emojiStyle,
          ),
        ),
      );
      cursor.skipTo(match.end);
    }
    cursor.appendText(spans, text.length);
    spans.addAll(
      widget.trailing.map(
        (marker) => _TrailingWidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: marker,
        ),
      ),
    );

    final richText = Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: widget.style,
      textAlign: widget.textAlign,
    );

    // A trailing WidgetSpan carries meaningful semantics of its own. Keep
    // those descendants exposed; ordinary emoji-only prose still gets one
    // clean label rather than being announced as several fragments.
    if (widget.trailing.isNotEmpty) return richText;

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
