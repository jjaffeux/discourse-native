import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/composer_syntax.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import '../ui/foundation/code_editor_theme.dart';
import 'code_block.dart';
import 'composer_block_selection.dart';
import 'composer_code_blocks.dart';
import 'composer_controller.dart';
import 'composer_embedded_editor.dart';
import 'syntax.dart';

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
      if (occurrence.projection case final _CodeProjection projection
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
        _CodeProjection(composer, block),
  ];
}

final class _CodeProjection implements ComposerInteractiveSyntaxProjection {
  _CodeProjection(this.composer, this.block);
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
        child: ComposerBlockSelection(
          selected: context.highlighted,
          child: ComposerCodeBlockEditor(
            key: context.pillKey,
            composer: composer,
            block: block,
          ),
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
    if (_editorKey?.currentState
        case final _ComposerCodeBlockEditorState state) {
      state.edit();
    }
  }

  @override
  void edit(BuildContext context, ComposerEditorHost editor) => focus();
  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (_replaceCode(editor, block, '')) editor.requestFocus();
  }
}

bool _replaceCode(
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

class _ComposerCodeBlockEditorState extends State<ComposerCodeBlockEditor> {
  late ComposerCodeBlock _block = widget.block;
  late final _controller = DCodeEditingController(
    text: _body,
    language: _block.language,
  );
  final _focus = FocusNode();
  bool _synchronizing = false;
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
      _controller.value = TextEditingValue(
        text: _body,
        selection: TextSelection.collapsed(
          offset: _controller.selection.extentOffset.clamp(0, _body.length),
        ),
      );
    }
    if (oldWidget.block.language != _block.language) {
      _controller.language = highlightMode(_body, _block.language);
    }
    _synchronizing = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void edit() => _focus.requestFocus();
  void _replace(String source) {
    if (_synchronizing || source == _block.source) return;
    final next = parseComposerCodeBlocks(source).single;
    if (_replaceCode(widget.composer, _block, source)) {
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
    final projection = _CodeProjection(widget.composer, _block);
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
    final theme = Theme.of(context);
    final codeTheme = AppTheme.forBrightness(
      Brightness.dark,
      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
    ).copyWith(platform: theme.platform);
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
              spacing: 0,
              border: false,
              backgroundColor: codeEditorColors(codeTheme).blockBackground,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.all(DSpacing.xs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: DSelect<String>(
                              key: const ValueKey('composer-code-language'),
                              value: _language,
                              semanticLabel: context.l10n.language,
                              size: DSelectSize.small,
                              triggerBuilder: (context, state, _) => DButton(
                                variant: DButtonVariant.transparentBackground,
                                size: DButtonSize.small,
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
