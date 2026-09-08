import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/site_lifecycle.dart';
import '../models/post.dart';
import '../theme/d_button.dart';
import 'shell_controller.dart';
import 'shell_sheet.dart';

Future<void> showPostFastEditor({
  required BuildContext context,
  required ShellController controller,
  required String siteUrl,
  required int topicId,
  required Post post,
  required String selectedMarkdown,
}) {
  // Keep the opening account across sheet rebuilds and failed-save retries.
  final lease = controller.lifecycle.capture(siteUrl);
  return showShellSheet<void>(
    context: context,
    title: 'Edit',
    dialogOnDesktop: true,
    enableDrag: false,
    desktopDialogConstraints: const BoxConstraints(
      maxWidth: 560,
      maxHeight: 520,
    ),
    builder: (context) => _PostFastEditor(
      controller: controller,
      lease: lease,
      siteUrl: siteUrl,
      topicId: topicId,
      post: post,
      selectedMarkdown: selectedMarkdown,
    ),
  );
}

class _PostFastEditor extends StatefulWidget {
  const _PostFastEditor({
    required this.controller,
    required this.lease,
    required this.siteUrl,
    required this.topicId,
    required this.post,
    required this.selectedMarkdown,
  });

  final ShellController controller;
  final SiteLease lease;
  final String siteUrl;
  final int topicId;
  final Post post;
  final String selectedMarkdown;

  @override
  State<_PostFastEditor> createState() => _PostFastEditorState();
}

class _PostFastEditorState extends State<_PostFastEditor> {
  static const _accountChangedError =
      'The topic changed before the edit could be saved.';

  late final TextEditingController _text = TextEditingController(
    text: widget.selectedMarkdown,
  );
  bool _saving = false;
  String? _error;

  bool get _canSave => !_saving && _text.text != widget.selectedMarkdown;
  bool get _accountIsCurrent =>
      !widget.controller.accountSessionDisposed && widget.lease.isCurrent;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!mounted || !_canSave) return;
    if (!_accountIsCurrent) {
      setState(() => _error = _accountChangedError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saveError = await widget.controller.saveFastEdit(
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      post: widget.post,
      selectedMarkdown: widget.selectedMarkdown,
      replacement: _text.text,
    );
    if (!mounted) return;
    final error = _accountIsCurrent ? saveError : _accountChangedError;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  void _cancel() {
    if (!_saving) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_saving,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_save()),
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            style: Theme.of(context).textTheme.bodyLarge,
            key: const ValueKey('fast-edit-input'),
            controller: _text,
            autofocus: true,
            enabled: !_saving,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(
              labelText: 'Selected text',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
              key: const ValueKey('fast-edit-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DButton(
                key: const ValueKey('fast-edit-cancel'),
                label: const Text('Cancel'),
                onPressed: _saving ? null : _cancel,
              ),
              const SizedBox(width: 8),
              DButton(
                key: const ValueKey('fast-edit-save'),
                label: const Text('Save Edit'),
                loadingLabel: const Text('Saving…'),
                onPressed: _canSave ? () => unawaited(_save()) : null,
                variant: DButtonVariant.primary,
                loading: _saving,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
