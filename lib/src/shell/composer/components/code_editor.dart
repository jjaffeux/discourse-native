import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../foundation/icons/d_icons.dart';
import '../../code_block.dart';
import '../component_artwork.dart';
import '../controller.dart';
import '../embedded_editor.dart';
import 'code.dart';
import 'code_source.dart';

/// Native code editing inside the draft; fences remain in canonical Markdown.
class ComposerCodeBlockEditor extends StatefulWidget {
  const ComposerCodeBlockEditor({
    super.key,
    required this.composer,
    required this.block,
  });
  final ComposerController composer;
  final ComposerCodeBlock block;
  @override
  State<ComposerCodeBlockEditor> createState() =>
      _ComposerCodeBlockEditorState();
}

class _ComposerCodeBlockEditorState extends State<ComposerCodeBlockEditor>
    implements ComposerComponentEditor {
  late ComposerCodeBlock _block = widget.block;
  late final _controller = DCodeEditingController(
    text: _body,
    language: _block.language,
  );
  final _focus = FocusNode();
  bool _synchronizing = false;
  late TextEditingValue _previousValue;
  String? _beforeEnter;
  bool _observationScheduled = false;

  @override
  void initState() {
    super.initState();
    _previousValue = _controller.value;
    _controller.addListener(_scheduleObservation);
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    _beforeEnter = null;
    _previousValue = _controller.value;
  }

  void _scheduleObservation() {
    if (_observationScheduled) return;
    _observationScheduled = true;
    scheduleMicrotask(() {
      _observationScheduled = false;
      if (mounted) _observeCode();
    });
  }

  bool _atCodeEnd(TextEditingValue value) =>
      value.selection.isValid &&
      value.selection.isCollapsed &&
      value.selection.extentOffset <= value.text.length &&
      !value.text
          .substring(value.selection.extentOffset)
          .contains(RegExp(r'[^ \t]'));

  void _observeCode() {
    final value = _controller.value;
    final previous = _previousValue;
    if (value.text == previous.text &&
        value.selection.baseOffset == previous.selection.baseOffset &&
        value.selection.extentOffset == previous.selection.extentOffset &&
        value.composing == previous.composing) {
      _previousValue = value;
      return;
    }
    _previousValue = value;
    final beforeEnter = _beforeEnter;
    _beforeEnter = null;
    if (_synchronizing ||
        !_focus.hasFocus ||
        !widget.composer.isEditing ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        !previous.composing.isCollapsed ||
        !value.composing.isCollapsed ||
        !_atCodeEnd(previous) ||
        !_atCodeEnd(value)) {
      return;
    }
    final caret = previous.selection.extentOffset;
    final added = value.text.length - previous.text.length;
    if (added <= 0 ||
        !value.text.startsWith(previous.text.substring(0, caret)) ||
        value.text.substring(caret + added) != previous.text.substring(caret)) {
      return;
    }
    final inserted = value.text.substring(caret, caret + added);
    if (!inserted.startsWith('\n') ||
        inserted.substring(1).contains(RegExp(r'[^ \t]'))) {
      return;
    }
    if (beforeEnter == null) {
      _beforeEnter = previous.text;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_focus.hasFocus ||
          _controller.text != value.text ||
          _controller.selection.baseOffset != value.selection.baseOffset ||
          _controller.selection.extentOffset != value.selection.extentOffset ||
          !_controller.value.composing.isCollapsed) {
        return;
      }
      _controller.value = TextEditingValue(
        text: beforeEnter,
        selection: TextSelection.collapsed(offset: beforeEnter.length),
      );
      _replace(_block.withBody(beforeEnter));
      _finish();
    });
  }

  String get _body => _block.body.replaceAll('\r\n', '\n');
  String get _language => switch (_block.language) {
    '' || 'plain' || 'plaintext' || 'nohighlight' => 'text',
    final language => language,
  };

  @override
  void didUpdateWidget(ComposerCodeBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _block = widget.block;
    _synchronizing = true;
    if (_controller.text != _body) {
      _beforeEnter = null;
      _controller.value = TextEditingValue(
        text: _body,
        selection: TextSelection.collapsed(
          offset: _controller.selection.extentOffset.clamp(0, _body.length),
        ),
      );
      _previousValue = _controller.value;
    }
    if (oldWidget.block.language != _block.language) {
      _controller.language = highlightMode(_body, _block.language);
    }
    _synchronizing = false;
  }

  @override
  void dispose() {
    _controller.removeListener(_scheduleObservation);
    _focus.removeListener(_focusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void edit() => _focus.requestFocus();
  void _replace(String source) {
    if (_synchronizing || source == _block.source) return;
    final next = parseComposerCodeBlocks(source).single;
    if (replaceComposerCodeBlock(widget.composer, _block, source)) {
      _block = ComposerCodeBlock(
        start: _block.start,
        source: next.source,
        bodyStart: next.bodyStart,
        bodyEnd: next.bodyEnd,
        fence: next.fence,
        infoStart: next.infoStart,
        infoEnd: next.infoEnd,
        closingStart: next.closingStart,
        closingLength: next.closingLength,
      );
      setState(() {});
    }
  }

  void _finish() {
    if (!widget.composer.isCurrent || !widget.composer.isEditing) return;
    final text = widget.composer.text;
    final occurrence = text.syntaxAtOffset(_block.start);
    if (occurrence == null || occurrence.projection.source != _block.source) {
      return;
    }
    text.releaseSyntaxPointerEdit(occurrence);
    final projection = ComposerCodeProjection(widget.composer, _block);
    widget.composer.commitText(
      expectedText: widget.composer.value.text,
      value: projection.moveCaretAfter(widget.composer.value),
    );
    widget.composer.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final languages = <String>{
      _language,
      'text',
      'bash',
      'c',
      'cpp',
      'csharp',
      'css',
      'dart',
      'diff',
      'go',
      'html',
      'java',
      'javascript',
      'json',
      'kotlin',
      'markdown',
      'php',
      'python',
      'ruby',
      'rust',
      'sql',
      'swift',
      'typescript',
      'xml',
      'yaml',
    };
    String label(String language) => switch (language) {
      '' ||
      'text' ||
      'plain' ||
      'plaintext' ||
      'nohighlight' => context.l10n.plainText,
      _ => codeLanguageLabel(language),
    };
    final codeTheme = Theme.of(context);
    // The shared source projection already reserves the outer caret gap.
    return SizedBox(
      width: double.infinity,
      child: Theme(
        data: codeTheme,
        child: ComposerEmbeddedEditor(
          owner: widget.composer,
          scrollController: widget.composer.text.imageScrollController,
          semanticLabel: context.l10n.codeBlock,
          child: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _finish();
                return KeyEventResult.handled;
              }
              // Formatting shortcuts belong to prose, not the source editor.
              if (event is KeyDownEvent &&
                  (HardwareKeyboard.instance.isMetaPressed ||
                      HardwareKeyboard.instance.isControlPressed) &&
                  [
                    LogicalKeyboardKey.keyB,
                    LogicalKeyboardKey.keyI,
                    LogicalKeyboardKey.keyE,
                    LogicalKeyboardKey.keyL,
                  ].contains(event.logicalKey)) {
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: DCard(
              variant: DCardVariant.well,
              spacing: 0,
              border: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DSpacing.xs,
                        DSpacing.xs,
                        DSpacing.xs,
                        0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: DSelect<String>(
                              key: const ValueKey('composer-code-language'),
                              value: _language,
                              semanticLabel: context.l10n.language,
                              size: DSelectSize.chip,
                              triggerBuilder: (context, state, _) => DButton(
                                variant: DButtonVariant.ghost,
                                size: DButtonSize.chip,
                                focusNode: state.focusNode,
                                hasPopup: true,
                                expanded: state.open,
                                icon: const DIcon(DIcons.chevronDown),
                                iconPosition: DButtonIconPosition.end,
                                onPressed: state.enabled ? state.toggle : null,
                                label: Text(label(_language)),
                              ),
                              enabled: widget.composer.isEditing,
                              entries: [
                                for (final language in languages)
                                  DSelectItem(
                                    value: language,
                                    textValue: label(language),
                                    child: Text(label(language)),
                                  ),
                              ],
                              onChanged: (language) {
                                if (language != null) {
                                  _replace(_block.withLanguage(language));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: (24 + _body.split('\n').length * 26.0).clamp(
                      56,
                      320,
                    ),
                    child: DCodeEditor(
                      backgroundColor: Colors.transparent,
                      controller: _controller,
                      focusNode: _focus,
                      readOnly: !widget.composer.isEditing,
                      onChanged: (body) => _replace(_block.withBody(body)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
