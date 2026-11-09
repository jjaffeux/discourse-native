import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart' as editor;
import 'package:highlight/highlight.dart' show Mode;

import '../../theme/tokens.dart';
import '../foundation/code_editor_theme.dart';
import '../foundation/code_syntax.dart';
import '../foundation/code_typography.dart';
import '../foundation/control_style.dart';
import 'd_scroll_area.dart';
import 'd_scroll_behavior.dart';

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
    this.backgroundColor,
    this._semanticLabel,
  });

  final DCodeEditingController controller;
  final FocusNode? focusNode;

  /// Called on text changes, including controller commands and external edits.
  final ValueChanged<String>? onChanged;
  final bool? readOnly;

  /// A containing Native well can own the fill while the editor keeps its syntax.
  final Color? backgroundColor;
  final String? _semanticLabel;
  String get semanticLabel => _semanticLabel ?? appL10n.codeEditor;

  @override
  State<DCodeEditor> createState() => _DCodeEditorState();
}

class _DCodeEditorState extends State<DCodeEditor> {
  late String _text;
  late int _gutterDigits;
  ScrollController? _verticalScroll;
  @override
  void initState() {
    super.initState();
    _text = widget.controller.text;
    _gutterDigits = widget.controller.code.lines.length.toString().length;
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
    final digits = widget.controller.code.lines.length.toString().length;
    if (digits != _gutterDigits) setState(() => _gutterDigits = digits);
    widget.onChanged?.call(text);
  }

  void _captureVerticalScroll(ScrollController controller) {
    if (identical(_verticalScroll, controller)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || identical(_verticalScroll, controller)) return;
      setState(() => _verticalScroll = controller);
    });
  }

  @override
  void didUpdateWidget(DCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _text = widget.controller.text;
      _gutterDigits = widget.controller.code.lines.length.toString().length;
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
    final syntax = codeEditorStyles(theme);
    if (widget.backgroundColor case final color?) {
      syntax['root'] = syntax['root']!.copyWith(backgroundColor: color);
    }
    final style = monospaceTextStyle.copyWith(
      fontSize: DControlStyle.labelFontSize,
      height: 1.8,
      color: tokens.foreground,
    );
    final numberPainter = TextPainter(
      text: TextSpan(text: '9' * _gutterDigits, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Upstream subtracts 16px for each disabled error and folding column.
    final gutterWidth = numberPainter.width.ceilToDouble() + 12 + 32;
    numberPainter.dispose();
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DScrollBar(
          controller: _verticalScroll,
          showScrollbar: _verticalScroll != null,
          backgroundColor:
              widget.backgroundColor ?? codeEditorColors(theme).blockBackground,
          notificationDepth: 1,
          child: ScrollConfiguration(
            behavior: _CodeEditorScrollBehavior(
              delegate: ScrollConfiguration.of(context),
              editingController: widget.controller,
              onVerticalScroll: _captureVerticalScroll,
            ),
            child: editor.CodeTheme(
              data: editor.CodeThemeData(styles: syntax),
              child: editor.CodeField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                readOnly: widget.controller.readOnly,
                expands: true,
                wrap: false,
                background:
                    widget.backgroundColor ??
                    codeEditorColors(theme).blockBackground,
                padding: const EdgeInsets.symmetric(vertical: DSpacing.md),
                textStyle: style,
                cursorColor: tokens.foreground,
                gutterStyle: editor.GutterStyle(
                  width: gutterWidth,
                  margin: 12,
                  showErrors: false,
                  showFoldingHandles: false,
                  textStyle: style.copyWith(color: tokens.mutedForeground),
                ),
                textSelectionTheme: TextSelectionThemeData(
                  selectionColor: theme.colorScheme.primary.withValues(
                    alpha: .28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeEditorScrollBehavior extends DScrollBehavior {
  const _CodeEditorScrollBehavior({
    required super.delegate,
    required this.editingController,
    required this.onVerticalScroll,
  });

  final DCodeEditingController editingController;
  final ValueChanged<ScrollController> onVerticalScroll;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal) {
      return DScrollBar(
        controller: details.controller,
        axis: Axis.horizontal,
        thumbVisibility: false,
        child: child,
      );
    }
    final controller = details.controller;
    if (controller != null &&
        identical(
          context.findAncestorWidgetOfExactType<EditableText>()?.controller,
          editingController,
        )) {
      onVerticalScroll(controller);
    }
    return child;
  }
}
