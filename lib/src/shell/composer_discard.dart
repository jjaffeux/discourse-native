import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'adaptive_dialog_action.dart';
import 'composer_controller.dart';
import 'composer_presentation.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

Future<void> closeComposerFromPanel({
  required BuildContext context,
  required ComposerController composer,
  ShellController? controller,
}) async {
  final shell = controller ?? ShellScope.read(context);
  if (composer.isDisposed || composer.discarding || composer.closing) return;
  if (_hasPendingOperation(composer)) {
    if (context.mounted) _showDiscardError(context, _pendingOperationMessage);
    return;
  }
  if (composer.canSaveDraft) {
    if (!shell.hideComposerForClose(composer)) return;
    try {
      await ComposerPresentationHost.closeAnimationOf(context, composer);
      // Paint the closed dock before restoration, encoding or network work.
      // The presentation host retains this editor until persistence is safe.
      await WidgetsBinding.instance.endOfFrame;
      if (composer.isDisposed) return;
      if (!await shell.prepareComposerForClose(composer)) {
        if (context.mounted) {
          DToast.show(
            context,
            'This draft could not be saved yet. Please try again.',
            type: DToastType.error,
          );
        }
        return;
      }
      if (composer.hasUnappliedDraft || composer.hasChanges) {
        shell.closeComposer(composer: composer);
        return;
      }
      final error = await shell.discardComposer(composer);
      if (!composer.isDisposed && error != null) composer.showNotice(error);
    } finally {
      shell.restoreComposerAfterFailedClose(composer);
    }
    return;
  }
  if (!context.mounted) return;
  if (!composer.hasChanges && !composer.metadataChanged) {
    await _closeUnchangedComposer(context, composer, shell);
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
  if (composer.isDisposed || composer.discarding || composer.closing) return;
  if (_hasPendingOperation(composer)) {
    if (context.mounted) _showDiscardError(context, _pendingOperationMessage);
    return;
  }
  if (composer.canSaveDraft &&
      !await shell.finishComposerDraftRestore(composer)) {
    return;
  }
  if (!context.mounted || composer.isDisposed) return;
  if (_hasPendingOperation(composer)) {
    _showDiscardError(context, _pendingOperationMessage);
    return;
  }
  if (composer.hasUnappliedDraft && !composer.hasChanges) {
    await _closeUnchangedComposer(context, composer, shell);
    return;
  }
  if (!composer.hasChanges && !composer.metadataChanged) {
    final error = await _discardAfterClosing(context, composer, shell);
    if (error != null && context.mounted) _showDiscardError(context, error);
    return;
  }

  if (!composer.beginDiscardPrompt()) return;
  final revision = composer.draftRevision;
  try {
    await showDiscourseDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _DiscardComposerDialog(
        composer: composer,
        onDiscard: () => _discardAfterClosing(context, composer, shell),
        confirmedRevision: revision,
      ),
    );
  } finally {
    composer.finishDiscardPrompt();
  }
}

Future<void> _closeUnchangedComposer(
  BuildContext context,
  ComposerController composer,
  ShellController shell,
) async {
  if (!shell.hideComposerForClose(composer)) return;
  final revision = composer.draftRevision;
  await ComposerPresentationHost.closeAnimationOf(context, composer);
  if (composer.isDisposed) return;
  if (_hasPendingOperation(composer) || composer.draftRevision != revision) {
    shell.restoreComposerAfterFailedClose(composer);
    if (context.mounted) {
      _showDiscardError(
        context,
        'This draft changed while closing. Review it and try again.',
      );
    }
    return;
  }
  shell.closeComposer(composer: composer);
}

Future<String?> _discardAfterClosing(
  BuildContext context,
  ComposerController composer,
  ShellController shell,
) async {
  if (!shell.hideComposerForClose(composer)) return _pendingOperationMessage;
  final revision = composer.draftRevision;
  try {
    if (context.mounted) {
      await ComposerPresentationHost.closeAnimationOf(context, composer);
    }
    if (composer.isDisposed) return null;
    if (_hasPendingOperation(composer)) return _pendingOperationMessage;
    if (composer.draftRevision != revision) {
      return 'This draft changed while closing. Review it and try again.';
    }
    return await shell.discardComposer(composer);
  } finally {
    shell.restoreComposerAfterFailedClose(composer);
  }
}

const _pendingOperationMessage =
    'Finish the current operation before closing this draft.';

bool _hasPendingOperation(ComposerController composer) =>
    composer.submitting ||
    composer.discarding ||
    composer.loadingBody ||
    composer.hasActiveUploads ||
    composer.state == ComposerState.checking;

void _showDiscardError(BuildContext context, String error) {
  DToast.show(context, error, type: DToastType.error);
}

class _DiscardComposerDialog extends StatefulWidget {
  const _DiscardComposerDialog({
    required this.composer,
    required this.onDiscard,
    required this.confirmedRevision,
  });

  final ComposerController composer;
  final Future<String?> Function() onDiscard;
  final int confirmedRevision;

  @override
  State<_DiscardComposerDialog> createState() => _DiscardComposerDialogState();
}

class _DiscardComposerDialogState extends State<_DiscardComposerDialog> {
  bool _discarding = false;
  bool _allowPop = false;
  String? _error;

  Future<void> _discard() async {
    if (_discarding) return;
    if (_hasPendingOperation(widget.composer)) {
      setState(() => _error = _pendingOperationMessage);
      return;
    }
    if (widget.composer.draftRevision != widget.confirmedRevision) {
      setState(() {
        _error =
            'This draft changed while the confirmation was open. '
            'Cancel, review it, and try again.';
      });
      return;
    }
    setState(() {
      _discarding = true;
      _error = null;
    });
    final error = await widget.onDiscard();
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
