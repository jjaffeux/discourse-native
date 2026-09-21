import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../plugin_api/site_plugin_api.dart';
import '../../shell/composer_block_selection.dart';
import '../../shell/composer_embedded_editor.dart';

const mermaidComposerKind = ComposerSyntaxKind(
  owner: PluginId('discourse-mermaid'),
  name: 'chart',
);

/// A complete top-level fence; original delimiters and whitespace stay intact.
class MermaidComposerBlock {
  const MermaidComposerBlock(
    this.start,
    this.end,
    this.source,
    this.bodyStart,
    this.bodyEnd,
  );
  final int start, end, bodyStart, bodyEnd;
  final String source;
  String get code => source.substring(bodyStart, bodyEnd);

  String replaceCode(String code) {
    var opening = source.substring(0, bodyStart);
    var closing = source.substring(bodyEnd);
    final fence = RegExp(r'`{3,}|~{3,}').firstMatch(opening)!.group(0)!;
    final candidates = RegExp(fence[0] == '`' ? r'`+' : r'~+').allMatches(code);
    var length = fence.length;
    for (final match in candidates) {
      if (match.group(0)!.length >= length) length = match.group(0)!.length + 1;
    }
    if (length != fence.length) {
      final replacement = fence[0] * length;
      opening = opening.replaceFirst(fence, replacement);
      closing = closing.replaceFirst(
        RegExp(fence[0] == '`' ? r'`{3,}' : r'~{3,}'),
        replacement,
      );
    }
    if (!closing.startsWith('\n') && !closing.startsWith('\r\n')) {
      closing = '${opening.endsWith('\r\n') ? '\r\n' : '\n'}$closing';
    }
    return '$opening$code$closing';
  }
}

/// Scan all fences so examples nested inside another code block stay literal.
List<MermaidComposerBlock> parseMermaidComposerBlocks(String source) {
  final lines = RegExp(
    r'[^\n]*(?:\n|$)',
  ).allMatches(source).where((m) => m.start < source.length).toList();
  final result = <MermaidComposerBlock>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final open = RegExp(
      r'^ {0,3}(`{3,}|~{3,})([^\r\n]*)\r?\n$',
    ).firstMatch(line.group(0)!);
    if (open == null) continue;
    final fence = open.group(1)!;
    final info = open.group(2)!.trim();
    if (fence[0] == '`' && info.contains('`')) continue;
    final close = RegExp(
      '^ {0,3}${fence[0]}{${fence.length},}[ \\t]*\\r?\\n?\$',
    );
    var j = i + 1;
    while (j < lines.length && !close.hasMatch(lines[j].group(0)!)) {
      j++;
    }
    if (j == lines.length) break;
    if (info == 'mermaid') {
      final end = lines[j].end - (source[lines[j].end - 1] == '\n' ? 1 : 0);
      var bodyEnd = lines[j].start;
      if (bodyEnd > line.end && source[bodyEnd - 1] == '\n') bodyEnd--;
      if (bodyEnd > line.end && source[bodyEnd - 1] == '\r') bodyEnd--;
      // Empty fences still need a separator when their first code is inserted.
      final blockSource = source.substring(line.start, end);
      result.add(
        MermaidComposerBlock(
          line.start,
          end,
          blockSource,
          line.end - line.start,
          bodyEnd - line.start,
        ),
      );
    }
    i = j;
  }
  return result;
}

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

class _MermaidProjection implements ComposerInteractiveSyntaxProjection {
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
  int caretAfter(String document) =>
      end < document.length && document[end] == '\n' ? end + 1 : end;
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
                    editor: readEditor(),
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
    semanticLabel: 'Mermaid chart editor',
    child: DMermaidEditor(
      key: _key,
      source: _block.code,
      onChanged: _replace,
      readOnly: !widget.editor.isCurrent || !widget.editor.isEditing,
    ),
  );
}
