import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/composer_syntax.dart';
import '../theme/d_button.dart';
import 'composer_quotes.dart';
import 'markdown_highlight.dart';

const composerLinkSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('core'),
  name: 'link',
);

const composerLinkSyntaxPolicy = ComposerLinkSyntaxPolicy();

@immutable
class ComposerLinkBlock {
  const ComposerLinkBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.anchor,
    required this.url,
  });

  final int start;
  final int end;
  final String source;
  final String anchor;
  final String url;
}

List<ComposerLinkBlock> parseComposerLinks(
  String source, {
  CodeRanges? codeRanges,
}) {
  if (source.isEmpty) return const [];
  final code = codeRanges ?? CodeRanges.of(scanMarkdown(source));
  final links = <ComposerLinkBlock>[];
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
        _isEscaped(source, bracket) ||
        (start > 0 && source[start - 1] == '!')) {
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
    if (code.overlaps(start, end)) continue;
    links.add(
      ComposerLinkBlock(
        start: start,
        end: end,
        source: source.substring(start, end),
        anchor: source.substring(start + 1, bracket),
        url: source.substring(urlStart, close),
      ),
    );
  }

  return List.unmodifiable(links);
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
  const ComposerLinkSyntaxPolicy();

  @override
  ComposerSyntaxKind get kind => composerLinkSyntaxKind;

  @override
  Object? get projectionState => null;

  @override
  TextInputFormatter? get inputFormatter => null;

  @override
  List<ComposerSyntaxProjection> parse(String source) =>
      parseWithCodeRanges(source, CodeRanges.of(scanMarkdown(source)));

  List<ComposerSyntaxProjection> parseWithCodeRanges(
    String source,
    CodeRanges codeRanges,
  ) => [
    for (final block in parseComposerLinks(source, codeRanges: codeRanges))
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
    if (!selection.isValid) return false;
    if (selection.isCollapsed) {
      if (selection.extentOffset == start || selection.extentOffset == end) {
        return false;
      }
      return !suppressCollapsedCaret &&
          selection.extentOffset > start &&
          selection.extentOffset < end;
    }
    return selection.start < end && selection.end > start;
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
  bool get protectsAdjacentDelete => true;

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
