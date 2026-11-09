import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../foundation/icons/d_icons.dart';
import '../block_surface.dart';
import '../component_artwork.dart';
import '../controller.dart';
import '../embedded_editor.dart';
import '../markdown_editing_controller.dart';
import '../panel.dart';
import 'details.dart';
import 'details_body_controller.dart';
import 'details_source.dart';

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

class _ComposerDetailsEditorState extends State<ComposerDetailsEditor>
    implements ComposerComponentEditor {
  late ComposerDetailsBodyController _body = ComposerDetailsBodyController(
    widget.composer,
    widget.block,
  );
  ComposerDetailsBlock get _block => _body.block;
  late final _summary = MarkdownEditingController(
    text: widget.block.summary,
    imageSiteUrl: widget.composer.target.siteUrl,
    resolveEmoji: widget.composer.text.resolveEmoji,
    emojiChanges: widget.composer.text.emojiChanges,
    enableMarkdownLinkify: false,
    shareScans: false,
    artwork: widget.composer.text.artwork,
  );
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

  @override
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
    if (replaceComposerDetails(
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
    if (!replaceComposerDetails(widget.composer, _block, source)) return false;
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
    semanticLabel: context.l10n.detailsEditor,
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
            // Touch opens this menu by long press, and only it can unwrap
            // the details.
            ComposerBlockSurface.ownsLongPress(child: _disclosure(context)),
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
                    semanticLabel: context.l10n.detailsSummary,
                    hintText: context.l10n.summary,
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
                        label: context.l10n.detailsContent,
                        hintText: context.l10n.writeHere,
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
          child: Text(context.l10n.removeDetailsKeepContent),
        ),
        DContextMenuItem(
          variant: DContextMenuItemVariant.destructive,
          onPressed: widget.composer.isEditing ? _remove : null,
          child: Text(context.l10n.deleteDetails),
        ),
      ],
    ),
    child: DContextMenuTrigger(
      focusable: false,
      child: DButton(
        key: const ValueKey('details-disclosure'),
        semanticLabel: _open
            ? context.l10n.collapseDetails
            : context.l10n.expandDetails,
        expanded: _open,
        variant: DButtonVariant.ghost,
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
