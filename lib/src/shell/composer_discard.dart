import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'composer_controller.dart';
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
      // Paint the closed dock before restoration, encoding or network work.
      // The presentation host retains this editor until persistence is safe.
      await WidgetsBinding.instance.endOfFrame;
      if (!await shell.prepareComposerForClose(composer)) {
        if (context.mounted) {
          DToast.show(
            context,
            appL10n.thisDraftCouldNotBeSavedYetPleaseTryAgain,
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
    shell.closeComposer(composer: composer);
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
    shell.closeComposer(composer: composer);
    return;
  }
  if (!composer.hasChanges && !composer.metadataChanged) {
    final error = await shell.discardComposer(composer);
    if (error != null && context.mounted) _showDiscardError(context, error);
    return;
  }

  if (!composer.beginDiscardPrompt()) return;
  final revision = composer.draftRevision;
  try {
    await showDDialog<void>(
      context: context,
      canDismiss: () => !composer.discarding || composer.isDisposed,
      builder: (dialogContext, dialog) => _DiscardComposerDialog(
        composer: composer,
        controller: shell,
        confirmedRevision: revision,
        onClose: dialog.close,
      ),
    );
  } finally {
    composer.finishDiscardPrompt();
  }
}

String get _pendingOperationMessage =>
    appL10n.finishTheCurrentOperationBeforeClosingThisDraft;

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
    required this.controller,
    required this.confirmedRevision,
    required this.onClose,
  });

  final ComposerController composer;
  final ShellController controller;
  final int confirmedRevision;
  final VoidCallback onClose;

  @override
  State<_DiscardComposerDialog> createState() => _DiscardComposerDialogState();
}

class _DiscardComposerDialogState extends State<_DiscardComposerDialog> {
  bool _discarding = false;
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
            appL10n.thisDraftChangedWhileTheConfirmationWasOpenCancelReviewIt;
      });
      return;
    }
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
    if (_discarding && !widget.composer.isDisposed) return;
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.composer.target.isEdit;
    final message = editing
        ? context.l10n.doYouWantToDiscardYourChanges
        : context.l10n.doYouWantToDiscardYourPost;
    return DDialogContent(
      key: const ValueKey('composer-discard-dialog'),
      semanticLabel: message,
      showCloseButton: false,
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(child: Text(message)),
            if (_error case final error?)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: DTokens.of(context).destructive),
                ),
              ),
          ],
        ),
        DDialogFooter(
          wideAlignment: WrapAlignment.start,
          children: [
            DButton(
              key: const ValueKey('composer-confirm-discard'),
              variant: DButtonVariant.destructive,
              onPressed: _discarding ? null : () => unawaited(_discard()),
              loading: _discarding,
              icon: const DIcon(DIcons.trashCan),
              label: Text(
                editing ? context.l10n.discardChanges : context.l10n.discard,
              ),
            ),
            DButton(
              key: const ValueKey('composer-cancel-discard'),
              variant: DButtonVariant.transparentBackground,
              onPressed: _discarding ? null : _closeDialog,
              label: Text(context.l10n.cancel),
            ),
          ],
        ),
      ],
    );
  }
}
