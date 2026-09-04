import 'dart:async';

import 'package:flutter/material.dart';

import 'adaptive_dialog_action.dart';
import 'composer_controller.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

Future<void> closeComposerFromPanel({
  required BuildContext context,
  required ComposerController composer,
  ShellController? controller,
}) async {
  final shell = controller ?? ShellScope.read(context);
  if (composer.discarding || composer.closing) return;
  if (composer.canSaveDraft) {
    if (!shell.hideComposerForClose(composer)) return;
    if (!await shell.finishComposerDraftRestore(composer)) {
      shell.restoreComposerAfterFailedClose(composer);
      return;
    }
    if (composer.hasUnappliedDraft && !composer.hasChanges) {
      shell.closeComposer();
      return;
    }
    if (composer.hasChanges) {
      shell.closeComposer();
      return;
    }
    final error = await shell.discardComposer(composer);
    if (!composer.isDisposed) {
      if (error != null) composer.showNotice(error);
      shell.restoreComposerAfterFailedClose(composer);
    }
    return;
  }
  if (!context.mounted) return;
  if (!composer.hasChanges) {
    shell.closeComposer();
    return;
  }

  await requestComposerDiscard(
    context: context,
    composer: composer,
    controller: shell,
  );
}

Future<void> requestComposerDiscard({
  required BuildContext context,
  required ComposerController composer,
  ShellController? controller,
}) async {
  final shell = controller ?? ShellScope.read(context);
  if (composer.discarding ||
      (composer.canSaveDraft &&
          !await shell.finishComposerDraftRestore(composer))) {
    return;
  }
  if (!context.mounted) return;
  if (composer.hasUnappliedDraft && !composer.hasChanges) {
    shell.closeComposer();
    return;
  }
  if (!composer.hasChanges) {
    final error = await shell.discardComposer(composer);
    if (error != null && context.mounted) _showDiscardError(context, error);
    return;
  }

  if (!composer.beginDiscardPrompt()) return;
  try {
    await showDiscourseDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) =>
          _DiscardComposerDialog(composer: composer, controller: shell),
    );
  } finally {
    composer.finishDiscardPrompt();
  }
}

void _showDiscardError(BuildContext context, String error) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(error)));
}

class _DiscardComposerDialog extends StatefulWidget {
  const _DiscardComposerDialog({
    required this.composer,
    required this.controller,
  });

  final ComposerController composer;
  final ShellController controller;

  @override
  State<_DiscardComposerDialog> createState() => _DiscardComposerDialogState();
}

class _DiscardComposerDialogState extends State<_DiscardComposerDialog> {
  bool _discarding = false;
  bool _allowPop = false;
  String? _error;

  Future<void> _discard() async {
    if (_discarding) return;
    setState(() {
      _discarding = true;
      _error = null;
    });
    final error = await widget.controller.discardComposer(widget.composer);
    if (!mounted) return;
    if (error == null) {
      _closeDialog();
      return;
    }
    setState(() {
      _discarding = false;
      _error = error;
    });
  }

  void _closeDialog() {
    if (_allowPop || (_discarding && !widget.composer.isDisposed)) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.composer.target.isEdit;
    final theme = Theme.of(context);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_discarding) _closeDialog();
      },
      child: DiscourseAlertDialog(
        key: const ValueKey('composer-discard-dialog'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                editing
                    ? 'Do you want to discard your changes?'
                    : 'Do you want to discard your post?',
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          AdaptiveDialogAction(
            key: const ValueKey('composer-confirm-discard'),
            kind: AdaptiveDialogActionKind.destructive,
            onPressed: _discarding ? null : () => unawaited(_discard()),
            child: Text(editing ? 'Discard changes' : 'Discard'),
          ),
          AdaptiveDialogAction(
            key: const ValueKey('composer-cancel-discard'),
            onPressed: _discarding ? null : _closeDialog,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
