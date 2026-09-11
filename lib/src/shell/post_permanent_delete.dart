import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import 'shell_controller.dart';

const _confirmationPhrase = 'permanently delete';

Future<void> showPostPermanentDelete({
  required BuildContext context,
  required ShellController controller,
  required String siteUrl,
  required int topicId,
  required Post post,
}) async {
  final target = controller.capturePostPermanentDeleteTarget(
    siteUrl: siteUrl,
    topicId: topicId,
    post: post,
  );
  final refusal = await controller.checkPermanentPostDeletion(target);
  if (!context.mounted) return;
  if (refusal != null) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('post-permanent-delete-refusal'),
        title: const Text('Cannot permanently delete'),
        content: Text(refusal),
        actions: [
          DButton(
            label: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
            variant: DButtonVariant.primary,
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
        _PermanentDeleteDialog(controller: controller, target: target),
  );
}

class _PermanentDeleteDialog extends StatefulWidget {
  const _PermanentDeleteDialog({
    required this.controller,
    required this.target,
  });

  final ShellController controller;
  final PostPermanentDeleteTarget target;

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
    final error = await widget.controller.permanentlyDeletePost(widget.target);
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
    final target = widget.target.deletesTopic ? 'topic' : 'post';
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
            DInput(
              key: const ValueKey('post-permanent-delete-confirmation'),
              controller: _confirmation,
              autofocus: true,
              enabled: !_saving,
              onChanged: (_) => setState(() => _error = null),
              hintText: _confirmationPhrase,
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
        DButton(
          label: const Text('Cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        DButton(
          key: const ValueKey('post-permanent-delete-submit'),
          label: const Text('Permanently delete'),
          onPressed: !_saving && _matches ? () => unawaited(_delete()) : null,
          variant: DButtonVariant.destructive,
          loading: _saving,
        ),
      ],
    );
  }
}
