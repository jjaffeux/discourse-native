import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mermaid_composer_source.dart';

export 'mermaid_composer_source.dart';

const mermaidComposerKind = ComposerSyntaxKind(
  owner: PluginId('discourse-mermaid'),
  name: 'chart',
);

class MermaidComposerPolicy implements ComposerSyntaxPolicy {
  const MermaidComposerPolicy(this.readEditor);
  final ComposerEditorHost Function()? readEditor;
  @override
  ComposerSyntaxKind get kind => mermaidComposerKind;
  @override
  Object? get projectionState => null;
  @override
  TextInputFormatter? get inputFormatter => null;
  @override
  List<ComposerSyntaxProjection> parse(String source) => readEditor == null
      ? []
      : [
          for (final block in parseMermaidComposerBlocks(source))
            _MermaidProjection(readEditor!, block),
        ];
}

class _MermaidProjection
    implements
        ComposerInteractiveSyntaxProjection,
        ComposerBlockSyntaxProjection {
  _MermaidProjection(this.readEditor, this.block);
  final ComposerEditorHost Function() readEditor;
  final MermaidComposerBlock block;
  GlobalKey? _key;
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
  TextEditingValue moveCaretAfter(TextEditingValue document) {
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
    _key = context.pillKey;
    final hiddenEnd = source.length - (context.followedByLineBreak ? 0 : 1);
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: context.baseStyle,
        child: LayoutBuilder(
          builder: (contextWidget, constraints) {
            final margin =
                (contextWidget
                        .findAncestorWidgetOfExactType<EditableText>()
                        ?.cursorWidth ??
                    2) +
                1;
            return SizedBox(
              width: (constraints.maxWidth - margin).clamp(0, double.infinity),
              child: ComposerBlockSelection(
                selected: context.highlighted,
                child: MediaQuery.withNoTextScaling(
                  child: MermaidComposerEditor(
                    key: context.pillKey,
                    editor: context.editor ?? readEditor(),
                    scrollController: context.scrollController,
                    block: block,
                  ),
                ),
              ),
            );
          },
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

  @override
  void edit(BuildContext context, ComposerEditorHost editor) {
    if (_key?.currentState case final _MermaidComposerEditorState state) {
      state.focus();
    }
  }

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    final current = editor.value;
    if (!editor.isCurrent ||
        !editor.isEditing ||
        end > current.text.length ||
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

class MermaidComposerEditor extends StatefulWidget {
  const MermaidComposerEditor({
    super.key,
    required this.editor,
    required this.block,
    this.scrollController,
  });
  final ComposerEditorHost editor;
  final MermaidComposerBlock block;
  final ScrollController? scrollController;
  @override
  State<MermaidComposerEditor> createState() => _MermaidComposerEditorState();
}

class _MermaidComposerEditorState extends State<MermaidComposerEditor> {
  late MermaidComposerBlock _block = widget.block;
  final _key = GlobalKey<DMermaidEditorState>();
  void focus() => _key.currentState?.requestFocus();
  @override
  void didUpdateWidget(MermaidComposerEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _block = widget.block;
  }

  void _replace(String code) {
    final editor = widget.editor;
    final current = editor.value;
    if (!editor.isCurrent ||
        !editor.isEditing ||
        _block.end > current.text.length ||
        current.text.substring(_block.start, _block.end) != _block.source) {
      setState(() {});
      return;
    }
    final replacement = _block.replaceCode(code);
    final next = current.text.replaceRange(
      _block.start,
      _block.end,
      replacement,
    );
    final updated = parseMermaidComposerBlocks(next)
        .where((b) => b.start == _block.start && b.source == replacement)
        .firstOrNull;
    if (updated == null) {
      setState(() {});
      return;
    }
    if (editor.commitText(
      expectedText: current.text,
      value: TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: updated.end),
      ),
    )) {
      _block = updated;
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => ComposerEmbeddedEditor(
    owner: widget.editor,
    scrollController: widget.scrollController,
    semanticLabel: context.l10n.mermaidChartEditor,
    child: DMermaidEditor(
      key: _key,
      source: _block.code,
      onChanged: _replace,
      readOnly: !widget.editor.isCurrent || !widget.editor.isEditing,
    ),
  );
}
