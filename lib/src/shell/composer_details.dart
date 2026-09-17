import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/composer_syntax.dart';
import '../theme/d_icons.dart';
import 'composer_block_selection.dart';
import 'composer_controller.dart';
import 'composer_details_blocks.dart';
import 'composer_details_body_controller.dart';
import 'composer_embedded_editor.dart';
import 'composer_panel.dart';

const composerDetailsSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('core'),
  name: 'details',
);

void insertComposerDetails(ComposerController composer) {
  if (!composer.isCurrent || !composer.isEditing || composer.target.isPlugin) {
    return;
  }
  composer.insertBlock(
    expectedValue: composer.value,
    markdown: '[details="Summary"]\n\n[/details]',
  );
  composer.requestFocus();
}

final class ComposerDetailsPolicy implements ComposerSyntaxPolicy {
  const ComposerDetailsPolicy(this.composer);
  final ComposerController composer;
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
      _DetailsProjection(composer, block),
  ];
}

final class _DetailsProjection implements ComposerInteractiveSyntaxProjection {
  _DetailsProjection(this.composer, this.block);
  final ComposerController composer;
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
        child: ComposerBlockSelection(
          selected: context.highlighted,
          child: ComposerDetailsEditor(
            key: context.pillKey,
            composer: composer,
            block: block,
          ),
        ),
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
  void edit(BuildContext context, ComposerEditorHost editor) {
    if (_editorKey?.currentState case final _ComposerDetailsEditorState state) {
      state.edit();
    }
  }

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    _replaceDetails(editor, block, '');
  }
}

bool _replaceDetails(
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

/// Summary and rich body edits update the canonical block without its tags.
class ComposerDetailsEditor extends StatefulWidget {
  const ComposerDetailsEditor({
    super.key,
    required this.composer,
    required this.block,
  });
  final ComposerController composer;
  final ComposerDetailsBlock block;
  @override
  State<ComposerDetailsEditor> createState() => _ComposerDetailsEditorState();
}

class _ComposerDetailsEditorState extends State<ComposerDetailsEditor> {
  late ComposerDetailsBodyController _body = ComposerDetailsBodyController(
    widget.composer,
    widget.block,
  );
  ComposerDetailsBlock get _block => _body.block;
  late final _summary = TextEditingController(text: widget.block.summary);
  final _summaryFocus = FocusNode();
  final _accordion = DAccordionController<int>(initialValues: const [0]);
  String? _error;

  @override
  void didUpdateWidget(ComposerDetailsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.block.summary != widget.block.summary;
    if (!identical(_body.parent, widget.composer) || !_body.isCurrent) {
      final previous = _body;
      _body = ComposerDetailsBodyController(widget.composer, widget.block);
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    } else {
      _body.updateBlock(widget.block);
    }
    if (changed && _summary.text != _block.summary) {
      _summary.text = _block.summary;
    }
  }

  @override
  void dispose() {
    _summary.dispose();
    _body.dispose();
    _summaryFocus.dispose();
    _accordion.dispose();
    super.dispose();
  }

  void edit() {
    if (!widget.composer.isEditing) return;
    _accordion.open(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _summaryFocus.requestFocus();
    });
  }

  bool _change(String source) {
    if (source == _block.source) {
      if (_error != null) setState(() => _error = null);
      return true;
    }
    final blocks = parseComposerDetails(source);
    if (!_replaceDetails(widget.composer, _block, source)) return false;
    if (blocks.length != 1 || blocks.single.source != source) {
      // Incomplete nested markup remains canonical draft text. Let the outer
      // composer display it for correction rather than keeping unsaved input.
      widget.composer.requestFocus();
      return true;
    }
    final updated = parseComposerDetails(
      widget.composer.text.text,
    ).firstWhere((block) => block.start == _block.start);
    setState(() {
      _body.updateBlock(updated);
      _error = null;
    });
    return true;
  }

  void _changeSummary(String value) {
    try {
      _change(_block.withSummary(value));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.composer.requestFocus();
      return KeyEventResult.handled;
    }
    // The summary is plain text; body shortcuts belong to its rich editor.
    final keyboard = HardwareKeyboard.instance;
    if (_summaryFocus.hasFocus &&
        (keyboard.isMetaPressed || keyboard.isControlPressed) &&
        {
          LogicalKeyboardKey.keyB,
          LogicalKeyboardKey.keyI,
          LogicalKeyboardKey.keyE,
          LogicalKeyboardKey.keyL,
        }.contains(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => ComposerEmbeddedEditor(
    owner: widget.composer,
    scrollController: widget.composer.text.imageScrollController,
    semanticLabel: 'Details editor',
    child: _editor(context),
  );

  Widget _editor(BuildContext context) => ListenableBuilder(
    listenable: widget.composer,
    builder: (context, _) => Focus(
      onKeyEvent: _onKey,
      child: DAccordion<int>(
        controller: _accordion,
        keepMounted: true,
        onValuesChange: (values) {
          if (!values.contains(0) &&
              widget.composer.activeEditor != widget.composer) {
            widget.composer.requestFocus();
          }
        },
        children: [
          DAccordionItem<int>(
            value: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DAccordionHeader(
                        child: DAccordionTrigger(
                          child: Text(
                            _block.summary.isEmpty ? 'Details' : _block.summary,
                          ),
                        ),
                      ),
                    ),
                    DButton.iconOnly(
                      tooltip: 'Remove details',
                      variant: DButtonVariant.transparentBackground,
                      icon: const DIcon(DIcons.trashCan),
                      onPressed: widget.composer.isEditing
                          ? () {
                              if (_replaceDetails(
                                widget.composer,
                                _block,
                                '',
                              )) {
                                widget.composer.requestFocus();
                              }
                            }
                          : null,
                    ),
                  ],
                ),
                DAccordionContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DInput(
                        key: const ValueKey('details-summary'),
                        controller: _summary,
                        focusNode: _summaryFocus,
                        labelText: 'Summary',
                        errorText: _error,
                        enabled: widget.composer.isEditing,
                        onChanged: _changeSummary,
                      ),
                      const SizedBox(height: DSpacing.sm),
                      ComposerRichBodyEditor(
                        key: const ValueKey('details-body'),
                        composer: _body,
                        label: 'Hidden content',
                        hintText: 'Write the content to reveal…',
                        onExit: widget.composer.requestFocus,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
