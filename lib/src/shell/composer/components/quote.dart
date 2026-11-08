import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/d_icons.dart';
import '../../../theme/discourse_typography.dart';
import '../../site_emoji_text.dart';
import '../block_selection.dart';
import '../markdown_highlight.dart';
import '../markdown_style.dart';
import '../source_projection.dart';
import 'quote_source.dart';

export 'quote_source.dart';

List<InlineSpan> buildComposerQuoteSpans({
  required String source,
  required ComposerQuoteBlock block,
  required String contents,
  required String? siteUrl,
  required TextStyle baseStyle,
  required Key quoteKey,
  required GlobalKey removeKey,
  required bool selected,
  required VoidCallback? onRemove,
}) => [
  WidgetSpan(
    alignment: PlaceholderAlignment.top,
    style: baseStyle,
    child: KeyedSubtree(
      key: quoteKey,
      child: ComposerBlockSelection(
        selected: selected,
        child: IgnorePointer(
          child: ComposerQuotePreview(
            block: block,
            onRemove: onRemove,
            contents: contents,
            siteUrl: siteUrl,
            baseStyle: baseStyle,
            removeKey: removeKey,
          ),
        ),
      ),
    ),
  ),
  ...composerCollapsedBlockSourceTail(
    source: source,
    start: block.start,
    end: block.contentEnd,
    baseStyle: baseStyle,
  ),
];

class ComposerQuoteInputFormatter extends TextInputFormatter {
  const ComposerQuoteInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return newValue;
    final blocks = parseComposerQuotes(oldValue.text);
    if (blocks.isEmpty) return newValue;

    var prefix = 0;
    final shared = math.min(oldValue.text.length, newValue.text.length);
    while (prefix < shared &&
        oldValue.text.codeUnitAt(prefix) == newValue.text.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldValue.text.length - prefix &&
        suffix < newValue.text.length - prefix &&
        oldValue.text.codeUnitAt(oldValue.text.length - suffix - 1) ==
            newValue.text.codeUnitAt(newValue.text.length - suffix - 1)) {
      suffix++;
    }
    var replacedEnd = oldValue.text.length - suffix;

    // Shared delimiters can make a whole-selection replacement look like an
    // interior edit. Trust the selection only when the unchanged text on both
    // sides still fits, without overlap, in the proposed value.
    final selection = oldValue.selection;
    if (selection.isValid &&
        !selection.isCollapsed &&
        selection.end <= oldValue.text.length &&
        newValue.text.length >=
            oldValue.text.length - (selection.end - selection.start) &&
        newValue.text.startsWith(oldValue.text.substring(0, selection.start)) &&
        newValue.text.endsWith(oldValue.text.substring(selection.end))) {
      prefix = selection.start;
      replacedEnd = selection.end;
    }

    for (final block in blocks) {
      if (prefix == replacedEnd) {
        if (prefix > block.start && prefix < block.contentEnd) return oldValue;
        continue;
      }
      if (prefix >= block.contentEnd || replacedEnd <= block.start) continue;
      final coversWholeBlock =
          prefix <= block.start && replacedEnd >= block.end;
      if (!coversWholeBlock) return oldValue;
    }
    return newValue;
  }
}

class ComposerQuotePreview extends StatefulWidget {
  const ComposerQuotePreview({
    super.key,
    required this.block,
    required this.contents,
    required this.baseStyle,
    this.removeKey,
    this.onRemove,
    this.siteUrl,
  });

  final ComposerQuoteBlock block;
  final String contents;
  final TextStyle baseStyle;
  final String? siteUrl;
  final Key? removeKey;
  final VoidCallback? onRemove;

  @visibleForTesting
  static int scans = 0;

  @override
  State<ComposerQuotePreview> createState() => _ComposerQuotePreviewState();
}

class _ComposerQuotePreviewState extends State<ComposerQuotePreview> {
  String? _scanned;
  List<MarkdownRun> _runs = const [];

  List<MarkdownRun> get _contentRuns {
    if (_scanned == widget.contents) return _runs;
    _scanned = widget.contents;
    ComposerQuotePreview.scans += 1;
    return _runs = scanMarkdown(widget.contents, shared: false);
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final contents = widget.contents;
    final baseStyle = widget.baseStyle;
    final removeKey = widget.removeKey;
    final theme = Theme.of(context);
    final title = block.title;
    final quoteBodyStyle = baseStyle.copyWith(
      fontSize: DiscourseTypography.base,
      height: DiscourseTypography.lineHeightContent,
      color: DTokens.of(context).mutedForeground,
    );
    final runs = [
      for (final run in _contentRuns)
        if (!run.has(Md.marker))
          SiteEmojiTextRun(
            contents.substring(run.start, run.end),
            literal: run.has(Md.code) || run.has(Md.codeBlock),
            style: markdownStyle(run.mask, run.detail, quoteBodyStyle, theme),
          ),
    ];
    final quoteBody = widget.siteUrl == null
        ? Text.rich(
            TextSpan(
              children: [
                for (final run in runs)
                  TextSpan(text: run.text, style: run.style),
              ],
            ),
            style: quoteBodyStyle,
          )
        : SiteEmojiText(runs, siteUrl: widget.siteUrl!, style: quoteBodyStyle);

    return Semantics(
      container: true,
      label: title == null
          ? context.l10n.quote
          : context.l10n.quoteFrom((title).toString()),
      hint: widget.onRemove == null
          ? null
          : context.l10n.readOnlyUseTheRemoveQuoteButtonToDeleteIt,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DQuote(
          header: Text(
            title ?? context.l10n.quote,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: widget.onRemove == null
              ? null
              : DButton.iconOnly(
                  key: removeKey,
                  tooltip: context.l10n.removeQuote,
                  semanticLabel: context.l10n.removeQuote,
                  size: DButtonSize.tabAction,
                  variant: DButtonVariant.ghost,
                  icon: const DIcon(DIcons.xmark),
                  onPressed: widget.onRemove,
                ),
          child: quoteBody,
        ),
      ),
    );
  }
}
