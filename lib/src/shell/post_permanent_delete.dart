import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post.dart';
import 'shell_controller.dart';

const _confirmationPhrase = 'permanently delete';

Future<void> showPostPermanentDelete({
  required BuildContext context,
  required ShellController controller,
  required Post post,
}) async {
  final refusal = await controller.checkPermanentPostDeletion(post);
  if (!context.mounted) return;
  if (refusal != null) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('post-permanent-delete-refusal'),
        title: const Text('Cannot permanently delete'),
        content: Text(refusal),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _PermanentDeleteDialog(controller: controller, post: post),
  );
}

class _PermanentDeleteDialog extends StatefulWidget {
  const _PermanentDeleteDialog({required this.controller, required this.post});

  final ShellController controller;
  final Post post;

  @override
  State<_PermanentDeleteDialog> createState() => _PermanentDeleteDialogState();
}

class _PermanentDeleteDialogState extends State<_PermanentDeleteDialog> {
  final _confirmation = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _matches =>
      _confirmation.text.trim().toLowerCase() == _confirmationPhrase;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_saving || !_matches) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.controller.permanentlyDeletePost(widget.post);
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

  @override
  Widget build(BuildContext context) {
    final target = widget.post.postNumber == 1 ? 'topic' : 'post';
    return AlertDialog(
      key: const ValueKey('post-permanent-delete-dialog'),
      title: Text('Permanently delete $target?'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This cannot be undone. The $target will be removed from the '
              'database.',
            ),
            const SizedBox(height: 14),
            const Text('Type “$_confirmationPhrase” to confirm.'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('post-permanent-delete-confirmation'),
              controller: _confirmation,
              autofocus: true,
              enabled: !_saving,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(
                hintText: _confirmationPhrase,
                border: OutlineInputBorder(),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                key: const ValueKey('post-permanent-delete-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('post-permanent-delete-submit'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: !_saving && _matches ? () => unawaited(_delete()) : null,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Text('Permanently delete'),
        ),
      ],
    );
  }
}
