import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import 'shell_controller.dart';

String get _confirmationPhrase => appL10n.permanentlyDeletePostpermanentdelete;

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
    await showDDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context, dialog) => DDialogContent(
        showCloseButton: false,
        key: const ValueKey('post-permanent-delete-refusal'),
        maxWidth: 520,
        children: [
          DDialogHeader(
            children: [
              DDialogTitle(child: Text(appL10n.cannotPermanentlyDelete)),
            ],
          ),
          Text(refusal),
          DDialogFooter(
            children: [
              DButton(
                label: Text(appL10n.oK),
                onPressed: dialog.close,
                variant: DButtonVariant.primary,
              ),
            ],
          ),
        ],
      ),
    );
    return;
  }

  await showDDialog<void>(
    context: context,
    useRootNavigator: true,
    dismissOnBarrier: false,
    builder: (context, dialog) => _PermanentDeleteDialog(
      controller: controller,
      target: target,
      onClose: dialog.close,
    ),
  );
}

class _PermanentDeleteDialog extends StatefulWidget {
  const _PermanentDeleteDialog({
    required this.controller,
    required this.target,
    required this.onClose,
  });

  final ShellController controller;
  final PostPermanentDeleteTarget target;
  final VoidCallback onClose;

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
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target.deletesTopic ? 'topic' : 'post';
    return DDialogContent(
      showCloseButton: false,
      key: const ValueKey('post-permanent-delete-dialog'),
      maxWidth: 520,
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(
              child: Text(
                context.l10n.permanentlyDeletePostpermanentdeleteValue(
                  (target).toString(),
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.thisCannotBeUndoneTheWillBeRemovedFromTheDatabase(
                  (target).toString(),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.l10n.typeToConfirm((_confirmationPhrase).toString()),
              ),
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
        DDialogFooter(
          children: [
            DButton(
              label: Text(context.l10n.cancel),
              onPressed: _saving ? null : () => widget.onClose(),
            ),
            DButton(
              key: const ValueKey('post-permanent-delete-submit'),
              label: Text(context.l10n.permanentlyDelete),
              onPressed: !_saving && _matches
                  ? () => unawaited(_delete())
                  : null,
              variant: DButtonVariant.destructive,
              loading: _saving,
            ),
          ],
        ),
      ],
    );
  }
}
