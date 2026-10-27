import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import '../models/post.dart';
import '../models/post_mutation_outcome.dart';
import 'platform.dart';
import 'post_mutation_feedback.dart';
import 'shell_controller.dart';
import 'shell_sheet.dart';

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
  bool canDismiss() => !(dialogKey.currentState?._saving ?? false);
  Widget editor({Widget? sheet}) => _PostNoticeDialog(
    key: dialogKey,
    controller: controller,
    target: target,
    post: post,
    sheet: sheet,
  );
  if (context.isTouch) {
    return showShellSheet<void>(
      context: context,
      title: _title(post),
      canDismiss: canDismiss,
      surfaceBuilder: (_, sheet) => editor(sheet: sheet),
      builder: (context) =>
          ShellSheetForm.of<_PostNoticeDialogState>(context)._body(context),
      footerBuilder: (context) => ShellSheetActions(
        children: ShellSheetForm.of<_PostNoticeDialogState>(
          context,
        )._actions(context),
      ),
    );
  }
  return showDDialog<void>(
    context: context,
    dismissOnBarrier: false,
    canDismiss: canDismiss,
    builder: (_, _) => editor(),
  );
}

String _title(Post post) =>
    post.notice == null ? appL10n.addPostNotice : appL10n.changePostNotice;

class _PostNoticeDialog extends StatefulWidget {
  const _PostNoticeDialog({
    super.key,
    required this.controller,
    required this.target,
    required this.post,
    this.sheet,
  });

  final ShellController controller;
  final PostNoticeTarget target;
  final Post post;

  /// The phone sheet's surface, whose body and actions read this form.
  final Widget? sheet;

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
      _close();
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
      _close();
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

  void _close() => DDialogClose.close<void>(context);

  Widget _body(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.sm,
    children: [
      if (widget.sheet != null)
        DSheetDescription(
          child: Text(context.l10n.thisStaffNoticeWillBeShownAboveThePost),
        ),
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
  );

  List<Widget> _actions(BuildContext context) => [
    if (_recovery case final recovery?)
      PostMutationRecoveryButton(recovery: recovery, onRefreshed: _refreshed),
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
      onPressed: _saving ? null : _close,
      variant: DButtonVariant.outline,
    ),
    DButton(
      key: const ValueKey('post-notice-save'),
      label: Text(context.l10n.save),
      onPressed: _canSave ? () => unawaited(_set(_text.text)) : null,
      variant: DButtonVariant.primary,
      loading: _saving,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.sheet case final sheet?) {
      return ShellSheetForm<_PostNoticeDialogState>(state: this, child: sheet);
    }
    return DDialogContent(
      key: const ValueKey('post-notice-dialog'),
      semanticLabel: _title(widget.post),
      showCloseButton: false,
      maxWidth: 548,
      children: [
        DDialogHeader(
          children: [
            DDialogTitle(child: Text(_title(widget.post))),
            DDialogDescription(
              child: Text(context.l10n.thisStaffNoticeWillBeShownAboveThePost),
            ),
          ],
        ),
        DDialogScrollArea(child: _body(context)),
        DDialogFooter(children: _actions(context)),
      ],
    );
  }
}
