import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/site_lifecycle.dart';
import '../models/post.dart';
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
  final editor = GlobalKey<_PostFastEditorState>();
  return showShellSheet<void>(
    context: context,
    title: appL10n.edit,
    dialogOnDesktop: true,
    enableDrag: false,
    canDismiss: () => !(editor.currentState?._saving ?? false),
    desktopDialogConstraints: const BoxConstraints(
      maxWidth: 560,
      maxHeight: 520,
    ),
    surfaceBuilder: (_, sheet) => _PostFastEditor(
      key: editor,
      controller: controller,
      lease: lease,
      siteUrl: siteUrl,
      topicId: topicId,
      post: post,
      selectedMarkdown: selectedMarkdown,
      sheet: sheet,
    ),
    builder: (context) =>
        ShellSheetForm.of<_PostFastEditorState>(context)._body(context),
    footerBuilder: (context) => ShellSheetActions(
      children: ShellSheetForm.of<_PostFastEditorState>(
        context,
      )._actions(context),
    ),
  );
}

class _PostFastEditor extends StatefulWidget {
  const _PostFastEditor({
    super.key,
    required this.controller,
    required this.lease,
    required this.siteUrl,
    required this.topicId,
    required this.post,
    required this.selectedMarkdown,
    required this.sheet,
  });

  final ShellController controller;
  final SiteLease lease;
  final String siteUrl;
  final int topicId;
  final Post post;
  final String selectedMarkdown;
  final Widget sheet;

  @override
  State<_PostFastEditor> createState() => _PostFastEditorState();
}

class _PostFastEditorState extends State<_PostFastEditor> {
  static String get _accountChangedError =>
      appL10n.theTopicChangedBeforeTheEditCouldBeSaved;

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
    _saving = false;
    DDialogClose.close<void>(context);
  }

  void _cancel() {
    if (!_saving) DDialogClose.close<void>(context);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
          unawaited(_save()),
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
          unawaited(_save()),
    },
    child: ShellSheetForm(state: this, child: widget.sheet),
  );

  Widget _body(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DTextarea(
        key: const ValueKey('fast-edit-input'),
        controller: _text,
        autofocus: true,
        enabled: !_saving,
        minLines: 3,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() => _error = null),
        labelText: context.l10n.selectedText,
      ),
      if (_error case final error?) ...[
        const SizedBox(height: 8),
        Text(
          error,
          key: const ValueKey('fast-edit-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );

  List<Widget> _actions(BuildContext context) => [
    DButton(
      key: const ValueKey('fast-edit-cancel'),
      label: Text(context.l10n.cancel),
      onPressed: _saving ? null : _cancel,
    ),
    DButton(
      key: const ValueKey('fast-edit-save'),
      label: Text(context.l10n.saveEditPostfastedit),
      loadingLabel: Text(context.l10n.saving),
      onPressed: _canSave ? () => unawaited(_save()) : null,
      variant: DButtonVariant.primary,
      loading: _saving,
    ),
  ];
}
