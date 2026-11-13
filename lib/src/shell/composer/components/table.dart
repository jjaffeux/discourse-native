import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../plugin_api/composer_syntax.dart';
import '../component_editor.dart';
import 'table_source.dart';

ComposerSyntaxKind get composerTableSyntaxKind => ComposerSyntaxKind(
  owner: const PluginId('core'),
  name: 'table',
  label: appL10n.table,
);

void insertComposerTable(ComposerEditorHost composer) {
  if (!composer.isCurrent || !composer.isEditing || composer.isPluginTarget) {
    return;
  }
  composer.insertBlock(
    expectedValue: composer.value,
    markdown: appL10n.column1Column2,
  );
  composer.requestFocus();
}

final class ComposerTablePolicy implements ComposerSyntaxPolicy {
  const ComposerTablePolicy(this.editor, this.renderTable);
  final ComposerEditorHost editor;
  final Widget Function(ComposerSyntaxRenderContext, ComposerTableBlock)
  renderTable;

  @override
  ComposerSyntaxKind get kind => composerTableSyntaxKind;
  @override
  Object get projectionState => editor.isEditing;
  @override
  TextInputFormatter get inputFormatter => const ComposerTableInputFormatter();
  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final table in parseComposerTables(source))
      _TableProjection(renderTable, table),
  ];
}

final class _TableProjection
    implements
        ComposerInteractiveSyntaxProjection,
        ComposerBlockSyntaxProjection {
  _TableProjection(this.renderTable, this.table);
  final Widget Function(ComposerSyntaxRenderContext, ComposerTableBlock)
  renderTable;
  final ComposerTableBlock table;
  GlobalKey? _editorKey;
  @override
  int get start => table.start;
  @override
  int get end => table.end;
  @override
  String get source => table.source;
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
  int caretAfter(String document) =>
      end < document.length && document[end] == '\n' ? end + 1 : end;
  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) {
    // The visual line below a terminal table still maps to its last source
    // row. Give body text its own line before placing the caret there.
    final text = end == document.text.length
        ? '${document.text}\n'
        : document.text;
    return document.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: caretAfter(text)),
      composing: TextRange.empty,
    );
  }

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    _editorKey = context.pillKey;
    final hiddenEnd = source.length - (context.followedByLineBreak ? 0 : 1);
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: context.baseStyle,
        child: renderTable(context, table),
      ),
      // The source's real newline ends the widget line when present. Hidden
      // table rows must not introduce another apparent typing line below it.
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

  @override
  void edit(BuildContext context, ComposerEditorHost editor) {
    if (_editorKey?.currentState case final ComposerComponentEditor editor) {
      editor.edit();
    }
  }

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (!editor.isCurrent || !editor.isEditing) return;
    final current = editor.value;
    if (end > current.text.length ||
        current.text.substring(start, end) != source) {
      return;
    }
    editor.commitText(
      expectedText: current.text,
      value: TextEditingValue(
        text: current.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
  }
}
