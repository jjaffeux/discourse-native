import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post.dart';
import 'shell_controller.dart';

Future<void> showPostNoticeEditor({
  required BuildContext context,
  required ShellController controller,
  required Post post,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _PostNoticeDialog(controller: controller, post: post),
);

class _PostNoticeDialog extends StatefulWidget {
  const _PostNoticeDialog({required this.controller, required this.post});

  final ShellController controller;
  final Post post;

  @override
  State<_PostNoticeDialog> createState() => _PostNoticeDialogState();
}

class _PostNoticeDialogState extends State<_PostNoticeDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.post.notice?.raw ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _set(String? notice) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.controller.setPostNotice(widget.post, notice);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  bool get _canSave =>
      !_saving &&
      _text.text.trim().isNotEmpty &&
      _text.text.trim() != widget.post.notice?.raw;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('post-notice-dialog'),
    title: Text(
      widget.post.notice == null ? 'Add post notice' : 'Change post notice',
    ),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('This staff notice will be shown above the post.'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('post-notice-text'),
            controller: _text,
            autofocus: true,
            enabled: !_saving,
            minLines: 4,
            maxLines: 8,
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(
              labelText: 'Notice',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
              key: const ValueKey('post-notice-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      if (widget.post.notice != null)
        TextButton(
          key: const ValueKey('post-notice-delete'),
          onPressed: _saving ? null : () => unawaited(_set(null)),
          child: Text(
            'Delete notice',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('post-notice-save'),
        onPressed: _canSave ? () => unawaited(_set(_text.text)) : null,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}
