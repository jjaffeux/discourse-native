import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../plugin_api/composer_syntax.dart';
import '../component_editing_host.dart';
import '../component_editor.dart';
import 'details_source.dart';

ComposerSyntaxKind get composerDetailsSyntaxKind => ComposerSyntaxKind(
  owner: const PluginId('core'),
  name: 'details',
  label: appL10n.details,
);

void insertComposerDetails(ComposerComponentEditingHost composer) {
  if (!composer.isCurrent || !composer.isEditing || composer.isPluginTarget) {
    return;
  }
  final value = composer.value;
  if (!value.composing.isCollapsed) return;
  final selection = value.selection;
  final selected = selection.isValid ? selection.textInside(value.text) : '';
  if (!composer.insertBlock(
    expectedValue: value,
    markdown: '[details]\n$selected\n[/details]',
  )) {
    return;
  }
  final inserted = composer.value;
  final start = selection.isValid ? selection.start : value.text.length;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!composer.isEditing || composer.value != inserted) return;
    for (final occurrence in composer.text.syntaxBlocks) {
      final projection = occurrence.projection;
      if (occurrence.start >= start &&
          occurrence.end <= inserted.selection.extentOffset &&
          projection is _DetailsProjection) {
        projection.focusSummary();
        break;
      }
    }
  });
}

final class ComposerDetailsPolicy implements ComposerSyntaxPolicy {
  const ComposerDetailsPolicy(this.composer, this.render);
  final Widget Function(ComposerSyntaxRenderContext, ComposerDetailsBlock)
  render;
  final ComposerComponentEditingHost composer;
  @override
  ComposerSyntaxKind get kind => composerDetailsSyntaxKind;
  @override
  Object get projectionState => composer.isEditing;
  @override
  TextInputFormatter get inputFormatter =>
      const ComposerDetailsInputFormatter();
  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final block in parseComposerDetails(source))
      _DetailsProjection(composer, block, render),
  ];
}

final class _DetailsProjection
    implements
        ComposerInteractiveSyntaxProjection,
        ComposerBlockSyntaxProjection {
  _DetailsProjection(this.composer, this.block, this.render);
  final Widget Function(ComposerSyntaxRenderContext, ComposerDetailsBlock)
  render;
  final ComposerComponentEditingHost composer;
  final ComposerDetailsBlock block;
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
  int caretAfter(String document) {
    if (document.startsWith('\r\n', end)) return end + 2;
    return document.startsWith('\n', end) ? end + 1 : end;
  }

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: caretAfter(document.text)),
        composing: TextRange.empty,
      );
  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    _editorKey = context.pillKey;
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: context.baseStyle,
        child: render(context, block),
      ),
      TextSpan(
        text: '\n',
        style: context.baseStyle.copyWith(color: Colors.transparent),
      ),
      TextSpan(
        text: source.substring(2),
        semanticsLabel: '\u200B' * (source.length - 2),
        style: const TextStyle(
          fontSize: 0,
          height: 0,
          letterSpacing: 0,
          color: Colors.transparent,
        ),
      ),
    ];
  }

  @override
  void edit(BuildContext context, ComposerEditorHost editor) => focusSummary();

  void focusSummary() {
    if (_editorKey?.currentState case final ComposerComponentEditor editor) {
      editor.edit();
    }
  }

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    replaceComposerDetails(editor, block, '');
  }
}

bool replaceComposerDetails(
  ComposerEditorHost editor,
  ComposerDetailsBlock block,
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
