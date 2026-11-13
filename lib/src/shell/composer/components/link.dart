import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/site_config.dart';
import '../../../plugin_api/composer_syntax.dart';
import '../artwork.dart';
import '../markdown_highlight.dart';
import 'link_source.dart';
import 'quote_source.dart';

ComposerSyntaxKind get composerLinkSyntaxKind => ComposerSyntaxKind(
  owner: const PluginId('core'),
  name: 'link',
  label: appL10n.link,
);

final class ComposerLinkSyntaxPolicy implements ComposerSyntaxPolicy {
  const ComposerLinkSyntaxPolicy({
    this.enableLinkify = true,
    this.linkifyTlds = SiteConfig.defaultMarkdownLinkifyTlds,
    this.artwork,
  });

  final bool enableLinkify;
  final List<String> linkifyTlds;

  /// Read when a link is drawn or edited, because the editor installs its
  /// artwork after the document controller has already scanned the source.
  final ComposerArtwork Function()? artwork;

  @override
  ComposerSyntaxKind get kind => composerLinkSyntaxKind;

  @override
  Object? get projectionState =>
      Object.hash(enableLinkify, Object.hashAll(linkifyTlds));

  @override
  TextInputFormatter? get inputFormatter => null;

  @override
  List<ComposerSyntaxProjection> parse(String source) =>
      parseWithCodeRanges(source, markdownCodeRanges(source));

  List<ComposerSyntaxProjection> parseWithCodeRanges(
    String source,
    CodeRanges codeRanges,
  ) => [
    for (final block in parseComposerLinks(
      source,
      codeRanges: codeRanges,
      enableLinkify: enableLinkify,
      linkifyTlds: linkifyTlds,
    ))
      ComposerLinkSyntaxProjection(block, artwork),
  ];
}

final class ComposerLinkSyntaxProjection implements ComposerSyntaxProjection {
  const ComposerLinkSyntaxProjection(this.block, [this._artwork]);

  final ComposerLinkBlock block;
  final ComposerArtwork Function()? _artwork;

  ComposerArtwork get _installedArtwork =>
      _artwork?.call() ?? composerArtworkMissing();

  @override
  int get start => block.start;

  @override
  int get end => block.end;

  @override
  String get source => block.source;

  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) {
    final selection = document.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;
    if (selection.extentOffset == start || selection.extentOffset == end) {
      return false;
    }
    return !suppressCollapsedCaret &&
        selection.extentOffset > start &&
        selection.extentOffset < end;
  }

  @override
  int caretAfter(String document) => end;

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: end),
        composing: TextRange.empty,
      );

  @override
  bool get supportsHover => true;

  @override
  bool get protectsAdjacentDelete => block.kind == ComposerLinkKind.markdown;

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) => [
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      style: context.baseStyle,
      child: _installedArtwork.link(
        key: context.pillKey,
        anchor: block.anchor,
        url: block.url,
        baseStyle: context.baseStyle,
        highlighted: context.highlighted,
        hovered: context.hovered,
        siteUrl: context.siteUrl,
        resolveUploadUrl: context.resolveUploadUrl,
      ),
    ),
    if (source.length > 1)
      TextSpan(text: source.substring(1), style: _hidden(context.baseStyle)),
  ];

  @override
  Future<void> edit(BuildContext context, ComposerEditorHost editor) =>
      _installedArtwork.editLink(context, editor, block);

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (!editor.isCurrent || !editor.isEditing) return;
    final expectedValue = editor.value;
    if (!_stillContains(expectedValue.text, block)) return;
    editor.commitText(
      expectedText: expectedValue.text,
      value: expectedValue.copyWith(
        text: expectedValue.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
        composing: TextRange.empty,
      ),
    );
  }
}

/// Turns selected prose into a link when the clipboard contains one web URL.
TextEditingValue? composerPastedLinkValue(
  TextEditingValue current,
  String clipboard,
) {
  final selection = current.selection;
  final url = clipboard.trim();
  final uri = Uri.tryParse(url);
  if (!selection.isValid ||
      selection.isCollapsed ||
      selection.end > current.text.length ||
      (current.composing.isValid && !current.composing.isCollapsed) ||
      RegExp(r'\s').hasMatch(url) ||
      uri == null ||
      !const ['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return null;
  }
  final anchor = selection.textInside(current.text);
  if (anchor.trim().isEmpty ||
      anchor.contains('\n') ||
      markdownCodeRanges(
        current.text,
      ).overlaps(selection.start, selection.end) ||
      parseComposerLinks(current.text).any(
        (link) => link.start < selection.end && link.end > selection.start,
      )) {
    return null;
  }
  return composerLinkValue(
    current: current,
    expectedText: current.text,
    selection: selection,
    url: url,
    anchor: anchor,
  );
}

final _linkAnchorDelimiters = RegExp(r'[\[\]\\]');
final _linkUrlDelimiters = RegExp(r'[ ()<>\\]');
final _linkSourceAnchorDelimiters = RegExp(r'\\[!-/:-@\[-`{-~]|[\[\]\\]');
final _linkSourceUrlDelimiters = RegExp(r'\\[!-/:-@\[-`{-~]|[ ()<>\\]');

String _serializedComposerLinkPart(
  String value, {
  required bool destination,
  required bool preserveMarkdownEscapes,
}) {
  final pattern = destination
      ? (preserveMarkdownEscapes
            ? _linkSourceUrlDelimiters
            : _linkUrlDelimiters)
      : (preserveMarkdownEscapes
            ? _linkSourceAnchorDelimiters
            : _linkAnchorDelimiters);
  return value.replaceAllMapped(pattern, (match) {
    final delimiter = match[0]!;
    if (preserveMarkdownEscapes && delimiter.length == 2) return delimiter;
    return destination
        ? '%${delimiter.codeUnitAt(0).toRadixString(16).toUpperCase()}'
        : '\\$delimiter';
  });
}

TextEditingValue? composerLinkValue({
  required TextEditingValue current,
  required String expectedText,
  required TextSelection selection,
  required String url,
  required String anchor,
  ComposerLinkBlock? existingLink,
}) {
  if (current.text != expectedText ||
      !selection.isValid ||
      selection.end > current.text.length ||
      selectionTouchesComposerQuote(
        parseComposerQuotes(current.text),
        selection,
      )) {
    return null;
  }

  final normalizedUrl = url.trim();
  if (normalizedUrl.isEmpty) return null;
  final linkText = anchor.isEmpty ? normalizedUrl : anchor;
  // Existing Markdown fields contain editable source escapes. Keep those
  // escapes, and leave unchanged fields verbatim, while escaping new input.
  final preserveSource = existingLink?.kind == ComposerLinkKind.markdown;
  final sourceAnchor = preserveSource && linkText == existingLink!.anchor
      ? linkText
      : _serializedComposerLinkPart(
          linkText,
          destination: false,
          preserveMarkdownEscapes: preserveSource,
        );
  final sourceUrl = preserveSource && normalizedUrl == existingLink!.url
      ? existingLink.source.substring(
          existingLink.anchor.length + 3,
          existingLink.source.length - 1,
        )
      : _serializedComposerLinkPart(
              normalizedUrl,
              destination: true,
              preserveMarkdownEscapes: preserveSource,
            ) +
            (existingLink?.destinationSuffix ?? '');
  final insertion = '[$sourceAnchor]($sourceUrl)';
  return current.copyWith(
    text: current.text.replaceRange(selection.start, selection.end, insertion),
    selection: TextSelection.collapsed(
      offset: selection.start + insertion.length,
    ),
    composing: TextRange.empty,
  );
}

TextStyle _hidden(TextStyle base) => TextStyle(
  color: const Color(0x00000000),
  fontFamily: base.fontFamily,
  fontFamilyFallback: base.fontFamilyFallback,
  fontSize: 0,
  height: 0,
);

bool _stillContains(String document, ComposerLinkBlock block) =>
    block.start >= 0 &&
    block.end <= document.length &&
    block.start <= block.end &&
    document.substring(block.start, block.end) == block.source;
