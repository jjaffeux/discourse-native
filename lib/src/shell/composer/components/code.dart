import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../plugin_api/composer_syntax.dart';
import '../component_artwork.dart';
import '../controller.dart';
import '../projected_component_input.dart';
import 'code_source.dart';

void insertComposerCodeBlock(ComposerController composer) {
  if (!composer.isCurrent || !composer.isEditing || composer.target.isPlugin) {
    return;
  }
  final value = composer.value;
  if (!value.composing.isCollapsed) return;
  final selection = value.selection;
  final selected = selection.isValid ? selection.textInside(value.text) : '';
  if (!composer.insertBlock(
    expectedValue: value,
    markdown: composerCodeMarkdown(
      selected,
      newline: value.text.contains('\r\n') ? '\r\n' : '\n',
    ),
  )) {
    return;
  }
  final inserted = composer.value;
  final start = selection.isValid ? selection.start : value.text.length;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!composer.isCurrent ||
        !composer.isEditing ||
        composer.value != inserted) {
      return;
    }
    for (final occurrence in composer.text.syntaxBlocks) {
      if (occurrence.projection case final ComposerCodeProjection projection
          when occurrence.start >= start &&
              occurrence.end <= inserted.selection.extentOffset) {
        projection.focus();
        break;
      }
    }
  });
}

final class ComposerCodePolicy implements ComposerSyntaxPolicy {
  const ComposerCodePolicy(this.composer);
  final ComposerController composer;
  @override
  ComposerSyntaxKind get kind => ComposerSyntaxKind(
    owner: const PluginId('core'),
    name: 'code-block',
    label: appL10n.codeBlock,
  );
  @override
  Object get projectionState => composer.isEditing;
  @override
  TextInputFormatter get inputFormatter => const ComposerCodeInputFormatter();
  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final block in parseComposerCodeBlocks(source))
      // Mermaid's existing diagram component owns these fences.
      if (block.language.toLowerCase() != 'mermaid')
        ComposerCodeProjection(composer, block),
  ];
}

final class ComposerCodeProjection
    implements ComposerAtomicSelectionProjection {
  ComposerCodeProjection(this.composer, this.block);
  final ComposerController composer;
  final ComposerCodeBlock block;
  GlobalKey? _editorKey;
  @override
  int get start => block.start;
  @override
  int get end => block.end;
  @override
  String get source => block.source;
  @override
  bool get supportsHover => false;
  @override
  bool get protectsAdjacentDelete => true;
  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      document.isComposingRangeValid &&
      !document.composing.isCollapsed &&
      document.composing.start < end &&
      document.composing.end > start;
  @override
  int caretAfter(String document) => document.startsWith('\r\n', end)
      ? end + 2
      : document.startsWith('\n', end)
      ? end + 1
      : end;
  @override
  TextEditingValue moveCaretAfter(
    TextEditingValue document,
  ) => document.copyWith(
    text: end == document.text.length ? '${document.text}\n' : document.text,
    selection: TextSelection.collapsed(
      offset: end == document.text.length ? end + 1 : caretAfter(document.text),
    ),
    composing: TextRange.empty,
  );
  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    _editorKey = context.pillKey;
    final hiddenEnd = source.length - (context.followedByLineBreak ? 0 : 1);
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: context.baseStyle,
        child: composer.artwork.codeBlock(
          key: context.pillKey,
          composer: composer,
          block: block,
          highlighted: context.highlighted,
          onSelect: composer.isEditing ? select : null,
        ),
      ),
      TextSpan(
        text: source.substring(1, hiddenEnd),
        semanticsLabel: '\u200B' * (hiddenEnd - 1),
        style: const TextStyle(
          fontSize: 0,
          height: 0,
          letterSpacing: 0,
          color: Colors.transparent,
        ),
      ),
      if (!context.followedByLineBreak)
        TextSpan(
          text: '\n',
          style: context.baseStyle.copyWith(color: Colors.transparent),
        ),
    ];
  }

  void focus() {
    if (_editorKey?.currentState case final ComposerComponentEditor editor) {
      editor.edit();
    }
  }

  void select() {
    if (!composer.isCurrent || !composer.isEditing) return;
    final text = composer.text;
    final occurrence = text.syntaxAtOffset(start);
    if (occurrence == null || occurrence.source != source) return;
    text.releaseSyntaxPointerEdit(occurrence);
    composer.autocomplete.dismiss();
    text.clearKeyboardPillSelection();
    text.selection = TextSelection(baseOffset: start, extentOffset: end);
    text.selectPillForKeyboard(ComposerSyntaxInput(occurrence));
    composer.requestFocus();
  }

  @override
  void edit(BuildContext context, ComposerEditorHost editor) => focus();
  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (replaceComposerCodeBlock(editor, block, '')) editor.requestFocus();
  }
}

bool replaceComposerCodeBlock(
  ComposerEditorHost editor,
  ComposerCodeBlock block,
  String source,
) {
  if (!editor.isCurrent || !editor.isEditing) return false;
  final current = editor.value;
  if (block.end > current.text.length ||
      current.text.substring(block.start, block.end) != block.source) {
    return false;
  }
  return editor.commitText(
    expectedText: current.text,
    value: TextEditingValue(
      text: current.text.replaceRange(block.start, block.end, source),
      selection: TextSelection.collapsed(offset: block.start + source.length),
    ),
  );
}
