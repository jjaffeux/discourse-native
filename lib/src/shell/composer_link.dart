import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/site_config.dart';
import '../plugin_api/composer_syntax.dart';
import '../theme/d_button.dart';
import 'composer_quotes.dart';
import 'markdown_highlight.dart';

const composerLinkSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('core'),
  name: 'link',
);

enum ComposerLinkKind { markdown, linkify }

@immutable
class ComposerLinkBlock {
  const ComposerLinkBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.anchor,
    required this.url,
    required this.kind,
  });

  final int start;
  final int end;
  final String source;
  final String anchor;
  final String url;
  final ComposerLinkKind kind;
}

final RegExp _linkifyCandidatePattern = RegExp(
  r'(?:(?:https?|ftp)://|//)[^\s<]+'
  r"|[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
  r'(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+'
  r'[A-Za-z]{2,63}'
  r'|(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+'
  r'[A-Za-z]{2,63}(?::[0-9]{1,5})?(?:[/?#][^\s<]*)?',
  caseSensitive: false,
  unicode: true,
);
final RegExp _linkifyHostBoundaryPattern = RegExp(r'[:/?#]');
final RegExp _linkReferencePrefixPattern = RegExp(r'^\s*\[[^\]\n]+\]:\s*$');

List<ComposerLinkBlock> parseComposerLinks(
  String source, {
  CodeRanges? codeRanges,
  bool enableLinkify = true,
  List<String> linkifyTlds = SiteConfig.defaultMarkdownLinkifyTlds,
}) {
  if (source.isEmpty) return const [];
  final code = codeRanges ?? CodeRanges.of(scanMarkdown(source));
  final links = <ComposerLinkBlock>[];
  final markdownRanges = <TextRange>[];
  var offset = 0;
  var barrenTo = -1;
  var lineEnd = -1;

  while (offset < source.length) {
    final start = source.indexOf('[', offset);
    if (start < 0) break;
    if (start < barrenTo) {
      offset = start + 1;
      continue;
    }
    if (start >= lineEnd) {
      final next = source.indexOf('\n', start + 1);
      lineEnd = next < 0 ? source.length : next;
    }

    final bracket = source.indexOf(']', start + 1);
    if (bracket < 0) break;
    if (bracket > lineEnd) {
      barrenTo = lineEnd;
      offset = start + 1;
      continue;
    }
    if (bracket == start + 1 ||
        bracket + 2 >= source.length ||
        source[bracket + 1] != '(' ||
        _isEscaped(source, start) ||
        _isEscaped(source, bracket)) {
      offset = start + 1;
      continue;
    }

    final urlStart = bracket + 2;
    var close = urlStart;
    while (close < source.length &&
        source[close] != ')' &&
        !_isWhitespace(source.codeUnitAt(close))) {
      close += 1;
    }
    if (close == urlStart || close >= source.length || source[close] != ')') {
      offset = start + 1;
      continue;
    }

    final end = close + 1;
    offset = end;
    markdownRanges.add(TextRange(start: start, end: end));
    if (code.overlaps(start, end)) continue;
    if (start > 0 && source[start - 1] == '!') continue;
    links.add(
      ComposerLinkBlock(
        start: start,
        end: end,
        source: source.substring(start, end),
        anchor: source.substring(start + 1, bracket),
        url: source.substring(urlStart, close),
        kind: ComposerLinkKind.markdown,
      ),
    );
  }

  if (enableLinkify) {
    final tlds = linkifyTlds
        .map(_normalizedTld)
        .where((value) => value.isNotEmpty)
        .toSet();
    var markdownRangeIndex = 0;
    for (final match in _linkifyCandidatePattern.allMatches(source)) {
      final start = match.start;
      final end = _trimLinkifyEnd(source, start, match.end);
      while (markdownRangeIndex < markdownRanges.length &&
          markdownRanges[markdownRangeIndex].end <= start) {
        markdownRangeIndex += 1;
      }
      final overlapsMarkdown =
          markdownRangeIndex < markdownRanges.length &&
          markdownRanges[markdownRangeIndex].start < end;
      if (end <= start ||
          code.overlaps(start, end) ||
          overlapsMarkdown ||
          _insideAngleBrackets(source, start) ||
          _isLinkReferenceDestination(source, start) ||
          !_hasLinkifyBoundary(source, start)) {
        continue;
      }

      final raw = source.substring(start, end);
      final normalized = _normalizedLinkifyUrl(raw, tlds);
      if (normalized == null) continue;
      links.add(
        ComposerLinkBlock(
          start: start,
          end: end,
          source: raw,
          anchor: raw,
          url: normalized,
          kind: ComposerLinkKind.linkify,
        ),
      );
    }
  }

  links.sort((a, b) => a.start.compareTo(b.start));
  return List.unmodifiable(links);
}

String _normalizedTld(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('.') ? normalized.substring(1) : normalized;
}

int _trimLinkifyEnd(String source, int start, int end) {
  const punctuation = {0x21, 0x22, 0x27, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F};
  while (end > start && punctuation.contains(source.codeUnitAt(end - 1))) {
    end -= 1;
  }
  for (final pair in const [(0x28, 0x29), (0x5B, 0x5D), (0x7B, 0x7D)]) {
    while (end > start && source.codeUnitAt(end - 1) == pair.$2) {
      var opens = 0;
      var closes = 0;
      for (var index = start; index < end; index += 1) {
        final unit = source.codeUnitAt(index);
        if (unit == pair.$1) opens += 1;
        if (unit == pair.$2) closes += 1;
      }
      if (closes <= opens) break;
      end -= 1;
    }
  }
  return end;
}

String? _normalizedLinkifyUrl(String raw, Set<String> tlds) {
  final lower = raw.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('ftp://') ||
      lower.startsWith('//')) {
    return raw;
  }

  final at = raw.lastIndexOf('@');
  final hostAndPath = at < 0 ? raw : raw.substring(at + 1);
  final boundary = hostAndPath.indexOf(_linkifyHostBoundaryPattern);
  final host = (boundary < 0 ? hostAndPath : hostAndPath.substring(0, boundary))
      .toLowerCase();
  final dot = host.lastIndexOf('.');
  if (dot < 0 || !tlds.contains(host.substring(dot + 1))) return null;
  return at < 0 ? 'http://$raw' : 'mailto:$raw';
}

bool _hasLinkifyBoundary(String source, int start) {
  if (start == 0) return true;
  final previous = source.codeUnitAt(start - 1);
  return !_isAsciiLetterOrNumber(previous) &&
      previous != 0x5F &&
      previous != 0x40;
}

bool _isAsciiLetterOrNumber(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A);

bool _insideAngleBrackets(String source, int start) {
  final open = source.lastIndexOf('<', start);
  final close = source.lastIndexOf('>', start);
  return open > close;
}

bool _isLinkReferenceDestination(String source, int start) {
  final lineStart = start == 0 ? 0 : source.lastIndexOf('\n', start - 1) + 1;
  final prefix = source.substring(lineStart, start);
  return _linkReferencePrefixPattern.hasMatch(prefix);
}

bool _isEscaped(String source, int offset) {
  var slashes = 0;
  for (
    var index = offset - 1;
    index >= 0 && source.codeUnitAt(index) == 0x5C;
    index -= 1
  ) {
    slashes += 1;
  }
  return slashes.isOdd;
}

bool _isWhitespace(int unit) => unit == 0x20 || (unit >= 0x09 && unit <= 0x0D);

final class ComposerLinkSyntaxPolicy implements ComposerSyntaxPolicy {
  const ComposerLinkSyntaxPolicy({
    this.enableLinkify = true,
    this.linkifyTlds = SiteConfig.defaultMarkdownLinkifyTlds,
  });

  final bool enableLinkify;
  final List<String> linkifyTlds;

  @override
  ComposerSyntaxKind get kind => composerLinkSyntaxKind;

  @override
  Object? get projectionState =>
      Object.hash(enableLinkify, Object.hashAll(linkifyTlds));

  @override
  TextInputFormatter? get inputFormatter => null;

  @override
  List<ComposerSyntaxProjection> parse(String source) =>
      parseWithCodeRanges(source, CodeRanges.of(scanMarkdown(source)));

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
      ComposerLinkSyntaxProjection(block),
  ];
}

final class ComposerLinkSyntaxProjection implements ComposerSyntaxProjection {
  const ComposerLinkSyntaxProjection(this.block);

  final ComposerLinkBlock block;

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
  bool get hidesCursorWhenSelected => true;

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) => [
    WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      style: context.baseStyle,
      child: IgnorePointer(
        child: ComposerLinkPill(
          key: context.pillKey,
          anchor: block.anchor,
          url: block.url,
          baseStyle: context.baseStyle,
          highlighted: context.highlighted,
          hovered: context.hovered,
        ),
      ),
    ),
    if (source.length > 1)
      TextSpan(text: source.substring(1), style: _hidden(context.baseStyle)),
  ];

  @override
  Future<void> edit(BuildContext context, ComposerEditorHost editor) =>
      showComposerLinkDialog(context: context, composer: editor, link: block);

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
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

class ComposerLinkPill extends StatelessWidget {
  const ComposerLinkPill({
    super.key,
    required this.anchor,
    required this.url,
    required this.baseStyle,
    required this.highlighted,
    required this.hovered,
  });

  final String anchor;
  final String url;
  final TextStyle baseStyle;
  final bool highlighted;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      link: true,
      label: anchor,
      hint: 'Edit link to $url',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted
              ? primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          anchor,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: baseStyle.copyWith(
            color: primary,
            decoration: hovered ? TextDecoration.underline : null,
            decorationColor: primary,
          ),
        ),
      ),
    );
  }
}

TextEditingValue? composerLinkValue({
  required TextEditingValue current,
  required String expectedText,
  required TextSelection selection,
  required String url,
  required String anchor,
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
  final insertion = '[$linkText]($normalizedUrl)';
  return current.copyWith(
    text: current.text.replaceRange(selection.start, selection.end, insertion),
    selection: TextSelection.collapsed(
      offset: selection.start + insertion.length,
    ),
    composing: TextRange.empty,
  );
}

Future<void> showComposerLinkDialog({
  required BuildContext context,
  required ComposerEditorHost composer,
  ComposerLinkBlock? link,
}) async {
  final expectedValue = composer.value;
  final capturedSelection = link == null
      ? expectedValue.selection
      : TextSelection(baseOffset: link.start, extentOffset: link.end);
  final selectionIsInBounds =
      capturedSelection.isValid &&
      capturedSelection.end <= expectedValue.text.length;
  final selectedAnchor =
      selectionIsInBounds && !capturedSelection.isCollapsed && link == null
      ? expectedValue.text.substring(
          capturedSelection.start,
          capturedSelection.end,
        )
      : '';
  final draft = await showDialog<_ComposerLinkDraft>(
    context: context,
    builder: (context) => _ComposerLinkDialog(
      initialAnchor: link?.anchor ?? selectedAnchor,
      initialUrl: link?.url ?? '',
    ),
  );
  if (draft == null || !selectionIsInBounds) return;

  final current = composer.value;
  final next = composerLinkValue(
    current: current,
    expectedText: expectedValue.text,
    selection: capturedSelection,
    url: draft.url,
    anchor: draft.anchor,
  );
  if (next == null ||
      !composer.commitText(expectedText: expectedValue.text, value: next)) {
    return;
  }
  composer.requestFocus();
}

@immutable
class _ComposerLinkDraft {
  const _ComposerLinkDraft({required this.url, required this.anchor});

  final String url;
  final String anchor;
}

class _ComposerLinkDialog extends StatefulWidget {
  const _ComposerLinkDialog({
    required this.initialAnchor,
    required this.initialUrl,
  });

  final String initialAnchor;
  final String initialUrl;

  @override
  State<_ComposerLinkDialog> createState() => _ComposerLinkDialogState();
}

class _ComposerLinkDialogState extends State<_ComposerLinkDialog> {
  late final TextEditingController _url;
  late final TextEditingController _anchor;

  bool get _canInsert => _url.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initialUrl);
    _anchor = TextEditingController(text: widget.initialAnchor);
  }

  @override
  void dispose() {
    _url.dispose();
    _anchor.dispose();
    super.dispose();
  }

  void _insert() {
    if (!_canInsert) return;
    Navigator.of(
      context,
    ).pop(_ComposerLinkDraft(url: _url.text.trim(), anchor: _anchor.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('composer-link-dialog'),
    title: const Text('Insert link'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('composer-link-url'),
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _insert(),
            decoration: const InputDecoration(labelText: 'URL'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('composer-link-anchor'),
            controller: _anchor,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _insert(),
            decoration: const InputDecoration(labelText: 'Text'),
          ),
        ],
      ),
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        onPressed: () => Navigator.of(context).pop(),
      ),
      DButton(
        key: const ValueKey('composer-link-insert'),
        label: const Text('Insert link'),
        onPressed: _canInsert ? _insert : null,
        variant: DButtonVariant.primary,
      ),
    ],
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
