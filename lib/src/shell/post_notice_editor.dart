import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
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
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _PostNoticeDialog(controller: controller, target: target, post: post),
  );
}

class _PostNoticeDialog extends StatefulWidget {
  const _PostNoticeDialog({
    required this.controller,
    required this.target,
    required this.post,
  });

  final ShellController controller;
  final PostNoticeTarget target;
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
    final error = await widget.controller.setPostNotice(widget.target, notice);
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
      widget.post.notice == null
          ? context.l10n.addPostNotice
          : context.l10n.changePostNotice,
    ),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.thisStaffNoticeWillBeShownAboveThePost),
          const SizedBox(height: 12),
          DTextarea(
            key: const ValueKey('post-notice-text'),
            controller: _text,
            autofocus: true,
            enabled: !_saving,
            minLines: 4,
            maxLines: 8,
            onChanged: (_) => setState(() => _error = null),
            labelText: context.l10n.notice,
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
        DButton(
          key: const ValueKey('post-notice-delete'),
          label: Text(context.l10n.deleteNotice),
          onPressed: _saving ? null : () => unawaited(_set(null)),
          variant: DButtonVariant.destructive,
        ),
      DButton(
        label: Text(context.l10n.cancel),
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
      ),
      DButton(
        key: const ValueKey('post-notice-save'),
        label: Text(context.l10n.save),
        onPressed: _canSave ? () => unawaited(_set(_text.text)) : null,
        variant: DButtonVariant.primary,
        loading: _saving,
      ),
    ],
  );
}
