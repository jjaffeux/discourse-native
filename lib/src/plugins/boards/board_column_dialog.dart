import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'boards_controller.dart';
import 'boards_data.dart';

class BoardColumnEditor extends StatefulWidget {
  const BoardColumnEditor({
    super.key,
    required this.handle,
    required this.column,
    required this.onSaved,
  });
  final BoardHandle handle;
  final BoardColumn column;
  final ValueChanged<BoardWriteResult> onSaved;
  @override
  State<BoardColumnEditor> createState() => _BoardColumnEditorState();
}

class _BoardColumnEditorState extends State<BoardColumnEditor> {
  late final _title = TextEditingController(text: widget.column.title);
  late final _icon = TextEditingController(text: widget.column.icon);
  late BoardColumnOrder _order = widget.column.order;
  late final _lease = widget.handle.owner.requests.capture(widget.handle.site);
  late final _revision = widget.handle.owner.accountRevision(
    widget.handle.site,
  );
  bool _saving = false, _uncertain = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.handle.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.handle.removeListener(_changed);
    _title.dispose();
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.handle.snapshot?.column(widget.column.id);
    if (!widget.handle.owner.sourceCurrent(
          widget.handle.site,
          _lease,
          _revision,
        ) ||
        current == null) {
      return DDialogContent(children: [Text(context.l10n.boardsRefused)]);
    }
    final enabled = widget.handle.canManage && !_saving && !_uncertain;
    return DDialogContent(
      children: [
        Text(context.l10n.boardsEditColumn),
        DInput(
          controller: _title,
          labelText: context.l10n.title,
          enabled: enabled,
          onChanged: (_) => setState(() {}),
        ),
        DInput(
          controller: _icon,
          labelText: context.l10n.boardsColumnIcon,
          enabled: enabled,
        ),
        DSelect<BoardColumnOrder>.controlled(
          value: _order,
          semanticLabel: context.l10n.boardsColumnSort,
          enabled: enabled,
          entries: [
            DSelectOption(
              value: BoardColumnOrder.priority,
              label: context.l10n.boardsSortPriority,
              child: Text(context.l10n.boardsSortPriority),
            ),
            DSelectOption(
              value: BoardColumnOrder.recency,
              label: context.l10n.boardsSortRecency,
              child: Text(context.l10n.boardsSortRecency),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _order = value);
          },
        ),
        if (_error case final error?) Text(error),
        DDialogFooter(
          children: [
            DButton(
              label: Text(context.l10n.save),
              onPressed: enabled && _title.text.trim().isNotEmpty
                  ? () async {
                      setState(() => _saving = true);
                      final result = await widget.handle.updateColumn(
                        widget.column.id,
                        title: _title.text,
                        icon: _icon.text,
                        order: _order,
                      );
                      if (!mounted) return;
                      if (result.saved) {
                        widget.onSaved(result);
                      } else {
                        setState(() {
                          _saving = false;
                          _uncertain = result.state == BoardWriteState.unknown;
                          _error = _uncertain
                              ? context.l10n.boardsUnknownWrite
                              : result.error ?? context.l10n.boardsRefused;
                        });
                      }
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class BoardColumnRemovalDialog extends StatefulWidget {
  const BoardColumnRemovalDialog({
    super.key,
    required this.handle,
    required this.columnId,
    required this.delete,
    required this.onConfirm,
    required this.onCancel,
  });
  final BoardHandle handle;
  final int columnId;
  final bool delete;
  final VoidCallback onConfirm, onCancel;
  @override
  State<BoardColumnRemovalDialog> createState() =>
      _BoardColumnRemovalDialogState();
}

class _BoardColumnRemovalDialogState extends State<BoardColumnRemovalDialog> {
  final _confirmation = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.handle.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.handle.removeListener(_changed);
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final column = widget.handle.snapshot?.column(widget.columnId);
    if (column == null) {
      return DDialogContent(children: [Text(context.l10n.boardsRefused)]);
    }
    final typing = widget.delete && column.cards.length > 5;
    return DDialogContent(
      children: [
        Text(
          widget.delete
              ? context.l10n.boardsDeleteColumn
              : context.l10n.boardsClearColumn,
        ),
        Text(
          widget.delete
              ? context.l10n.boardsDeleteColumnConfirm(
                  column.title,
                  column.cards.length,
                )
              : context.l10n.boardsClearColumnConfirm(
                  column.title,
                  column.cards.length,
                ),
        ),
        if (typing)
          DInput(
            controller: _confirmation,
            labelText: context.l10n.boardsTypeColumnName(column.title),
            onChanged: (_) => setState(() {}),
          ),
        DDialogFooter(
          children: [
            DButton(
              label: Text(context.l10n.cancel),
              onPressed: widget.onCancel,
            ),
            DButton(
              variant: DButtonVariant.destructive,
              label: Text(
                widget.delete
                    ? context.l10n.boardsDeleteColumn
                    : context.l10n.boardsClearColumn,
              ),
              onPressed:
                  widget.handle.canManage &&
                      (!typing || _confirmation.text == column.title)
                  ? widget.onConfirm
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
