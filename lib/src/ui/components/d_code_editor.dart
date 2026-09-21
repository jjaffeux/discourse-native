import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart' as editor;
import 'package:highlight/highlight.dart' show Mode;

import '../foundation/code_editor_theme.dart';
import '../foundation/code_syntax.dart';
import '../foundation/code_typography.dart';
import '../foundation/tokens.dart';

/// Native code controller. The creator owns and disposes it.
///
/// Uses the same highlighting engine as post code blocks. Unknown languages
/// remain editable as plain text; Mermaid has a lightweight authoring grammar.
class DCodeEditingController extends editor.CodeController {
  DCodeEditingController({
    String text = '',
    String? language,
    super.readOnly = false,
  }) : _readOnly = readOnly,
       super(
         text: text,
         language: language == 'mermaid'
             ? _mermaid
             : highlightMode(text, language),
       );
  bool _readOnly;
  @override
  bool get readOnly => _readOnly;
  set readOnly(bool value) => _readOnly = value;

  // Upstream insertStr moves the caret even when its text write is rejected.
  @override
  void insertStr(String str) {
    if (!readOnly && selection.isValid) super.insertStr(str);
  }

  @override
  void insertSelectedWord() {
    if (!readOnly) super.insertSelectedWord();
  }
}

final _mermaid = Mode(
  keywords:
      'flowchart graph sequenceDiagram classDiagram stateDiagram stateDiagram-v2 '
      'erDiagram gantt pie journey gitGraph mindmap timeline subgraph end '
      'direction TB TD BT LR RL participant actor loop alt else opt par and '
      'rect note Note over title section classDef class style linkStyle click',
  contains: [
    Mode(className: 'comment', begin: '%%', end: r'$'),
    Mode(className: 'string', begin: '"', end: '"'),
    Mode(className: 'number', begin: r'\b\d+(\.\d+)?\b'),
    Mode(className: 'operator', begin: r'[-=.]+>|<[-=.]+|---|:::|[{}\[\]()]'),
  ],
);

/// A bounded code editor with native selection, undo, indentation and gutters.
///
/// Place in a finite-height parent. [controller] and [focusNode] are borrowed;
/// this widget never disposes them. Horizontal scrolling preserves long lines.
/// The kit owns code typography, gutter geometry and live palette styling.
class DCodeEditor extends StatefulWidget {
  const DCodeEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.onChanged,
    this.readOnly,
    this.semanticLabel = 'Code editor',
  });

  final DCodeEditingController controller;
  final FocusNode? focusNode;

  /// Called on text changes, including controller commands and external edits.
  final ValueChanged<String>? onChanged;
  final bool? readOnly;
  final String semanticLabel;

  @override
  State<DCodeEditor> createState() => _DCodeEditorState();
}

class _DCodeEditorState extends State<DCodeEditor> {
  late String _text;
  @override
  void initState() {
    super.initState();
    _text = widget.controller.text;
    widget.controller.addListener(_changed);
    _readOnly();
  }

  void _readOnly() {
    if (widget.readOnly != null) widget.controller.readOnly = widget.readOnly!;
  }

  void _changed() {
    final text = widget.controller.text;
    if (text == _text) return;
    _text = text;
    widget.onChanged?.call(text);
  }

  @override
  void didUpdateWidget(DCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _text = widget.controller.text;
      widget.controller.addListener(_changed);
    }
    _readOnly();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final style = monospaceTextStyle.copyWith(
      fontSize: 13,
      height: 1.8,
      color: tokens.foreground,
    );
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: editor.CodeTheme(
          data: editor.CodeThemeData(styles: codeEditorStyles(theme)),
          child: editor.CodeField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            readOnly: widget.controller.readOnly,
            expands: true,
            wrap: false,
            background: codeEditorColors(theme).blockBackground,
            padding: const EdgeInsets.symmetric(vertical: DSpacing.md),
            textStyle: style,
            cursorColor: tokens.foreground,
            gutterStyle: editor.GutterStyle(
              width: 44,
              margin: 12,
              showErrors: false,
              showFoldingHandles: false,
              textStyle: style.copyWith(color: tokens.mutedForeground),
            ),
            textSelectionTheme: TextSelectionThemeData(
              selectionColor: theme.colorScheme.primary.withValues(alpha: .28),
            ),
          ),
        ),
      ),
    );
  }
}
