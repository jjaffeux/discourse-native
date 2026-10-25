import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../models/post.dart';
import '../models/post_mutation_outcome.dart';
import 'post_mutation_feedback.dart';
import 'shell_controller.dart';

Future<void> showPostNoticeEditor({
  required BuildContext context,
  required ShellController controller,
  required String siteUrl,
  required int topicId,
  required Post post,
}) {
  final target = controller.capturePostNoticeTarget(
    siteUrl: siteUrl,
    topicId: topicId,
    postId: post.id,
  );
  final dialogKey = GlobalKey<_PostNoticeDialogState>();
  return showDDialog<void>(
    context: context,
    dismissOnBarrier: false,
    canDismiss: () => !(dialogKey.currentState?._saving ?? false),
    builder: (context, dialog) => _PostNoticeDialog(
      key: dialogKey,
      controller: controller,
      target: target,
      post: post,
      onClose: dialog.close,
    ),
  );
}

class _PostNoticeDialog extends StatefulWidget {
  const _PostNoticeDialog({
    super.key,
    required this.controller,
    required this.target,
    required this.post,
    required this.onClose,
  });

  final ShellController controller;
  final PostNoticeTarget target;
  final Post post;
  final VoidCallback onClose;

  @override
  State<_PostNoticeDialog> createState() => _PostNoticeDialogState();
}

class _PostNoticeDialogState extends State<_PostNoticeDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.post.notice?.raw ?? '',
  );
  bool _saving = false;
  String? _error;
  PostMutationOutcome? _outcome;
  PostMutationRecovery? _recovery;

  bool get _requiresNewIntent =>
      _outcome is PostMutationAccepted ||
      (_outcome != null && postMutationRequiresNewIntent(_outcome!));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _set(String? notice) async {
    if (_saving || _requiresNewIntent) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final outcome = await widget.controller.setPostNotice(
      widget.target,
      notice,
    );
    if (!mounted) return;
    if (outcome is PostMutationAccepted &&
            outcome.projection == PostProjectionFreshness.fresh ||
        outcome is PostMutationNoChange) {
      _saving = false;
      widget.onClose();
      return;
    }
    setState(() {
      _saving = false;
      _outcome = outcome;
      _recovery = postMutationRecoveryOf(outcome);
      _error = postMutationMessage(
        context,
        outcome,
        retiredMessage:
            context.l10n.yourConnectionChangedReopenThePostNoticeAndTryAgain,
      );
    });
  }

  void _refreshed(PostProjectionFreshness projection) {
    if (_outcome is PostMutationAccepted &&
        projection == PostProjectionFreshness.fresh) {
      widget.onClose();
      return;
    }
    setState(() {
      if (projection != PostProjectionFreshness.stale) _recovery = null;
      _error = postMutationRefreshMessage(
        context,
        projection,
        retiredMessage:
            context.l10n.yourConnectionChangedReopenThePostNoticeAndTryAgain,
      );
    });
  }

  bool get _canSave =>
      !_saving &&
      !_requiresNewIntent &&
      _text.text.trim().isNotEmpty &&
      _text.text != widget.post.notice?.raw;

  @override
  Widget build(BuildContext context) => DDialogContent(
    key: const ValueKey('post-notice-dialog'),
    semanticLabel: widget.post.notice == null
        ? context.l10n.addPostNotice
        : context.l10n.changePostNotice,
    showCloseButton: false,
    maxWidth: 548,
    children: [
      DDialogHeader(
        children: [
          DDialogTitle(
            child: Text(
              widget.post.notice == null
                  ? context.l10n.addPostNotice
                  : context.l10n.changePostNotice,
            ),
          ),
          DDialogDescription(
            child: Text(context.l10n.thisStaffNoticeWillBeShownAboveThePost),
          ),
        ],
      ),
      DDialogScrollArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DSpacing.sm,
          children: [
            DTextarea(
              key: const ValueKey('post-notice-text'),
              controller: _text,
              autofocus: true,
              enabled: !_saving && !_requiresNewIntent,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => setState(() => _error = null),
              labelText: context.l10n.notice,
            ),
            if (_error case final error?)
              DAlert(
                key: const ValueKey('post-notice-error'),
                variant: DAlertVariant.destructive,
                description: DAlertDescription(child: Text(error)),
              ),
          ],
        ),
      ),
      DDialogFooter(
        children: [
          if (_recovery case final recovery?)
            PostMutationRecoveryButton(
              recovery: recovery,
              onRefreshed: _refreshed,
            ),
          if (widget.post.notice != null)
            DButton(
              key: const ValueKey('post-notice-delete'),
              label: Text(context.l10n.deleteNotice),
              onPressed: _saving || _requiresNewIntent
                  ? null
                  : () => unawaited(_set(null)),
              variant: DButtonVariant.destructive,
            ),
          DButton(
            label: Text(
              _requiresNewIntent ? context.l10n.close : context.l10n.cancel,
            ),
            onPressed: _saving ? null : widget.onClose,
            variant: DButtonVariant.outline,
          ),
          DButton(
            key: const ValueKey('post-notice-save'),
            label: Text(context.l10n.save),
            onPressed: _canSave ? () => unawaited(_set(_text.text)) : null,
            variant: DButtonVariant.primary,
            loading: _saving,
          ),
        ],
      ),
    ],
  );
}
