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
  if (composer.canSaveDraft &&
      (composer.hasChanges ||
          composer.metadataChanged ||
          composer.savedDraft != null)) {
    await requestComposerDiscard(
      context: context,
      composer: composer,
      controller: controller,
      offerSave: true,
    );
  } else {
    await saveComposerFromPanel(
      context: context,
      composer: composer,
      controller: controller,
    );
  }
}

Future<void> saveComposerFromPanel({
  required BuildContext context,
  required ComposerController composer,
  ShellController? controller,
  bool showFailureToast = true,
}) async {
  final shell = controller ?? ShellScope.read(context);
  if (composer.isDisposed || composer.discarding || composer.closing) return;
  if (_hasPendingOperation(composer)) {
    if (context.mounted && showFailureToast) {
      _showDiscardError(context, _pendingOperationMessage);
    }
    return;
  }
  if (composer.canSaveDraft) {
    if (!shell.hideComposerForClose(composer)) return;
    try {
      // Paint the closed dock before restoration, encoding or network work.
      // The presentation host retains this editor until persistence is safe.
      await WidgetsBinding.instance.endOfFrame;
      if (!await shell.prepareComposerForClose(composer)) {
        if (context.mounted && showFailureToast) {
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
  bool offerSave = false,
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
  if (!composer.hasChanges &&
      !composer.metadataChanged &&
      composer.savedDraft == null) {
    final error = await shell.discardComposer(composer);
    if (error != null && context.mounted) _showDiscardError(context, error);
    return;
  }

  if (!composer.beginDiscardPrompt()) return;
  final revision = composer.draftRevision;
  try {
    await showDDialog<void>(
      context: context,
      // Keep the source diff readable. Native Dialog still owns the barrier,
      // focus trap, keyboard dismissal and route lifecycle.
      presentationBuilder: (context, presentation) => Stack(
        children: [
          Positioned.fill(
            child: presentation.buildBackdrop(
              color: Colors.transparent,
              blurSigma: 0,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: DSpacing.lg,
                right: DSpacing.lg,
                top: DSpacing.lg,
                bottom: DSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: SingleChildScrollView(
                  primary: false,
                  child: presentation.content,
                ),
              ),
            ),
          ),
        ],
      ),
      canDismiss: () =>
          (!composer.discarding && !composer.closing) || composer.isDisposed,
      builder: (dialogContext, dialog) => _DiscardComposerDialog(
        composer: composer,
        controller: shell,
        confirmedRevision: revision,
        offerSave: offerSave,
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
    this.offerSave = false,
    required this.onClose,
  });

  final ComposerController composer;
  final ShellController controller;
  final int confirmedRevision;
  final bool offerSave;
  final VoidCallback onClose;

  @override
  State<_DiscardComposerDialog> createState() => _DiscardComposerDialogState();
}

class _DiscardComposerDialogState extends State<_DiscardComposerDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _restoration = AnimationController(
    vsync: this,
    duration: DTextRevisionPreview.restorationDuration,
  );
  bool _restoring = false;
  bool _discarding = false;
  bool _saving = false;
  String? _error;
  final _previewIntents = <ComposerDiscardPreview>{};

  @override
  void dispose() {
    _restoration.dispose();
    super.dispose();
  }

  Widget _previewAction(ComposerDiscardPreview kind, Widget child) =>
      DRevisionPreviewTarget(
        onChanged: (active) {
          if (_discarding || _saving || _restoring) return;
          _previewIntents.remove(kind);
          if (active) _previewIntents.add(kind);
          widget.composer.previewDiscard(
            _previewIntents.lastOrNull,
            widget.confirmedRevision,
          );
        },
        child: child,
      );

  Future<void> _rollback() async {
    if (_restoring || _discarding || _saving) return;
    final composer = widget.composer;
    if (_hasPendingOperation(composer)) {
      setState(() => _error = _pendingOperationMessage);
      return;
    }
    if (composer.draftRevision != widget.confirmedRevision) {
      setState(
        () => _error =
            appL10n.thisDraftChangedWhileTheConfirmationWasOpenCancelReviewIt,
      );
      return;
    }
    final from = composer.draft;
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final result = await widget.controller.rollbackSavedComposerDraft(
        composer,
        confirmedRevision: widget.confirmedRevision,
      );
      if (!mounted) return;
      if (composer.isDisposed ||
          result.revision == null && result.error == null) {
        widget.onClose();
        return;
      }
      if (result.error != null) {
        setState(() => _error = result.error);
        return;
      }
      final revision = result.revision!;
      if (!composer.showDraftRollback(from, _restoration, revision)) {
        setState(
          () => _error =
              appL10n.thisDraftChangedWhileTheConfirmationWasOpenCancelReviewIt,
        );
        return;
      }
      _restoration.duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : DTextRevisionPreview.restorationDuration;
      await _restoration.forward(from: 0).orCancel;
      if (!mounted || composer.isDisposed) return;
      composer.finishDiscard();
      composer.clearDiscardPreview();
      if (!composer.discardRevisionIsCurrent(revision)) {
        setState(
          () => _error =
              appL10n.thisDraftChangedWhileTheConfirmationWasOpenCancelReviewIt,
        );
        return;
      }
      widget.controller.closeComposer(composer: composer);
      widget.onClose();
    } on TickerCanceled {
      // A dismissed account or route must never close a replacement composer.
    } finally {
      if (!composer.isDisposed) {
        composer.finishDiscard();
        composer.clearDiscardPreview();
      }
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _discarding || _restoring) return;
    setState(() => _saving = true);
    await saveComposerFromPanel(
      context: context,
      composer: widget.composer,
      controller: widget.controller,
      showFailureToast: false,
    );
    if (!mounted) return;
    if (widget.composer.isDisposed) {
      widget.onClose();
    } else {
      setState(() {
        _saving = false;
        _error = appL10n.thisDraftCouldNotBeSavedYetPleaseTryAgain;
      });
    }
  }

  Future<void> _discard() async {
    if (_discarding || _saving || _restoring) return;
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
    if ((_discarding || _saving || _restoring) && !widget.composer.isDisposed) {
      return;
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.composer.target.isEdit;
    final saved = widget.composer.savedDraft != null;
    final changed = widget.composer.hasSavedDraftChanges;
    final busy = _saving || _discarding || _restoring;
    final message = widget.offerSave
        ? context.l10n.closeComposer
        : editing
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
            if (widget.offerSave)
              DButton(
                key: const ValueKey('composer-confirm-save'),
                autofocus: true,
                variant: DButtonVariant.primary,
                onPressed: busy ? null : () => unawaited(_save()),
                loading: _saving,
                icon: const DIcon(DIcons.check),
                label: Text(
                  !saved
                      ? context.l10n.saveDraft
                      : changed
                      ? context.l10n.saveChanges
                      : context.l10n.keepComposerDraft,
                ),
              ),
            if (saved && changed)
              _previewAction(
                ComposerDiscardPreview.changes,
                DButton(
                  key: const ValueKey('composer-revert-saved-draft'),
                  variant: DButtonVariant.destructive,
                  onPressed: busy ? null : () => unawaited(_rollback()),
                  loading: _restoring,
                  icon: const DIcon(DIcons.arrowRotateLeft),
                  label: Text(context.l10n.discardChanges),
                ),
              ),
            _previewAction(
              ComposerDiscardPreview.all,
              DButton(
                key: const ValueKey('composer-confirm-discard'),
                variant: DButtonVariant.destructive,
                onPressed: busy ? null : () => unawaited(_discard()),
                loading: _discarding,
                icon: const DIcon(DIcons.trashCan),
                label: Text(
                  saved
                      ? context.l10n.deleteComposerDraft
                      : editing
                      ? context.l10n.discardChanges
                      : context.l10n.discard,
                ),
              ),
            ),
            DButton(
              key: const ValueKey('composer-cancel-discard'),
              variant: DButtonVariant.ghost,
              onPressed: busy ? null : _closeDialog,
              label: Text(context.l10n.cancel),
            ),
          ],
        ),
      ],
    );
  }
}
