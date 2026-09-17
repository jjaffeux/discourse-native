import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/composer_syntax.dart';
import '../theme/d_icons.dart';
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
        // WidgetSpan already scales its whole child with the surrounding text.
        // Applying the inherited scaler again compounds it in every nested
        // editor, shrinking media space and enlarging text relative to prose.
        child: MediaQuery.withNoTextScaling(
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
  void edit(BuildContext context, ComposerEditorHost editor) => focusSummary();

  void focusSummary() {
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
  bool _open = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _summaryFocus.addListener(_activate);
  }

  void _activate() {
    if (_summaryFocus.hasFocus) {
      widget.composer.activateEmbeddedEditor(_body);
    }
  }

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
    super.dispose();
  }

  void edit() {
    if (!widget.composer.isEditing) return;
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _summaryFocus.requestFocus();
    });
  }

  void _focusBody() {
    if (!_body.isEditing) return;
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _body.isEditing) _body.requestFocus();
    });
  }

  void _leave({bool before = false}) {
    if (!widget.composer.isEditing) return;
    final text = widget.composer.text;
    var offset = before ? _block.start : _block.end;
    if (before && offset > 0 && text.text[offset - 1] == '\n') {
      offset--;
      if (offset > 0 && text.text[offset - 1] == '\r') offset--;
    } else if (before && offset == 0) {
      final newline = _block.source.contains('\r\n') ? '\r\n' : '\n';
      if (!widget.composer.commitText(
        expectedText: text.text,
        value: TextEditingValue(
          text: '$newline${text.text}',
          selection: const TextSelection.collapsed(offset: 0),
        ),
      )) {
        return;
      }
    } else if (!before) {
      if (text.text.startsWith('\r\n', offset)) {
        offset += 2;
      } else if (text.text.startsWith('\n', offset)) {
        offset++;
      } else if (offset == text.text.length) {
        // A block at the end needs an ordinary text line to continue writing.
        final newline = _block.source.contains('\r\n') ? '\r\n' : '\n';
        if (!widget.composer.commitText(
          expectedText: text.text,
          value: TextEditingValue(
            text: '${text.text}$newline',
            selection: TextSelection.collapsed(offset: offset + newline.length),
          ),
        )) {
          return;
        }
        offset += newline.length;
      }
    }
    text.selection = TextSelection.collapsed(offset: offset);
    widget.composer.requestFocus();
  }

  void _remove({bool keepContent = false}) {
    if (_replaceDetails(
      widget.composer,
      _block,
      keepContent ? _block.body : '',
    )) {
      widget.composer.requestFocus();
    }
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
      _leave();
      return KeyEventResult.handled;
    }
    // The summary is plain text; body shortcuts belong to its rich editor.
    final keyboard = HardwareKeyboard.instance;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final backward = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    final forward = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    if (!keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      if (_summaryFocus.hasFocus &&
          _summary.value.composing.isCollapsed &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                  _summary.selection.isCollapsed &&
                  _summary.selection.extentOffset == _summary.text.length))) {
        _focusBody();
        return KeyEventResult.handled;
      }
      final value = _body.value;
      if (_body.focus.hasPrimaryFocus &&
          value.composing.isCollapsed &&
          value.selection.isValid &&
          value.selection.isCollapsed) {
        final caret = value.selection.extentOffset;
        if (caret == 0 &&
            (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == backward)) {
          _summary.selection = TextSelection.collapsed(
            offset: _summary.text.length,
          );
          _summaryFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (caret == value.text.length &&
            (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == forward)) {
          _leave();
          return KeyEventResult.handled;
        }
      }
      if (_summaryFocus.hasFocus &&
          _summary.value.composing.isCollapsed &&
          _summary.selection.isCollapsed &&
          _summary.selection.extentOffset == 0 &&
          (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == backward)) {
        _leave(before: true);
        return KeyEventResult.handled;
      }
    }
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
      child: DCollapsible(
        open: _open,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _disclosure(context),
            const SizedBox(width: DSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DInput(
                    key: const ValueKey('details-summary'),
                    borderless: true,
                    maxLines: 3,
                    controller: _summary,
                    focusNode: _summaryFocus,
                    semanticLabel: 'Details summary',
                    hintText: 'Summary',
                    style: context
                        .findAncestorWidgetOfExactType<ComposerEditor>()
                        ?.textStyle,
                    errorText: _error,
                    enabled: widget.composer.isEditing,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.singleLineFormatter,
                    ],
                    onEditingComplete: _focusBody,
                    onChanged: _changeSummary,
                  ),
                  DCollapsibleContent(
                    keepMounted: true,
                    child: Padding(
                      padding: const EdgeInsets.only(top: DSpacing.xs),
                      child: ComposerRichBodyEditor(
                        key: const ValueKey('details-body'),
                        composer: _body,
                        label: 'Details content',
                        hintText: 'Write here…',
                        onExit: _leave,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _disclosure(BuildContext context) => DContextMenu(
    restoreFocus: false,
    content: DContextMenuContent(
      width: 260,
      children: [
        DContextMenuItem(
          onPressed: widget.composer.isEditing
              ? () => _remove(keepContent: true)
              : null,
          child: const Text('Remove details, keep content'),
        ),
        DContextMenuItem(
          variant: DContextMenuItemVariant.destructive,
          onPressed: widget.composer.isEditing ? _remove : null,
          child: const Text('Delete details'),
        ),
      ],
    ),
    child: DContextMenuTrigger(
      focusable: false,
      child: DButton(
        key: const ValueKey('details-disclosure'),
        semanticLabel: _open ? 'Collapse details' : 'Expand details',
        expanded: _open,
        variant: DButtonVariant.transparentBackground,
        label: DIcon(
          _open
              ? DIcons.chevronDown
              : Directionality.of(context) == TextDirection.rtl
              ? DIcons.chevronLeft
              : DIcons.chevronRight,
        ),
        onPressed: () {
          setState(() => _open = !_open);
          if (!_open && widget.composer.activeEditor == _body.activeEditor) {
            widget.composer.activateEmbeddedEditor(null);
          }
        },
      ),
    ),
  );
}
