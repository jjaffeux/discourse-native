import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'boards_controller.dart';
import 'boards_data.dart';

class BoardCardEditor extends StatefulWidget {
  const BoardCardEditor({
    super.key,
    required this.handle,
    required this.column,
    required this.card,
    required this.onSaved,
  });
  final BoardHandle handle;
  final BoardColumn column;
  final BoardCard? card;
  final ValueChanged<BoardWriteResult> onSaved;
  @override
  State<BoardCardEditor> createState() => BoardCardEditorState();
}

class BoardCardEditorState extends State<BoardCardEditor> {
  late final _title = TextEditingController(text: widget.card?.title);
  late final _notes = TextEditingController(text: widget.card?.notes);
  late final _tags = TextEditingController(text: widget.card?.tags.join(', '));
  bool _saving = false;
  bool _uncertain = false;
  String? _error;
  late final _lease = widget.handle.owner.requests.capture(widget.handle.site);
  late final _revision = widget.handle.owner.accountRevision(
    widget.handle.site,
  );
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
    _notes.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.handle.owner.sourceCurrent(
          widget.handle.site,
          _lease,
          _revision,
        ) ||
        widget.handle.snapshot == null) {
      return DDialogContent(children: [Text(context.l10n.boardsRefused)]);
    }
    final writable =
        widget.handle.canWrite &&
        !_uncertain &&
        widget.card?.kind != BoardCardKind.unsupported;
    return DDialogContent(
      children: [
        Text(
          widget.card == null ? context.l10n.boardsNewCard : context.l10n.edit,
        ),
        DInput(
          controller: _title,
          labelText: context.l10n.title,
          enabled: writable && !_saving,
          onChanged: (_) => setState(() {}),
        ),
        DTextarea(
          controller: _notes,
          labelText: context.l10n.boardsNotes,
          minLines: 3,
          maxLines: 8,
          enabled: writable && !_saving,
        ),
        DInput(
          controller: _tags,
          labelText: context.l10n.boardsTags,
          enabled: writable && !_saving,
        ),
        if (_error != null) Text(_error!),
        DDialogFooter(
          children: [
            DButton(
              label: Text(context.l10n.save),
              onPressed: writable && !_saving && _title.text.trim().isNotEmpty
                  ? () async {
                      setState(() => _saving = true);
                      final result = await widget.handle.saveStandalone(
                        widget.column.id,
                        _title.text,
                        _notes.text,
                        cardId: widget.card?.id,
                        tags: _tags.text
                            .split(',')
                            .map((tag) => tag.trim())
                            .where((tag) => tag.isNotEmpty)
                            .toList(),
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
