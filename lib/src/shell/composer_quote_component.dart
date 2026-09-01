import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';

import '../plugin_api/composer_component.dart';
import '../plugin_api/composer_syntax.dart';
import 'composer_quotes.dart';

const composerQuoteComponentKind = ComposerSyntaxKind(
  owner: PluginId('core'),
  name: 'quote',
);

/// Core's atomic block declaration for a complete Markdown quote.
///
/// [resolveQuoteContents] has the same precedence as the live resolver on the
/// legacy composer, followed by [formatQuoteContents] and the parsed contents.
ComposerComponent<ComposerQuoteBlock> composerQuoteComponent({
  ComposerQuoteContentsFormatter? formatQuoteContents,
  ComposerQuoteContentsResolver? resolveQuoteContents,
}) => ComposerComponent<ComposerQuoteBlock>.block(
  kind: composerQuoteComponentKind,
  find: (markdown) => parseComposerQuotes(markdown).map(
    (block) => ComposerComponentCandidate(
      range: TextRange(start: block.start, end: block.end),
      value: block,
    ),
  ),
  builder: (context, component) {
    final block = component.value;
    return ComposerQuotePreview(
      block: block,
      contents:
          resolveQuoteContents?.call(block) ??
          formatQuoteContents?.call(block) ??
          block.contents,
      baseStyle: component.baseStyle,
    );
  },
  semanticLabel: (context, component) {
    final title = component.value.title;
    return title == null ? 'Quote' : 'Quote from $title';
  },
  onRemove: _removeQuote,
);

void _removeQuote(
  BuildContext context,
  ComposerEditorHost editor,
  ComposerComponentInstance<ComposerQuoteBlock> component,
) {
  if (!editor.isCurrent) return;
  final current = editor.value;
  final range = component.range;
  if (!range.isValid ||
      !range.isNormalized ||
      range.isCollapsed ||
      range.end > current.text.length ||
      current.text.substring(range.start, range.end) != component.source) {
    return;
  }

  final next = TextEditingValue(
    text: current.text.replaceRange(range.start, range.end, ''),
    selection: TextSelection.collapsed(offset: range.start),
  );
  if (editor.commitText(expectedText: current.text, value: next)) {
    editor.requestFocus();
  }
}
