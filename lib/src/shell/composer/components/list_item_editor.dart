import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../component_artwork.dart';
import '../controller.dart';
import '../embedded_editor.dart';
import '../panel.dart';
import 'list.dart';
import 'list_source.dart';

/// The existing rich composer edits a source-mapped body beside a Native
/// checkbox or a text marker. Descendants remain in the item's content column.
class ComposerListItemEditor extends StatefulWidget {
  const ComposerListItemEditor({
    super.key,
    required this.composer,
    required this.item,
    this.scrollController,
  });
  final ComposerController composer;
  final ComposerListItem item;
  final ScrollController? scrollController;
  @override
  State<ComposerListItemEditor> createState() => _ComposerListItemEditorState();
}

class _ComposerListItemEditorState extends State<ComposerListItemEditor>
    implements ComposerComponentEditor {
  late final body = ComposerListBodyController(widget.composer, widget.item);
  bool _focusScheduled = false;

  @override
  void edit() => body.requestFocus();
  @override
  void initState() {
    super.initState();
    widget.composer.text.addListener(_focusFromParent);
    widget.composer.focus.addListener(_focusFromParent);
    _focusFromParent();
  }

  @override
  void didUpdateWidget(ComposerListItemEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    body.updateItem(widget.item);
    _focusFromParent();
  }

  void _focusFromParent() {
    if (_focusScheduled ||
        !body.isEditing ||
        !widget.composer.focus.hasPrimaryFocus) {
      return;
    }
    final selection = widget.composer.value.selection;
    final item = body.item;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        selection.start < item.contentStart ||
        selection.end > item.end) {
      return;
    }
    // Keyboard focus must reach the body before painting the parent's caret
    // beside its full-width projection. Only defer changes during build/layout.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _focusScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusScheduled = false;
        if (mounted) _focusFromParent();
      });
      return;
    }
    body.text.selection = TextSelection.collapsed(
      offset: item.body.localOffset(selection.start),
    );
    body.requestFocus();
  }

  @override
  void dispose() {
    widget.composer.text.removeListener(_focusFromParent);
    widget.composer.focus.removeListener(_focusFromParent);
    body.dispose();
    super.dispose();
  }

  bool get _isFirstNestedItem {
    final parent = widget.composer;
    return parent is ComposerListBodyController &&
        parent.item.children.firstOrNull?.start == widget.item.start;
  }

  @override
  Widget build(BuildContext context) => ComposerEmbeddedEditor(
    owner: widget.composer,
    scrollController: widget.scrollController,
    semanticLabel: context.l10n.item((widget.item.label).toString()),
    child: Padding(
      padding: widget.item.isTask
          ? EdgeInsets.only(
              // The parent's bottom padding follows its entire subtree, so
              // its first child needs its own gap from the parent's text.
              top: _isFirstNestedItem ? DSpacing.sm : 0,
              bottom: DSpacing.sm,
            )
          : EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.item.isTask)
            DCheckbox(
              inline: true,
              size: DControlStyle.isTouch(context)
                  ? DCheckboxSize.large
                  : DCheckboxSize.standard,
              inlineTextStyle:
                  context
                      .findAncestorWidgetOfExactType<ComposerEditor>()
                      ?.textStyle ??
                  Theme.of(context).textTheme.bodyLarge,
              value: widget.item.checked,
              readOnly: !body.isEditing,
              semanticLabel: widget.item.body.text.split('\n').first.isEmpty
                  ? context.l10n.toDo
                  : widget.item.body.text.split('\n').first,
              onChanged: (_) => body.toggle(),
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.only(end: DSpacing.md),
              child: Text(
                widget.item.number != null ? '${widget.item.number}.' : '•',
                style: context
                    .findAncestorWidgetOfExactType<ComposerEditor>()
                    ?.textStyle,
              ),
            ),
          Expanded(
            child: ComposerRichBodyEditor(
              composer: body,
              label: context.l10n.listItemContent,
              hintText: widget.item.isTask
                  ? context.l10n.toDo
                  : context.l10n.list,
              enableBlockReordering: false,
              onKeyEvent: body.handleKey,
              onEmptyBackspace: body.deleteAtStart,
              onExit: body.exit,
            ),
          ),
        ],
      ),
    ),
  );
}
