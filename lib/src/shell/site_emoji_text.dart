import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/discourse_typography.dart';
import 'emoji.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';

@immutable
class SiteEmojiTextRun {
  const SiteEmojiTextRun(this.text, {this.style});

  final String text;
  final TextStyle? style;
}

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

  final List<Widget> trailing;

  static final RegExp shortcodePattern = RegExp(
    r':([a-z0-9_+-]+(?::t[1-6])?):',
  );

  @override
  State<SiteEmojiText> createState() => _SiteEmojiTextState();
}

class _SiteEmojiTextState extends State<SiteEmojiText> {
  ShellController? _askedController;
  String? _askedSite;

  @override
  Widget build(BuildContext context) {
    final text = widget.runs.map((run) => run.text).join();
    if (!SiteEmojiText.shortcodePattern.hasMatch(text)) {
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
          for (final match in SiteEmojiText.shortcodePattern.allMatches(text))
            if (controller.emojiNameFor(widget.siteUrl, match.group(1)!)
                case final name?)
              (match: match, name: name),
        ]);
      },
    );
  }

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

  Widget _resolved(
    BuildContext context,
    String text,
    List<({RegExpMatch match, String name})> emoji,
  ) {
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

    for (final resolved in emoji) {
      final match = resolved.match;
      cursor.appendText(spans, match.start);
      final emojiStyle = effectiveStyle.merge(cursor.style);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SiteEmojiImage(
            siteUrl: widget.siteUrl,
            name: resolved.name,
            size:
                (emojiStyle.fontSize ?? DiscourseTypography.fontDown1) *
                emojiScale,
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

class _TrailingWidgetSpan extends WidgetSpan {
  const _TrailingWidgetSpan({required super.child, super.alignment});

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) {}
}
